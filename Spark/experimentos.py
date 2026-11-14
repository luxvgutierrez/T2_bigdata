"""
Experimentos del procesamiento con Spark.

Mide, con datos reales y sintéticos:
  E1. Escalado       : tiempo por fase y throughput al crecer el volumen.
  E2. Formato        : CSV vs Parquet (lectura, escritura y tamaño).
  E3. Particionado   : escribir/leer particionado por anio_mes vs archivo único.
  E4. Shuffle        : efecto de spark.sql.shuffle.partitions en una agregación.
  E5. Calidad        : recall/precisión de las reglas con errores inyectados.

Salidas:
  resultados/experimentos.csv   (formato largo: experimento, configuracion, metrica, valor)
  resultados/experimentos.json  (métricas completas)
  resultados/experimentos.md    (tablas listas para el informe)

Uso:
    python experimentos.py --escalas 1,5,10
    python experimentos.py --escalas 5 --calidad 0.01,0.05
"""
import argparse
import json
import time
from pathlib import Path

import pandas as pd

import config_spark as cfg
import generador_sintetico as gen
from pipeline_spark import (ejecutar_pipeline, leer_bronze, limpiar_tabla,
                            validar_referencias)


# --------------------------------------------------------------------------
# Utilidades de medición
# --------------------------------------------------------------------------
def medir(funcion):
    """Ejecuta una acción de Spark y devuelve (resultado, segundos)."""
    inicio = time.perf_counter()
    resultado = funcion()
    return resultado, round(time.perf_counter() - inicio, 3)


def tamano_mb(ruta) -> float:
    """Tamaño en disco de un archivo o directorio (solo rutas locales)."""
    ruta = Path(ruta)
    if not ruta.exists():
        return 0.0
    if ruta.is_file():
        return round(ruta.stat().st_size / 1024 / 1024, 2)
    total = sum(f.stat().st_size for f in ruta.rglob('*') if f.is_file())
    return round(total / 1024 / 1024, 2)


class Bitacora:
    """Acumula resultados en formato largo para exportarlos a CSV/Markdown."""

    def __init__(self):
        self.filas = []
        self.json = {}

    def agregar(self, experimento, configuracion, metrica, valor, unidad=''):
        self.filas.append({
            'experimento': experimento,
            'configuracion': configuracion,
            'metrica': metrica,
            'valor': valor,
            'unidad': unidad,
        })

    def dataframe(self) -> pd.DataFrame:
        return pd.DataFrame(self.filas)


# --------------------------------------------------------------------------
# E1. Escalado
# --------------------------------------------------------------------------
def exp_escalado(spark, escalas, ruta_datos: Path, ruta_salida: Path, bit: Bitacora,
                 ruta_raw: Path = None):
    resultados = []
    for escala in escalas:
        datos = ruta_datos / f'escala_{escala}x'
        if not datos.exists():
            print(f'  generando dataset {escala}x...')
            gen.construir_dataset(escala, datos, ruta_raw=ruta_raw)
        salida = ruta_salida / f'escala_{escala}x'
        print(f'  E1: pipeline escala {escala}x...')
        metricas = ejecutar_pipeline(spark, datos, salida, formato='parquet',
                                     particionar=True)

        filas = metricas['filas_silver']
        total = metricas['duracion_total']
        fila = {
            'escala': escala,
            'filas_bronze': metricas['filas_bronze'],
            'filas_silver': filas,
            'filas_rechazadas': metricas['filas_rechazadas'],
            'filas_gold': metricas['filas_gold'],
            't_bronze_s': metricas['fases'].get('bronze', 0),
            't_silver_s': metricas['fases'].get('silver', 0),
            't_gold_s': metricas['fases'].get('gold', 0),
            't_total_s': total,
            'filas_por_segundo': round(filas / total, 1) if total else 0,
            'tamano_gold_mb': tamano_mb(salida),
        }
        resultados.append(fila)
        for clave, valor in fila.items():
            if clave == 'escala':
                continue
            unidad = 's' if clave.endswith('_s') else ('MB' if clave.endswith('_mb')
                                                       else ('filas/s' if 'segundo' in clave else ''))
            bit.agregar('E1_escalado', f'{escala}x', clave, valor, unidad)

    bit.json['E1_escalado'] = resultados
    return resultados


