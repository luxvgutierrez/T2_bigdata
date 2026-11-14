"""
Pipeline de procesamiento en Spark: bronze -> silver -> gold.

Se ejecuta igual en local (Spark local[*]) y en Databricks (cluster):
solo cambian las rutas. La lógica de calidad es la misma que la ETL de
pandas, pero expresada como transformaciones distribuidas.

Uso local:
    python pipeline_spark.py --datos datos/escala_5x --salida salida/escala_5x
"""
import argparse
import json
import shutil
import time
from contextlib import contextmanager
from pathlib import Path

from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F

import config_spark as cfg


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
@contextmanager
def cronometro(metricas: dict, fase: str):
    """Mide una fase y la acumula en el diccionario de métricas."""
    inicio = time.perf_counter()
    try:
        yield
    finally:
        metricas.setdefault('fases', {})[fase] = round(time.perf_counter() - inicio, 3)


def _texto(col: str):
    """Columna de texto normalizada: recorta espacios y trata '' como NULL."""
    limpio = F.trim(F.col(col))
    return F.when(limpio == '', None).otherwise(limpio)


def _numero(col: str, tipo: str = 'int'):
    """
    Castea a número conservando la versión texto (para detectar basura).
    Se pasa por double para aceptar '79.0' sin romper; con ANSI desactivado,
    un valor no numérico ('ABC') queda en NULL y lo detecta la regla.
    """
    texto = _texto(col)
    if tipo in ('int', 'bigint'):
        return texto.cast('double').cast('bigint')
    return texto.cast('double')


def _booleano(col: str):
    return (F.when(_texto(col).isNull(), None)
            .otherwise(F.lower(_texto(col)).isin('true', '1', 't', 'si')))


# --------------------------------------------------------------------------
# BRONZE: lectura con esquema explícito + metadatos de ingesta
# --------------------------------------------------------------------------
def leer_bronze(spark, ruta_datos, tabla: str, id_lote: str) -> DataFrame:
    """
    Lee el CSV con esquema explícito (sin inferSchema) y agrega trazabilidad.
    Todas las columnas entran como texto: el tipado es responsabilidad de silver.
    """
    df = (spark.read
          .option('header', True)
          .option('encoding', 'UTF-8')
          .option('mode', 'PERMISSIVE')
          .schema(cfg.ESQUEMAS[tabla])
          .csv(cfg.ruta_uri(Path(ruta_datos) / f'{tabla}.csv')))

    return (df
            .withColumn('_id_lote', F.lit(id_lote))
            .withColumn('_fecha_carga', F.current_timestamp())
            .withColumn('_tabla_origen', F.lit(tabla)))


# --------------------------------------------------------------------------
# SILVER: tipado + reglas de calidad + cuarentena
# --------------------------------------------------------------------------
def _motivo_rechazo(df: DataFrame, tabla: str) -> DataFrame:
    """
    Construye una columna `_motivo` con la PRIMERA regla que falla.
    Reglas (en orden de precedencia):
      1. nulo en clave obligatoria
      2. valor no numérico donde se espera número
      3. medida negativa
      4. importe incoherente (importe != cantidad * precio)
      5. fecha inválida
      6. clave foránea huérfana
    """
    condiciones = []

    for col in cfg.CLAVES_OBLIGATORIAS.get(tabla, []):
        condiciones.append(F.when(F.col(col).isNull(), F.lit(f'nulo_clave:{col}')))

    for col in df.columns:
        if col.endswith('__txt'):
            original = col[:-5]
            condiciones.append(F.when(
                F.col(col).isNotNull() & F.col(original).isNull(),
                F.lit(f'no_numerico:{original}')))

    for col in df.columns:
        if col in cfg.COLUMNAS_ENTERAS | cfg.COLUMNAS_DECIMALES:
            condiciones.append(F.when(F.col(col) < 0, F.lit(f'negativo:{col}')))

    if tabla == 'Fact_Ventas':
        condiciones.append(F.when(
            F.abs(F.col('importe_total') - F.col('cantidad') * F.col('precio_unitario')) > cfg.TOLERANCIA_IMPORTE,
            F.lit('importe_incoherente:importe_total')))
    if tabla == 'Fact_Compras':
        condiciones.append(F.when(
            F.abs(F.col('subtotal') - F.col('cantidad') * F.col('precio_unitario')) > cfg.TOLERANCIA_IMPORTE,
            F.lit('importe_incoherente:subtotal')))

    for col in df.columns:
        if col.endswith('__fecha_txt'):
            original = col[:-11]
            condiciones.append(F.when(
                F.col(col).isNotNull() & F.col(original).isNull(),
                F.lit(f'fecha_invalida:{original}')))

    for col in df.columns:
        if col.endswith('__fk_ok'):
            original = col[:-7]
            condiciones.append(F.when(
                F.col(col) == F.lit(False), F.lit(f'huerfano:{original}')))

    if not condiciones:
        return df.withColumn('_motivo', F.lit(None).cast('string'))
    return df.withColumn('_motivo', F.coalesce(*condiciones))


