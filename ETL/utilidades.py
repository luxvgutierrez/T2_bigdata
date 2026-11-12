"""Utilidades comunes de la ETL."""
import os
import shutil
import tempfile

import pandas as pd

from config import (
    CARPETA_RAW,
    CARPETA_PROCESSED,
    CARPETA_RECHAZADOS,
)

# --------------------------------------------------------------------------
# Contrato de tipos del lake (mismo en silver y gold).
# Las CLAVES DE NEGOCIO son texto (CHAR(6) en la BD: '000001', 'T00001') y
# NUNCA deben convertirse a número: se perderían los ceros a la izquierda.
# --------------------------------------------------------------------------
COLUMNAS_ENTERAS = {
    'cantidad', 'stock_cantidad', 'anio', 'trimestre', 'mes', 'dia',
    'dia_semana', 'plazo_pago_dias', 'nro_comprobante', 'estado_pago',
}
COLUMNAS_DECIMALES = {
    'importe_total', 'subtotal', 'precio_unitario', 'precio_lista',
    'limite_credito', 'precio_abastecimiento',
}
COLUMNAS_FECHA = {'fecha', 'fecha_nacimiento', 'fecha_inicio', 'fecha_fin'}
COLUMNAS_BOOLEANAS = {'es_vigente', 'es_fin_semana', 'tiene_delivery'}
COLUMNAS_TEXTO = {
    'id_cliente', 'id_trabajador', 'id_provedor', 'id_detalle', 'id_ingreso',
    'id_detalle_ingreso', 'cod_producto', 'cod_tipo_producto', 'cod_tipo_provedor',
    'dni', 'nro_documento',
}


def _tipar_columna(serie: pd.Series, columna: str) -> pd.Series:
    """Aplica el tipo declarado en el contrato a una columna leída como texto."""
    if columna.startswith('sk_'):
        return pd.to_numeric(serie, errors='coerce').astype('Int64')
    if columna in COLUMNAS_ENTERAS:
        return pd.to_numeric(serie, errors='coerce').astype('Int64')
    if columna in COLUMNAS_DECIMALES:
        return pd.to_numeric(serie, errors='coerce').astype('Float64').round(2)
    if columna in COLUMNAS_FECHA:
        fechas = pd.to_datetime(serie, errors='coerce')
        return fechas.dt.normalize() if columna == 'fecha' else fechas
    if columna in COLUMNAS_BOOLEANAS:
        valores = serie.astype(str).str.strip().str.lower()
        return valores.isin(['true', '1', 't', 'si'])
    if columna in COLUMNAS_TEXTO:
        return serie.astype('string').str.strip()
    if serie.dtype == object or pd.api.types.is_string_dtype(serie):
        return serie.astype('string').str.strip()
    return serie


def leer_csv_contrato(ruta: str) -> pd.DataFrame:
    """
    Lee un CSV del lake aplicando el contrato de tipos.

    Se lee TODO como texto (dtype=str) para no perder los ceros a la izquierda
    de las claves de negocio ('000001', 'T00001'); recién después se convierte
    cada columna a su tipo declarado.
    """
    df = pd.read_csv(ruta, dtype=str, keep_default_na=False, na_values=[''])
    for col in df.columns:
        df[col] = _tipar_columna(df[col], col)
    return df


def escribir_csv_atomico(df: pd.DataFrame, ruta: str) -> None:
    """
    Escritura atómica: primero escribe a un archivo temporal y luego lo renombra.
    Así un corte a mitad de ejecución nunca deja un CSV corrupto en la capa final.
    """
    tmp = f'{ruta}.tmp'
    df.to_csv(tmp, index=False, encoding='utf-8')
    os.replace(tmp, ruta)


def ruta_raw(tabla: str) -> str:
    return os.path.join(CARPETA_RAW, f'{tabla}.csv')


def ruta_procesado(tabla: str) -> str:
    return os.path.join(CARPETA_PROCESSED, f'{tabla}_Limpio.csv')


def ruta_rechazados(tabla: str) -> str:
    return os.path.join(CARPETA_RECHAZADOS, f'{tabla}_rechazadas.csv')


def ruta_huerfanos(tabla: str) -> str:
    return os.path.join(CARPETA_RECHAZADOS, f'{tabla}_huerfanas.csv')


def guardar_cuarentena(df_rechazados: pd.DataFrame, tabla: str, tipo: str = 'rechazadas'):
    """
    Guarda las filas rechazadas con su motivo en la carpeta de cuarentena.
    tipo: 'rechazadas' (reglas RNF03) o 'huerfanas' (falla referencial).
    Devuelve la ruta escrita, o None si no hubo rechazos.
    """
    if df_rechazados is None or df_rechazados.empty:
        return None
    os.makedirs(CARPETA_RECHAZADOS, exist_ok=True)
    ruta = ruta_huerfanos(tabla) if tipo == 'huerfanas' else ruta_rechazados(tabla)
    escribir_csv_atomico(df_rechazados, ruta)
    return ruta


def escribir_capa(df: pd.DataFrame, ruta_destino: str, formato: str = 'parquet',
                  columnas_particion=None) -> str:
    """
    Escritura de la capa gold:
      - 'parquet' -> directorio particionado (columnar, comprimido) o archivo único
      - 'csv'     -> archivo plano UTF-8
    En ambos casos es atómica: se escribe en un temporal y se publica al final.
    """
    if df is None or df.empty:
        return None

    if formato == 'parquet':
        padre = os.path.dirname(ruta_destino)
        if padre:
            os.makedirs(padre, exist_ok=True)
        tmp_dir = tempfile.mkdtemp(prefix='._tmp_gold_', dir=padre or None)
        try:
            if columnas_particion:
                df.to_parquet(
                    tmp_dir, engine='pyarrow', compression='snappy',
                    index=False, partition_cols=list(columnas_particion),
                )
            else:
                df.to_parquet(
                    os.path.join(tmp_dir, 'datos.parquet'),
                    engine='pyarrow', compression='snappy', index=False,
                )
            if os.path.isdir(ruta_destino):
                shutil.rmtree(ruta_destino)
            elif os.path.exists(ruta_destino):
                os.remove(ruta_destino)
            os.replace(tmp_dir, ruta_destino)
        finally:
            if os.path.isdir(tmp_dir):
                shutil.rmtree(tmp_dir, ignore_errors=True)
        return ruta_destino

    escribir_csv_atomico(df, ruta_destino)
    return ruta_destino
