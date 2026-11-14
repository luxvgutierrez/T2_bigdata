# Databricks notebook source
# MAGIC %md
# MAGIC # T2 BigData — Data Lake con Spark en Databricks
# MAGIC
# MAGIC Pipeline **bronze → silver → gold** sobre los CSV del minimarket, con
# MAGIC reglas de calidad, cuarentena y modelo en estrella en Parquet.
# MAGIC
# MAGIC **Cómo usarlo (Free Edition, desde el navegador):**
# MAGIC 1. *Workspace* → tu carpeta → **Create → Notebook** (o *Import* de este `.py`).
# MAGIC 2. Adjuntar un cluster (*Serverless* o *Single node*).
# MAGIC 3. Elegir los parámetros con los *widgets* y **Run all**.
# MAGIC
# MAGIC El notebook **descarga el código y los datos reales** desde el repositorio
# MAGIC (rama `jesusdev`), así que no hay que subir archivos a mano.
# MAGIC
# MAGIC > Si el cluster no tiene salida a Internet, subir la carpeta `Spark/` y los
# MAGIC > 8 CSV de `ETL/raw/` a un Volume y ajustar las rutas de las celdas 2 y 3.

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Parámetros

# COMMAND ----------

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

dbutils.widgets.dropdown('escala', '5', ['1', '2', '5', '10', '25'], 'Escala del dataset')
dbutils.widgets.dropdown('errores', '0', ['0', '0.01', '0.05'], 'Errores inyectados (calidad)')
dbutils.widgets.dropdown('experimentos', 'false', ['false', 'true'], 'Ejecutar experimentos')
dbutils.widgets.text('rama', 'jesusdev', 'Rama del repositorio')
dbutils.widgets.text('ruta_base', '', 'Carpeta base (vacío = automática)')

ESCALA = int(dbutils.widgets.get('escala'))
ERRORES = float(dbutils.widgets.get('errores'))
EXPERIMENTOS = dbutils.widgets.get('experimentos') == 'true'
RAMA = dbutils.widgets.get('rama')
RUTA_BASE_MANUAL = dbutils.widgets.get('ruta_base').strip()
REPO = f'https://raw.githubusercontent.com/luxvgutierrez/T2_bigdata/{RAMA}'

print(f'Escala={ESCALA} | errores={ERRORES:.0%} | experimentos={EXPERIMENTOS} | rama={RAMA}')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Carpeta de trabajo
# MAGIC
# MAGIC Se busca una ruta escribible: primero un **Volume** de Unity Catalog y,
# MAGIC si no existe, `/tmp` (válido en clusters de un solo nodo).

# COMMAND ----------

def probar_escritura(ruta: str) -> bool:
    try:
        os.makedirs(ruta, exist_ok=True)
        prueba = os.path.join(ruta, '.escritura_ok')
        with open(prueba, 'w') as f:
            f.write('ok')
        os.remove(prueba)
        return True
    except Exception as error:
        print(f'  no disponible: {ruta} ({type(error).__name__})')
        return False


def resolver_base() -> str:
    candidatos = []
    for catalogo in ('workspace', 'main', 'hive_metastore'):
        candidatos.append(f'/Volumes/{catalogo}/default/t2_bigdata')
    candidatos.append('/tmp/t2_bigdata')

    for ruta in candidatos:
        if ruta.startswith('/Volumes'):
            nombre = ruta[len('/Volumes/'):].replace('/', '.')
            try:
                spark.sql(f'CREATE VOLUME IF NOT EXISTS {nombre}')
            except Exception:
                pass  # sin permiso o catálogo inexistente: se prueba la ruta
        if probar_escritura(ruta):
            return ruta
    raise RuntimeError('No hay una carpeta escribible: crea un Volume o usa /tmp')


BASE = RUTA_BASE_MANUAL if RUTA_BASE_MANUAL else resolver_base()
if RUTA_BASE_MANUAL and not probar_escritura(BASE):
    raise RuntimeError(f'La carpeta indicada no es escribible: {BASE}')
print('Carpeta de trabajo:', BASE)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Código y datos desde el repositorio

# COMMAND ----------

def descargar(url: str, destino: str, intentos: int = 3) -> None:
    for intento in range(1, intentos + 1):
        try:
            urllib.request.urlretrieve(url, destino)
            return
        except Exception:
            if intento == intentos:
                raise
            time.sleep(2 * intento)


