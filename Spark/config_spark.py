"""
Configuración común del procesamiento con Spark (local y Databricks).

Reglas de diseño:
  - Los esquemas son EXPLÍCITOS (StructType). No se usa inferSchema: en un lake
    con millones de filas, inferir el esquema obliga a leer el archivo dos veces
    y permite que un valor sucio cambie el tipo de una columna completa.
  - Todas las columnas se leen como texto en bronze; el tipado ocurre en silver.
    Así se conservan los ceros a la izquierda de las claves de negocio
    ('000001', 'T00001'), igual que en la ETL de pandas.
  - Las rutas se resuelven con `as_uri()` para que funcionen en Windows, Linux
    y en el sistema de archivos de Databricks (dbfs:/ o /Volumes/).
"""
import os
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql.types import StringType, StructField, StructType

# --------------------------------------------------------------------------
# Entorno
# --------------------------------------------------------------------------
EN_DATABRICKS = 'DATABRICKS_RUNTIME_VERSION' in os.environ

try:
    BASE_PROYECTO = Path(__file__).resolve().parent.parent
except NameError:  # en un notebook de Databricks no siempre existe __file__
    BASE_PROYECTO = Path(os.getcwd()).parent

RUTA_RAW = BASE_PROYECTO / 'ETL' / 'raw'
RUTA_SPARK = BASE_PROYECTO / 'Spark'
RUTA_DATOS = RUTA_SPARK / 'datos'
RUTA_SALIDA = RUTA_SPARK / 'salida'
RUTA_RESULTADOS = RUTA_SPARK / 'resultados'


def ruta_uri(ruta) -> str:
    """Convierte una ruta local en URI file:///... (idempotente)."""
    texto = str(ruta)
    if '://' in texto:
        return texto
    # Rutas nativas de Databricks: Spark las resuelve con su FS por defecto
    if texto.startswith(('/Volumes', '/dbfs', '/FileStore')):
        return texto
    camino = Path(texto)
    if not camino.is_absolute():
        camino = (Path.cwd() / camino).resolve()
    return camino.as_uri()


# --------------------------------------------------------------------------
# Esquemas explícitos (todas las columnas como texto en bronze)
# --------------------------------------------------------------------------
def esquema(columnas) -> StructType:
    return StructType([StructField(c, StringType(), True) for c in columnas])


ESQUEMAS = {
    'Dim_Cliente': esquema([
        'sk_cliente', 'id_cliente', 'dni', 'nombres', 'apellidos',
        'fecha_nacimiento', 'correo', 'telefono', 'tipo_cliente', 'direccion',
        'fecha_inicio', 'fecha_fin', 'es_vigente',
    ]),
    'Dim_Producto': esquema([
        'sk_producto', 'cod_producto', 'descripcion', 'cod_tipo_producto',
        'tipo_producto', 'estado_producto', 'precio_lista', 'fecha_inicio',
        'fecha_fin', 'es_vigente',
    ]),
    'Dim_Proveedor': esquema([
        'sk_proveedor', 'id_provedor', 'nombre_proveedor', 'cod_tipo_provedor',
        'tipo_proveedor', 'limite_credito', 'plazo_pago_dias', 'tipo_pago',
        'estado_credito', 'tiene_delivery', 'telefono', 'fecha_inicio',
        'fecha_fin', 'es_vigente',
    ]),
    'Dim_Tiempo': esquema([
        'sk_tiempo', 'fecha', 'anio', 'trimestre', 'mes', 'nombre_mes',
        'dia', 'dia_semana', 'nombre_dia', 'es_fin_semana',
    ]),
    'Dim_Trabajador': esquema([
        'sk_trabajador', 'id_trabajador', 'dni', 'nombres', 'apellidos',
        'fecha_nacimiento', 'tipo_trabajador', 'cat_laboral', 'fecha_inicio',
        'fecha_fin', 'es_vigente',
    ]),
    'Fact_Ventas': esquema([
        'sk_fact_venta', 'sk_tiempo', 'sk_cliente', 'sk_trabajador',
        'sk_producto', 'sk_condicion_venta', 'nro_comprobante', 'id_detalle',
        'cantidad', 'importe_total', 'precio_unitario',
    ]),
    'Fact_Compras': esquema([
        'sk_fact_compra', 'sk_tiempo', 'sk_proveedor', 'sk_trabajador',
        'sk_producto', 'sk_documento_ingreso', 'id_ingreso',
        'id_detalle_ingreso', 'nro_documento', 'cantidad', 'precio_unitario',
        'subtotal',
    ]),
    'Fact_Inventario_Snapshot': esquema([
        'sk_tiempo', 'sk_producto', 'stock_cantidad',
    ]),
}

# Columnas de negocio (texto que NUNCA se convierte a número)
CLAVES_NEGOCIO = {
    'id_cliente', 'id_trabajador', 'id_provedor', 'id_detalle', 'id_ingreso',
    'id_detalle_ingreso', 'cod_producto', 'cod_tipo_producto',
    'cod_tipo_provedor', 'dni', 'nro_documento', 'telefono', 'correo',
}