# --------------------------------------------------------------------------
# E2. CSV vs Parquet
# --------------------------------------------------------------------------
def exp_formatos(spark, ruta_datos: Path, ruta_salida: Path, bit: Bitacora,
                 escala: int = 10, ruta_raw: Path = None):
    datos = ruta_datos / f'escala_{escala}x'
    if not datos.exists():
        gen.construir_dataset(escala, datos, ruta_raw=ruta_raw)
    tabla = 'Fact_Inventario_Snapshot'
    ruta_csv = datos / f'{tabla}.csv'
    ruta_parquet = ruta_salida / '_exp_formatos' / tabla

    df = (spark.read.option('header', True)
          .schema(cfg.ESQUEMAS[tabla]).csv(cfg.ruta_uri(ruta_csv)))
    filas, t_csv = medir(df.count)
    _, t_escribir = medir(lambda: df.write.mode('overwrite').parquet(
        cfg.ruta_uri(ruta_parquet)))
    _, t_parquet = medir(lambda: spark.read.parquet(
        cfg.ruta_uri(ruta_parquet)).count())

    mb_csv = tamano_mb(ruta_csv)
    mb_parquet = tamano_mb(ruta_parquet)

    resultado = {
        'tabla': tabla, 'filas': filas,
        't_lectura_csv_s': t_csv, 't_lectura_parquet_s': t_parquet,
        't_escritura_parquet_s': t_escribir,
        'mb_csv': mb_csv, 'mb_parquet': mb_parquet,
        'factor_compresion': round(mb_csv / mb_parquet, 2) if mb_parquet else None,
        'aceleracion_lectura': round(t_csv / t_parquet, 2) if t_parquet else None,
    }
    for clave, valor in resultado.items():
        if clave in ('tabla', 'filas'):
            continue
        bit.agregar('E2_formatos', f'snapshot_{escala}x', clave, valor,
                    's' if clave.startswith('t_') else ('MB' if clave.startswith('mb') else 'x'))

    bit.json['E2_formatos'] = resultado
    return resultado


# --------------------------------------------------------------------------
# E3. Particionado
# --------------------------------------------------------------------------
def exp_particionado(spark, ruta_salida: Path, bit: Bitacora, escala: int = 10):
    origen = ruta_salida / f'escala_{escala}x' / 'Fact_Ventas'
    if not origen.exists():
        print(f'  E3 omitido: falta la salida de escala {escala}x')
        return None

    ventas = spark.read.parquet(cfg.ruta_uri(origen))
    base = ruta_salida / '_exp_particionado'
    ruta_unica = base / 'ventas_unica'
    ruta_part = base / 'ventas_particionada'

    _, t_unica = medir(lambda: ventas.write.mode('overwrite').parquet(
        cfg.ruta_uri(ruta_unica)))
    _, t_part = medir(lambda: ventas.write.mode('overwrite')
                      .partitionBy('anio_mes').parquet(cfg.ruta_uri(ruta_part)))

    # Lectura con filtro por mes: el particionado permite poda de archivos
    lee_unica = spark.read.parquet(cfg.ruta_uri(ruta_unica))
    lee_part = spark.read.parquet(cfg.ruta_uri(ruta_part))
    filas_unica, t_lee_unica = medir(
        lambda: lee_unica.filter("anio_mes = '2026-03'").count())
    filas_part, t_lee_part = medir(
        lambda: lee_part.filter("anio_mes = '2026-03'").count())

    resultado = {
        'filas_totales': ventas.count(),
        't_escritura_unica_s': t_unica,
        't_escritura_particionada_s': t_part,
        'mb_unica': tamano_mb(ruta_unica),
        'mb_particionada': tamano_mb(ruta_part),
        'filas_mes': filas_part,
        't_lectura_mes_unica_s': t_lee_unica,
        't_lectura_mes_particionada_s': t_lee_part,
        'aceleracion_lectura_filtrada': round(t_lee_unica / t_lee_part, 2)
        if t_lee_part else None,
        'particiones': len([p for p in ruta_part.glob('anio_mes=*')]),
    }
    for clave, valor in resultado.items():
        bit.agregar('E3_particionado', 'ventas_10x', clave, valor,
                    's' if clave.startswith('t_') else ('MB' if clave.startswith('mb') else ''))

    bit.json['E3_particionado'] = resultado
    return resultado