DIR_CODIGO = '/tmp/t2_codigo'
os.makedirs(DIR_CODIGO, exist_ok=True)
MODULOS = ('config_spark.py', 'generador_sintetico.py',
           'pipeline_spark.py', 'experimentos.py')

try:
    for modulo in MODULOS:
        destino = os.path.join(DIR_CODIGO, modulo)
        descargar(f'{REPO}/Spark/{modulo}', destino)
        print(f'  {modulo:<24} {os.path.getsize(destino):>6} bytes')
    ORIGEN_CODIGO = 'github'
except Exception as error:
    # Sin salida a Internet: se usan los módulos subidos a mano al Volume
    alterno = os.path.join(BASE, 'codigo')
    print(f'No se pudo descargar del repositorio ({type(error).__name__}).')
    print(f'Buscando módulos en {alterno} ...')
    if not all(os.path.exists(os.path.join(alterno, m)) for m in MODULOS):
        raise RuntimeError(
            'Sin Internet y sin módulos en el Volume. Sube la carpeta Spark/ '
            f'a {alterno} (o habilita la salida a Internet del cluster).'
        ) from error
    DIR_CODIGO = alterno
    ORIGEN_CODIGO = 'volume'

sys.path.insert(0, DIR_CODIGO)

TABLAS = ['Dim_Cliente', 'Dim_Producto', 'Dim_Proveedor', 'Dim_Tiempo',
          'Dim_Trabajador', 'Fact_Ventas', 'Fact_Compras',
          'Fact_Inventario_Snapshot']

DIR_REAL = os.path.join(BASE, 'raw_real')
os.makedirs(DIR_REAL, exist_ok=True)
try:
    for tabla in TABLAS:
        destino = os.path.join(DIR_REAL, f'{tabla}.csv')
        if not os.path.exists(destino) or os.path.getsize(destino) == 0:
            descargar(f'{REPO}/ETL/raw/{tabla}.csv', destino)
    ORIGEN_DATOS = 'github'
except Exception as error:
    faltan = [t for t in TABLAS
              if not os.path.exists(os.path.join(DIR_REAL, f'{t}.csv'))]
    if faltan:
        raise RuntimeError(
            'Sin Internet y faltan CSV en el Volume: ' + ', '.join(faltan)
        ) from error
    ORIGEN_DATOS = 'volume'

print(f'Código: {ORIGEN_CODIGO} ({DIR_CODIGO}) | datos: {ORIGEN_DATOS} ({DIR_REAL})')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Módulos del proyecto

# COMMAND ----------

import importlib

import config_spark as cfg
import experimentos as exp
import generador_sintetico as gen
import pipeline_spark as pipe

importlib.reload(cfg)
importlib.reload(gen)
importlib.reload(pipe)
importlib.reload(exp)

# Pocas particiones de shuffle: los datasets de este trabajo son pequeños y
# 200 particiones generarían cientos de tareas vacías.
for clave, valor in {
    'spark.sql.shuffle.partitions': str(max(8, min(200, ESCALA * 8))),
    'spark.sql.adaptive.enabled': 'true',
    # Un cast inválido debe devolver NULL (fila rechazada), no abortar el job
    'spark.sql.ansi.enabled': 'false',
}.items():
    try:
        spark.conf.set(clave, valor)
    except Exception as error:
        print(f'No se pudo configurar {clave}: {error}')
print('Spark', spark.version, '| particiones de shuffle:',
      spark.conf.get('spark.sql.shuffle.partitions'))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Dataset de entrada
# MAGIC
# MAGIC - `escala = 1` y sin errores → se usan los datos reales.
# MAGIC - `escala > 1` → dataset sintético con dimensiones ampliadas e integridad
# MAGIC   referencial garantizada.
# MAGIC - `errores > 0` → se corrompe una fracción de las ventas y se guarda la
# MAGIC   **verdad** en `_verdad_errores.csv` para medir la detección.

# COMMAND ----------

if ESCALA == 1 and ERRORES == 0:
    RUTA_DATOS = DIR_REAL
    print('Usando datos reales:', RUTA_DATOS)