# Contrato de tipos (idéntico al de la ETL de pandas: ETL/utilidades.py)
TOLERANCIA_IMPORTE = 0.05  # misma tolerancia por redondeo que reglas_limpieza.py
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

# Clave primaria (grano) de cada tabla
CLAVES_PRIMARIAS = {
    'Dim_Cliente': ['sk_cliente'],
    'Dim_Producto': ['sk_producto'],
    'Dim_Proveedor': ['sk_proveedor'],
    'Dim_Tiempo': ['sk_tiempo'],
    'Dim_Trabajador': ['sk_trabajador'],
    'Fact_Ventas': ['sk_fact_venta'],
    'Fact_Compras': ['sk_fact_compra'],
    'Fact_Inventario_Snapshot': ['sk_tiempo', 'sk_producto'],
}

# Claves de negocio que deben ser únicas (SCD-2: una versión vigente por clave)
CLAVES_NEGOCIO_UNICAS = {
    'Dim_Cliente': 'id_cliente',
    'Dim_Producto': 'cod_producto',
    'Dim_Proveedor': 'id_provedor',
    'Dim_Trabajador': 'id_trabajador',
}

# Integridad referencial: columna -> (tabla dimensión, clave)
CLAVES_FORANEAS = {
    'Fact_Ventas': {
        'sk_tiempo': ('Dim_Tiempo', 'sk_tiempo'),
        'sk_cliente': ('Dim_Cliente', 'sk_cliente'),
        'sk_trabajador': ('Dim_Trabajador', 'sk_trabajador'),
        'sk_producto': ('Dim_Producto', 'sk_producto'),
    },
    'Fact_Compras': {
        'sk_tiempo': ('Dim_Tiempo', 'sk_tiempo'),
        'sk_proveedor': ('Dim_Proveedor', 'sk_proveedor'),
        'sk_trabajador': ('Dim_Trabajador', 'sk_trabajador'),
        'sk_producto': ('Dim_Producto', 'sk_producto'),
    },
    'Fact_Inventario_Snapshot': {
        'sk_tiempo': ('Dim_Tiempo', 'sk_tiempo'),
        'sk_producto': ('Dim_Producto', 'sk_producto'),
    },
}

# Columnas obligatorias (no pueden ser nulas) por tabla
CLAVES_OBLIGATORIAS = {
    'Dim_Cliente': ['sk_cliente', 'id_cliente'],
    'Dim_Producto': ['sk_producto', 'cod_producto'],
    'Dim_Proveedor': ['sk_proveedor', 'id_provedor'],
    'Dim_Tiempo': ['sk_tiempo', 'fecha'],
    'Dim_Trabajador': ['sk_trabajador', 'id_trabajador'],
    'Fact_Ventas': ['sk_fact_venta', 'sk_tiempo', 'sk_cliente', 'sk_producto'],
    'Fact_Compras': ['sk_fact_compra', 'sk_tiempo', 'sk_proveedor', 'sk_producto'],
    'Fact_Inventario_Snapshot': ['sk_tiempo', 'sk_producto'],
}

# Tablas del modelo y su rol
DIMENSIONES = ['Dim_Cliente', 'Dim_Producto', 'Dim_Proveedor', 'Dim_Tiempo',
               'Dim_Trabajador']
HECHOS = ['Fact_Ventas', 'Fact_Compras', 'Fact_Inventario_Snapshot']
TABLAS = DIMENSIONES + HECHOS


# --------------------------------------------------------------------------
# Sesión de Spark
# --------------------------------------------------------------------------
def crear_spark(app: str = 'T2-BigData', shuffle_partitions: int = None,
                aqe: bool = True, memoria_driver: str = '4g') -> SparkSession:
    """Crea (o reutiliza) la SparkSession con una configuración reproducible."""
    confs = {
        'spark.sql.adaptive.enabled': str(aqe).lower(),
        'spark.sql.adaptive.coalescePartitions.enabled': str(aqe).lower(),
        'spark.sql.session.timeZone': 'America/Lima',
        'spark.sql.parquet.compression.codec': 'snappy',
        'spark.sql.sources.partitionOverwriteMode': 'dynamic',
        # Las reglas de calidad necesitan que un cast inválido devuelva NULL
        # (y no aborte el job): 'ABC' -> NULL -> fila rechazada con motivo.
        'spark.sql.ansi.enabled': 'false',
        'spark.driver.memory': memoria_driver,
    }
    if shuffle_partitions is not None:
        confs['spark.sql.shuffle.partitions'] = str(shuffle_partitions)
    elif not EN_DATABRICKS:
        # En local los datasets son pequeños: 200 particiones generan cientos
        # de tareas vacías y dominan el tiempo total.
        confs['spark.sql.shuffle.partitions'] = '8'

    constructor = SparkSession.builder.appName(app)
    for clave, valor in confs.items():
        constructor = constructor.config(clave, valor)
    spark = constructor.getOrCreate()

    # En Databricks la sesión ya existe: el builder no aplica los confs.
    for clave, valor in confs.items():
        try:
            spark.conf.set(clave, valor)
        except Exception:
            pass  # confs inmutables en runtime (p. ej. memoria del driver)

    spark.sparkContext.setLogLevel('WARN')
    return spark