# --------------------------------------------------------------------------
# E4. Particiones de shuffle
# --------------------------------------------------------------------------
def exp_shuffle(spark, ruta_salida: Path, bit: Bitacora, escala: int = 10):
    origen = ruta_salida / f'escala_{escala}x' / 'Fact_Inventario_Snapshot'
    if not origen.exists():
        print(f'  E4 omitido: falta la salida de escala {escala}x')
        return None

    df = spark.read.parquet(cfg.ruta_uri(origen))
    resultados = []
    aqe_previo = spark.conf.get('spark.sql.adaptive.enabled', 'true')
    shuffle_previo = spark.conf.get('spark.sql.shuffle.partitions', '200')
    spark.conf.set('spark.sql.adaptive.enabled', 'false')  # comparación justa

    try:
        for particiones in (4, 16, 64, 200):
            spark.conf.set('spark.sql.shuffle.partitions', str(particiones))
            agregado = (df.groupBy('anio_mes', 'sk_producto')
                          .agg({'stock_cantidad': 'sum'}))
            _, segundos = medir(agregado.count)
            resultados.append({'shuffle_partitions': particiones,
                               't_agregacion_s': segundos})
            bit.agregar('E4_shuffle', f'{particiones} particiones',
                        't_agregacion_s', segundos, 's')
    finally:
        # Restaurar la configuración previa (no un valor fijo): el resto de la
        # batería debe seguir usando las particiones con las que se inició.
        spark.conf.set('spark.sql.adaptive.enabled', aqe_previo)
        spark.conf.set('spark.sql.shuffle.partitions', shuffle_previo)

    bit.json['E4_shuffle'] = resultados
    return resultados