def limpiar_tabla(df: DataFrame, tabla: str) -> tuple:
    """
    Devuelve (limpio, rechazados, conteos_por_regla, filas_limpias).
    - limpio: filas que cumplen todas las reglas (queda en caché)
    - rechazados: filas descartadas con su `motivo_rechazo`
    - conteos_por_regla: lista de {'regla', 'filas'} para el reporte de calidad
    - filas_limpias: conteo ya materializado (evita un job extra en el caller)
    """
    columnas_texto = [c for c in df.columns
                      if not c.startswith('_') and '__' not in c]

    # 1) Normalización de texto (CHAR con relleno de SQL Server)
    for col in columnas_texto:
        df = df.withColumn(col, _texto(col))

    # 2) Tipado explícito, conservando el texto original para validar
    for col in columnas_texto:
        if col.startswith('sk_') or col in cfg.COLUMNAS_ENTERAS:
            df = (df.withColumn(f'{col}__txt', F.col(col))
                    .withColumn(col, _numero(col, 'bigint')))
        elif col in cfg.COLUMNAS_DECIMALES:
            df = (df.withColumn(f'{col}__txt', F.col(col))
                    .withColumn(col, _numero(col, 'double')))
        elif col in cfg.COLUMNAS_FECHA:
            df = (df.withColumn(f'{col}__fecha_txt', F.col(col))
                    .withColumn(col, F.to_date(F.col(col), 'yyyy-MM-dd')))
        elif col in cfg.COLUMNAS_BOOLEANAS:
            df = df.withColumn(col, _booleano(col))
        else:
            df = df.withColumn(col, F.col(col).cast('string'))

    # 3) Integridad referencial: las columnas __fk_ok ya vienen marcadas por
    #    validar_referencias(); si la tabla no tiene FKs se dejan como True.
    for fk in cfg.CLAVES_FORANEAS.get(tabla, {}):
        if f'{fk}__fk_ok' not in df.columns:
            df = df.withColumn(f'{fk}__fk_ok', F.lit(True))

    # 4) Motivo de rechazo
    df = _motivo_rechazo(df, tabla)
    # Se materializa UNA vez: limpio y rechazados salen del mismo cálculo
    df = df.persist()

    auxiliares = [c for c in df.columns if '__' in c]
    limpio = (df.filter(F.col('_motivo').isNull())
                .drop('_motivo', *auxiliares))
    rechazados = (df.filter(F.col('_motivo').isNotNull())
                    .withColumnRenamed('_motivo', 'motivo_rechazo')
                    .drop(*auxiliares))

    # 5) Duplicados por clave primaria (se conserva la primera aparición)
    pk = cfg.CLAVES_PRIMARIAS[tabla]
    ventana = Window.partitionBy(*pk).orderBy(F.monotonically_increasing_id())
    marcado = limpio.withColumn('_rn', F.row_number().over(ventana))
    duplicados = (marcado.filter(F.col('_rn') > 1)
                        .drop('_rn')
                        .withColumn('motivo_rechazo', F.lit('duplicado:clave_primaria')))
    limpio = marcado.filter(F.col('_rn') == 1).drop('_rn').cache()

    rechazados = rechazados.unionByName(duplicados, allowMissingColumns=True)

    # 6) Conteo por regla y materialización de la capa limpia
    conteos = (rechazados
               .withColumn('regla', F.split(F.col('motivo_rechazo'), ':').getItem(0))
               .groupBy('regla').count()
               .withColumnRenamed('count', 'filas')
               .collect())
    conteos = [{'regla': c['regla'], 'filas': c['filas']} for c in conteos]

    filas_limpias = limpio.count()  # materializa (queda en caché)
    df.unpersist()

    return limpio, rechazados, conteos, filas_limpias


