"""
Auditoría de la ETL (RNF03):
- Registra cada fase con su tiempo de respuesta (duración en segundos).
- Escribe log de la corrida, resumen JSON e histórico CSV apendado por corrida.
"""
import csv
import json
import os
import time
from contextlib import contextmanager
from datetime import datetime

CAMPOS_HISTORICO = [
    'id_corrida', 'inicio', 'fin', 'duracion_total_seg',
    'eventos_ok', 'eventos_error', 'estado_global',
]

ETAPAS_VALIDAS = (
    'CONEXION', 'EXTRACCION', 'LIMPIEZA', 'VALIDACION_REFERENCIAL',
    'CUARENTENA', 'SISTEMA',
)


class _Crono:
    """Objeto que el llamador llena durante la fase con métricas/mensaje."""

    def __init__(self):
        self.detalle = {}
        self.mensaje = ''


class Auditoria:
    def __init__(self, carpeta: str):
        os.makedirs(carpeta, exist_ok=True)
        self.carpeta = carpeta
        self.id_corrida = datetime.now().strftime('%Y%m%d_%H%M%S')
        self.ruta_log = os.path.join(carpeta, f'corrida_{self.id_corrida}.log')
        self.ruta_resumen = os.path.join(carpeta, f'resumen_corrida_{self.id_corrida}.json')
        self.ruta_historico = os.path.join(carpeta, 'historico_corridas.csv')
        self._t_inicio = time.perf_counter()
        self._inicio_dt = datetime.now()
        self.eventos = []
        self._log(f'=== INICIO DE CORRIDA {self.id_corrida} ===')

    # ------------------------------------------------------------------ #
    # Registro de eventos
    # ------------------------------------------------------------------ #
    def _log(self, mensaje: str) -> None:
        linea = f'[{datetime.now():%Y-%m-%d %H:%M:%S}] {mensaje}'
        print(linea)
        try:
            with open(self.ruta_log, 'a', encoding='utf-8') as f:
                print(linea, file=f)
        except OSError:
            pass  # el logging a archivo nunca debe romper la ETL

    @contextmanager
    def cronometrar(self, etapa: str, tabla: str = ''):
        """
        Mide el tiempo de respuesta de la fase completa.
        Uso:
            with auditoria.cronometrar('EXTRACCION', tabla) as crono:
                ...
                crono.detalle = {'filas_leidas': 5000}
            (si la fase lanza excepción queda registrada como ERROR y se propaga)
        """
        crono = _Crono()
        t0 = time.perf_counter()
        try:
            yield crono
        except Exception as exc:
            self._registrar(etapa, tabla, 'ERROR', time.perf_counter() - t0, str(exc), {})
            raise
        else:
            self._registrar(
                etapa, tabla, 'OK', time.perf_counter() - t0,
                crono.mensaje, crono.detalle,
            )

    def registrar_simple(self, etapa: str, tabla: str = '', mensaje: str = '') -> None:
        """Evento informativo sin cronómetro (avisos, reintentos, etc.)."""
        self._registrar(etapa, tabla, 'INFO', None, mensaje, {})

    def _registrar(self, etapa, tabla, estado, duracion, mensaje, detalle):
        evento = {
            'fecha_hora': datetime.now().isoformat(timespec='seconds'),
            'etapa': etapa,
            'tabla': tabla,
            'estado': estado,
            'duracion_seg': round(duracion, 3) if duracion is not None else None,
        }
        evento.update(detalle)
        if mensaje:
            evento['mensaje'] = mensaje
        self.eventos.append(evento)

        partes = [f'[{etapa}{"/" + tabla if tabla else ""}] {estado}'
                  + (f' en {evento["duracion_seg"]} s' if duracion is not None else '')]
        for clave in ('filas_leidas', 'filas_descartadas', 'filas_salida', 'huerfanos'):
            if clave in evento:
                partes.append(f'{clave}={evento[clave]}')
        if mensaje:
            partes.append(mensaje)
        self._log(' | '.join(partes))

    # ------------------------------------------------------------------ #
    # Consultas
    # ------------------------------------------------------------------ #
    @property
    def hay_errores(self) -> bool:
        return any(e['estado'] == 'ERROR' for e in self.eventos)

    # ------------------------------------------------------------------ #
    # Cierre de la corrida
    # ------------------------------------------------------------------ #
    def finalizar(self) -> dict:
        fin_dt = datetime.now()
        duracion_total = round(time.perf_counter() - self._t_inicio, 3)
        n_error = sum(1 for e in self.eventos if e['estado'] == 'ERROR')
        n_ok = sum(1 for e in self.eventos if e['estado'] == 'OK')

        resumen = {
            'id_corrida': self.id_corrida,
            'corpus': 'ETL BigData T2',
            'inicio': self._inicio_dt.isoformat(timespec='seconds'),
            'fin': fin_dt.isoformat(timespec='seconds'),
            'duracion_total_seg': duracion_total,
            'estado_global': 'CON_ERRORES' if self.hay_errores else 'EXITOSO',
            'eventos_ok': n_ok,
            'eventos_error': n_error,
            'fases': self.eventos,
        }

        # 1. Resumen JSON de la corrida (auditoría detallada)
        try:
            with open(self.ruta_resumen, 'w', encoding='utf-8') as f:
                json.dump(resumen, f, ensure_ascii=False, indent=2)
        except OSError as exc:
            self._log(f'AVISO: no se pudo escribir el resumen JSON: {exc}')

        # 2. Histórico CSV apendado (una fila por corrida)
        try:
            existe = os.path.exists(self.ruta_historico)
            with open(self.ruta_historico, 'a', newline='', encoding='utf-8') as f:
                escritor = csv.DictWriter(f, fieldnames=CAMPOS_HISTORICO)
                if not existe:
                    escritor.writeheader()
                escritor.writerow({
                    'id_corrida': self.id_corrida,
                    'inicio': resumen['inicio'],
                    'fin': resumen['fin'],
                    'duracion_total_seg': duracion_total,
                    'eventos_ok': n_ok,
                    'eventos_error': n_error,
                    'estado_global': resumen['estado_global'],
                })
        except OSError as exc:
            self._log(f'AVISO: no se pudo actualizar el histórico: {exc}')

        self._log(
            f'=== FIN DE CORRIDA {self.id_corrida} | '
            f'duración total: {duracion_total} s | '
            f'estado: {resumen["estado_global"]} ==='
        )
        return resumen