# --------------------------------------------------------------------------
# E5. Calidad: errores inyectados con verdad conocida
# --------------------------------------------------------------------------
def exp_calidad(spark, fracciones, ruta_datos: Path, bit: Bitacora,
                ruta_raw: Path = None):
    resultados = []
    for fraccion in fracciones:
        etiqueta = f'{int(round(fraccion * 100))}pct'
        datos = ruta_datos / f'calidad_{etiqueta}'
        if not datos.exists():
            print(f'  generando dataset con {etiqueta} de errores...')
            gen.construir_dataset(escala=2, ruta_salida=datos,
                                  fraccion_errores=fraccion, ruta_raw=ruta_raw)
        print(f'  E5: calidad con {etiqueta} de errores...')

        # Dimensiones limpias (referencia para las FK)
        dims = {}
        for tabla in cfg.DIMENSIONES:
            bronze = leer_bronze(spark, datos, tabla, 'exp_calidad')
            limpio, _, _, _ = limpiar_tabla(
                validar_referencias(bronze, tabla, {}), tabla)
            dims[tabla] = limpio.cache()

        bronze = leer_bronze(spark, datos, 'Fact_Ventas', 'exp_calidad')
        _, rechazados, _, conteos = limpiar_tabla(
            validar_referencias(bronze, 'Fact_Ventas', dims), 'Fact_Ventas')
        detectados = rechazados.select('sk_fact_venta', 'motivo_rechazo').toPandas()
        detectados['sk_fact_venta'] = detectados['sk_fact_venta'].astype(str)
        for df in dims.values():
            df.unpersist()

        verdad = pd.read_csv(datos / '_verdad_errores.csv', dtype=str)
        verdad['id_fila'] = verdad['id_fila'].astype(str)

        ids_verdad = set(verdad['id_fila'])
        ids_detectados = set(detectados['sk_fact_venta'])

        por_tipo = {}
        for tipo, grupo in verdad.groupby('tipo_error'):
            ids_tipo = set(grupo['id_fila'])
            detectados_tipo = ids_tipo & ids_detectados
            por_tipo[tipo] = {
                'inyectados': len(ids_tipo),
                'detectados': len(detectados_tipo),
                'recall': round(len(detectados_tipo) / len(ids_tipo), 3)
                if ids_tipo else None,
            }

        total_verdad = len(ids_verdad)
        total_det = len(ids_detectados)
        aciertos = len(ids_verdad & ids_detectados)
        resultado = {
            'fraccion_inyectada': fraccion,
            'filas_ventas': int(len(pd.read_csv(datos / 'Fact_Ventas.csv',
                                                usecols=['sk_fact_venta']))),
            'errores_inyectados': int(len(verdad)),
            'ids_con_error': total_verdad,
            'ids_detectados': total_det,
            'recall_global': round(aciertos / total_verdad, 3) if total_verdad else None,
            'precision_global': round(aciertos / total_det, 3) if total_det else None,
            'falsos_positivos': max(0, total_det - aciertos),
            'por_tipo': por_tipo,
        }
        resultados.append(resultado)

        bit.agregar('E5_calidad', etiqueta, 'recall_global',
                    resultado['recall_global'])
        bit.agregar('E5_calidad', etiqueta, 'precision_global',
                    resultado['precision_global'])
        for tipo, datos_tipo in por_tipo.items():
            bit.agregar('E5_calidad', f'{etiqueta}:{tipo}', 'recall',
                        datos_tipo['recall'])

    bit.json['E5_calidad'] = resultados
    return resultados


# --------------------------------------------------------------------------
# Exportación
# --------------------------------------------------------------------------
def exportar(bit: Bitacora, ruta_resultados: Path):
    ruta_resultados.mkdir(parents=True, exist_ok=True)
    df = bit.dataframe()
    df.to_csv(ruta_resultados / 'experimentos.csv', index=False, encoding='utf-8')
    (ruta_resultados / 'experimentos.json').write_text(
        json.dumps(bit.json, indent=2, ensure_ascii=False, default=str),
        encoding='utf-8')

    def tabla_md(filas, columnas):
        encabezado = '| ' + ' | '.join(columnas) + ' |'
        separador = '|' + '|'.join(['---'] * len(columnas)) + '|'
        cuerpo = ['| ' + ' | '.join(str(f.get(c, '')) for c in columnas) + ' |'
                  for f in filas]
        return '\n'.join([encabezado, separador, *cuerpo])

    partes = ['# Resultados de los experimentos con Spark', '']
    if bit.json.get('E1_escalado'):
        partes += ['## E1. Escalado', '',
                   tabla_md(bit.json['E1_escalado'],
                            ['escala', 'filas_silver', 't_bronze_s', 't_silver_s',
                             't_gold_s', 't_total_s', 'filas_por_segundo',
                             'tamano_gold_mb']), '']
    if bit.json.get('E2_formatos'):
        partes += ['## E2. CSV vs Parquet', '',
                   tabla_md([bit.json['E2_formatos']],
                            ['tabla', 'filas', 't_lectura_csv_s',
                             't_lectura_parquet_s', 'mb_csv', 'mb_parquet',
                             'factor_compresion', 'aceleracion_lectura']), '']
    if bit.json.get('E3_particionado'):
        partes += ['## E3. Particionado por mes', '',
                   tabla_md([bit.json['E3_particionado']],
                            ['filas_totales', 't_escritura_unica_s',
                             't_escritura_particionada_s', 't_lectura_mes_unica_s',
                             't_lectura_mes_particionada_s',
                             'aceleracion_lectura_filtrada', 'particiones']), '']
    if bit.json.get('E4_shuffle'):
        partes += ['## E4. Particiones de shuffle', '',
                   tabla_md(bit.json['E4_shuffle'],
                            ['shuffle_partitions', 't_agregacion_s']), '']
    if bit.json.get('E5_calidad'):
        partes += ['## E5. Calidad (errores inyectados)', '',
                   tabla_md(bit.json['E5_calidad'],
                            ['fraccion_inyectada', 'errores_inyectados',
                             'ids_con_error', 'ids_detectados', 'recall_global',
                             'precision_global', 'falsos_positivos']), '']
        for resultado in bit.json['E5_calidad']:
            partes += [f"### Recall por tipo de error — "
                       f"{resultado['fraccion_inyectada']:.0%}", '',
                       tabla_md([{'tipo_error': k, **v}
                                 for k, v in resultado['por_tipo'].items()],
                                ['tipo_error', 'inyectados', 'detectados',
                                 'recall']), '']

    (ruta_resultados / 'experimentos.md').write_text('\n'.join(partes),
                                                     encoding='utf-8')
    print(f'\n[OK] resultados en {ruta_resultados}')