else:
    etiqueta = f'escala_{ESCALA}x'
    if ERRORES:
        etiqueta += f'_err{int(round(ERRORES * 100))}pct'
    RUTA_DATOS = os.path.join(BASE, 'datos', etiqueta)
    if not os.path.exists(os.path.join(RUTA_DATOS, 'Fact_Ventas.csv')):
        print(f'Generando {etiqueta}...')
        manifiesto = gen.construir_dataset(
            ESCALA, Path(RUTA_DATOS), fraccion_errores=ERRORES,
            ruta_raw=Path(DIR_REAL))
        print(json.dumps(manifiesto, indent=2, ensure_ascii=False))
    else:
        print('Dataset ya generado:', RUTA_DATOS)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Pipeline bronze → silver → gold

# COMMAND ----------

RUTA_SALIDA = os.path.join(BASE, 'gold', os.path.basename(RUTA_DATOS))
metricas = pipe.ejecutar_pipeline(
    spark,
    ruta_datos=RUTA_DATOS,
    ruta_salida=RUTA_SALIDA,
    formato='parquet',
    particionar=True,
)
print('Gold en:', RUTA_SALIDA)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. Resultados: volumen, tiempos y calidad

# COMMAND ----------

import pandas as pd

resumen = pd.DataFrame([{'tabla': tabla, **valores}
                        for tabla, valores in metricas['tablas'].items()])
display(resumen)

print('Fases (s):', metricas['fases'])
print('Filas bronze :', metricas['filas_bronze'])
print('Filas silver :', metricas['filas_silver'])
print('Rechazadas   :', metricas['filas_rechazadas'])
print('Filas gold   :', metricas['filas_gold'])
print('Duración     :', metricas['duracion_total'], 's')

if metricas['calidad']:
    display(spark.createDataFrame(pd.DataFrame(metricas['calidad'])))
else:
    print('Sin rechazos: todas las filas cumplen las reglas.')

# COMMAND ----------

# MAGIC %md
# MAGIC ### Verificación de la capa gold

# COMMAND ----------

ventas = spark.read.parquet(os.path.join(RUTA_SALIDA, 'Fact_Ventas'))
display(ventas.groupBy('anio_mes')
        .agg({'importe_total': 'sum', 'cantidad': 'sum'})
        .orderBy('anio_mes'))

stock = spark.read.parquet(os.path.join(RUTA_SALIDA, 'mart_stock_ultimo_dia'))
print('Stock del último día por producto:', stock.count(), 'filas')
display(stock.orderBy(stock['stock_cantidad'].desc()).limit(10))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8. Experimentos (opcional)
# MAGIC
# MAGIC Con `experimentos = true` se ejecutan:
# MAGIC - **E1** escalado (una escala),
# MAGIC - **E2** CSV vs Parquet,
# MAGIC - **E3** particionado,
# MAGIC - **E5** calidad con 1% y 5% de errores inyectados.
# MAGIC
# MAGIC Los resultados quedan en `<BASE>/resultados/`.

# COMMAND ----------

if EXPERIMENTOS:
    bitacora = exp.Bitacora()
    dir_datos = Path(BASE) / 'datos'
    dir_salida = Path(BASE) / 'gold'

    exp.exp_escalado(spark, [ESCALA], dir_datos, dir_salida, bitacora,
                     ruta_raw=Path(DIR_REAL))
    exp.exp_formatos(spark, dir_datos, dir_salida, bitacora, ESCALA,
                     ruta_raw=Path(DIR_REAL))
    exp.exp_particionado(spark, dir_salida, bitacora, ESCALA)
    exp.exp_shuffle(spark, dir_salida, bitacora, ESCALA)
    exp.exp_calidad(spark, [0.01, 0.05], dir_datos, bitacora,
                    ruta_raw=Path(DIR_REAL))
    exp.exportar(bitacora, Path(BASE) / 'resultados')
    display(bitacora.dataframe())

# COMMAND ----------

# MAGIC %md
# MAGIC ## 9. Salida del notebook (para un Job)

# COMMAND ----------

dbutils.notebook.exit(json.dumps({
    'escala': ESCALA,
    'errores': ERRORES,
    'filas_bronze': metricas['filas_bronze'],
    'filas_silver': metricas['filas_silver'],
    'filas_rechazadas': metricas['filas_rechazadas'],
    'filas_gold': metricas['filas_gold'],
    'duracion_total_s': metricas['duracion_total'],
    'ruta_gold': RUTA_SALIDA,
}))