def validar_referencias(df: DataFrame, tabla: str, dims: dict) -> DataFrame:
    """
    Marca las FK que no existen en la dimensión. Usa broadcast join porque las
    dimensiones son pequeñas frente a los hechos.
    """
    for fk, (dim, pk) in cfg.CLAVES_FORANEAS.get(tabla, {}).items():
        if dim not in dims:
            continue
        validas = dims[dim].select(F.col(pk).cast('bigint').alias('_vk')).distinct()
        df = df.join(F.broadcast(validas),
                     df[fk].cast('bigint') == F.col('_vk'), 'left')
        df = (df.withColumn(f'{fk}__fk_ok', F.col('_vk').isNotNull())
                .drop('_vk'))
    return df


# --------------------------------------------------------------------------
# GOLD: modelo en estrella listo para BI
# --------------------------------------------------------------------------
def construir_gold(silver: dict, ruta_salida, particionar: bool = True,
                   formato: str = 'parquet', escribir: bool = True) -> dict:
    """
    Publica la capa gold:
      - Hechos enriquecidos con `fecha` y `anio_mes` (partición).
      - Marts agregados para Power BI.
    """
    calendario = (silver['Dim_Tiempo']
                  .select('sk_tiempo', 'fecha', 'anio', 'mes',
                          F.date_format('fecha', 'yyyy-MM').alias('anio_mes')))

    hechos = {}
    for tabla in cfg.HECHOS:
        if tabla not in silver:
            continue
        df = silver[tabla]
        if 'sk_tiempo' in df.columns:
            df = (df.join(F.broadcast(calendario), 'sk_tiempo', 'left')
                    .withColumn('anio_mes', F.col('anio_mes').cast('string')))
        hechos[tabla] = df

    marts = {}
    if 'Fact_Ventas' in hechos:
        marts['mart_ventas_mes_producto'] = (
            hechos['Fact_Ventas']
            .groupBy('anio_mes', 'sk_producto')
            .agg(F.sum('importe_total').alias('importe_total'),
                 F.sum('cantidad').alias('unidades'),
                 F.round(F.avg('precio_unitario'), 2).alias('precio_promedio'),
                 F.countDistinct('nro_comprobante').alias('comprobantes')))
    if 'Fact_Inventario_Snapshot' in hechos:
        ultimo = Window.partitionBy('sk_producto').orderBy(F.col('fecha').desc())
        marts['mart_stock_ultimo_dia'] = (
            hechos['Fact_Inventario_Snapshot']
            .withColumn('_rn', F.row_number().over(ultimo))
            .filter(F.col('_rn') == 1).drop('_rn')
            .select('sk_producto', 'fecha', 'anio_mes', 'stock_cantidad'))

    publicados = {}
    if escribir:
        destino = Path(ruta_salida)
        for nombre, df in {**hechos, **marts}.items():
            ruta = destino / nombre
            _limpiar_destino(ruta)
            escritor = df.write.mode('overwrite')
            if formato == 'parquet':
                if particionar and 'anio_mes' in df.columns and nombre in hechos:
                    # Un archivo por partición (mes) en lugar de uno por tarea:
                    # evita cientos de archivos pequeños que degradan a Power BI.
                    (df.repartition(F.col('anio_mes'))
                       .write.mode('overwrite')
                       .partitionBy('anio_mes')
                       .parquet(cfg.ruta_uri(ruta)))
                else:
                    escritor.parquet(cfg.ruta_uri(ruta))
            else:
                escritor.option('header', True).csv(cfg.ruta_uri(ruta))
            publicados[nombre] = df.count()

    return {'hechos': hechos, 'marts': marts, 'publicados': publicados}


def _limpiar_destino(ruta: Path) -> None:
    """
    Borra el destino antes de reescribir (evita particiones obsoletas).
    Funciona en rutas locales y en Volumes de Unity Catalog (FUSE).
    Para sistemas como dbfs:/ o s3:/ se deja que Spark haga el overwrite.
    """
    texto = str(ruta)
    if texto.startswith(('dbfs:', 's3:', 's3a:', 'abfss:')):
        return
    if ruta.exists():
        shutil.rmtree(ruta, ignore_errors=True)