def main():
    parser = argparse.ArgumentParser(description='Experimentos Spark')
    parser.add_argument('--escalas', default='1,5,10')
    parser.add_argument('--calidad', default='0,0.01,0.05',
                        help='Fracciones de error a probar (coma)')
    parser.add_argument('--solo', default='E1,E2,E3,E4,E5')
    parser.add_argument('--datos', default=str(cfg.RUTA_DATOS))
    parser.add_argument('--salida', default=str(cfg.RUTA_SALIDA))
    parser.add_argument('--resultados', default=str(cfg.RUTA_RESULTADOS))
    parser.add_argument('--raw', default=None,
                        help='Carpeta con los CSV reales (por defecto ETL/raw)')
    parser.add_argument('--shuffle', type=int, default=None)
    args = parser.parse_args()

    escalas = [int(e) for e in args.escalas.split(',') if e.strip()]
    fracciones = [float(f) for f in args.calidad.split(',') if f.strip()]
    solo = {s.strip().upper() for s in args.solo.split(',')}
    ruta_datos = Path(args.datos)
    ruta_salida = Path(args.salida)
    bit = Bitacora()
    escala_mayor = max(escalas)
    ruta_raw = Path(args.raw) if args.raw else None

    spark = cfg.crear_spark(app='T2-Experimentos',
                            shuffle_partitions=args.shuffle)
    # Calentamiento: paga el arranque de la JVM antes de medir (si no, la
    # primera escala parece mucho más lenta de lo que es).
    spark.range(1000).count()
    inicio = time.perf_counter()
    try:
        if 'E1' in solo:
            print('E1. Escalado')
            exp_escalado(spark, escalas, ruta_datos, ruta_salida, bit,
                         ruta_raw=ruta_raw)
        if 'E2' in solo:
            print('E2. Formatos')
            exp_formatos(spark, ruta_datos, ruta_salida, bit, escala_mayor,
                         ruta_raw=ruta_raw)
        if 'E3' in solo:
            print('E3. Particionado')
            exp_particionado(spark, ruta_salida, bit, escala_mayor)
        if 'E4' in solo:
            print('E4. Shuffle')
            exp_shuffle(spark, ruta_salida, bit, escala_mayor)
        if 'E5' in solo:
            print('E5. Calidad')
            exp_calidad(spark, fracciones, ruta_datos, bit, ruta_raw=ruta_raw)
    finally:
        print(f'Duración total de la batería: {time.perf_counter() - inicio:.1f} s')
        exportar(bit, Path(args.resultados))
        spark.stop()


if __name__ == '__main__':
    main()