# --------------------------------------------------------------------------
# Orquestador
# --------------------------------------------------------------------------
def ejecutar_pipeline(spark, ruta_datos, ruta_salida, formato: str = 'parquet',
                      particionar: bool = True, escribir: bool = True,
                      id_lote: str = None, guardar_metricas: bool = True) -> dict:
    """
    Ejecuta las tres capas y devuelve métricas de tiempo, volumen y calidad.
    """
    id_lote = id_lote or time.strftime('%Y%m%d_%H%M%S')
    metricas = {'id_lote': id_lote, 'formato': formato,
                'particionado': particionar, 'tablas': {}, 'calidad': []}

    # ---------------- BRONZE ----------------
    bronze = {}
    with cronometro(metricas, 'bronze'):
        for tabla in cfg.TABLAS:
            bronze[tabla] = leer_bronze(spark, ruta_datos, tabla, id_lote)
            metricas['tablas'].setdefault(tabla, {})['bronze'] = bronze[tabla].count()

    # ---------------- SILVER ----------------
    silver = {}
    dims = {}
    with cronometro(metricas, 'silver'):
        # Primero las dimensiones: son la referencia para validar los hechos
        for tabla in cfg.DIMENSIONES:
            df = validar_referencias(bronze[tabla], tabla, {})
            limpio, rechazados, conteos, filas_limpias = limpiar_tabla(df, tabla)
            dims[tabla] = limpio
            silver[tabla] = limpio
            metricas['tablas'][tabla].update({
                'silver': filas_limpias,
                'rechazados': sum(c['filas'] for c in conteos),
                'huerfanas': sum(c['filas'] for c in conteos
                                 if c['regla'] == 'huerfano'),
            })
            for c in conteos:
                metricas['calidad'].append({'tabla': tabla, **c})

        for tabla in cfg.HECHOS:
            df = validar_referencias(bronze[tabla], tabla, dims)
            limpio, rechazados, conteos, filas_limpias = limpiar_tabla(df, tabla)
            silver[tabla] = limpio
            metricas['tablas'][tabla].update({
                'silver': filas_limpias,
                'rechazados': sum(c['filas'] for c in conteos),
                'huerfanas': sum(c['filas'] for c in conteos
                                 if c['regla'] == 'huerfano'),
            })
            for c in conteos:
                metricas['calidad'].append({'tabla': tabla, **c})

    # ---------------- GOLD ----------------
    with cronometro(metricas, 'gold'):
        gold = construir_gold(silver, ruta_salida, particionar, formato, escribir)
        metricas['filas_gold'] = sum(gold['publicados'].values())

    metricas['filas_silver'] = sum(
        m['silver'] for m in metricas['tablas'].values())
    metricas['filas_bronze'] = sum(
        m['bronze'] for m in metricas['tablas'].values())
    metricas['filas_rechazadas'] = sum(
        m['rechazados'] for m in metricas['tablas'].values())
    metricas['duracion_total'] = round(
        sum(metricas['fases'].values()), 3)

    for df in silver.values():
        df.unpersist()

    if guardar_metricas:
        destino = Path(ruta_salida)
        destino.mkdir(parents=True, exist_ok=True)
        (destino / '_metricas.json').write_text(
            json.dumps(metricas, indent=2, ensure_ascii=False), encoding='utf-8')

    return metricas


def main():
    parser = argparse.ArgumentParser(description='Pipeline Spark bronze->silver->gold')
    parser.add_argument('--datos', default=str(cfg.RUTA_DATOS / 'escala_1x'))
    parser.add_argument('--salida', default=str(cfg.RUTA_SALIDA / 'escala_1x'))
    parser.add_argument('--formato', default='parquet', choices=['parquet', 'csv'])
    parser.add_argument('--sin-particionar', action='store_true')
    parser.add_argument('--shuffle', type=int, default=None)
    args = parser.parse_args()

    spark = cfg.crear_spark(shuffle_partitions=args.shuffle)
    try:
        metricas = ejecutar_pipeline(
            spark, args.datos, args.salida, formato=args.formato,
            particionar=not args.sin_particionar)
        print(json.dumps(metricas, indent=2, ensure_ascii=False))
    finally:
        spark.stop()


if __name__ == '__main__':
    main()
