"""
Configuración central de la ETL.
Toda ruta es absoluta y relativa a la carpeta del proyecto (no al CWD),
para que los scripts funcionen igual desde donde sea que se ejecuten.
"""
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Capas de la arquitectura (medallion: bronze -> silver -> gold)
CARPETA_RAW = os.path.join(BASE_DIR, 'raw')
CARPETA_PROCESSED = os.path.join(BASE_DIR, 'processed')
CARPETA_RECHAZADOS = os.path.join(BASE_DIR, 'processed', 'rechazados')
CARPETA_CURATED = os.path.join(BASE_DIR, 'curated')
CARPETA_GOLD_PARQUET = os.path.join(CARPETA_CURATED, 'tablas')
CARPETA_GOLD_POWERBI = os.path.join(CARPETA_CURATED, 'para_powerbi')
CARPETA_AUDITORIA = os.path.join(BASE_DIR, 'auditoria')

# Formato de la capa gold: 'parquet' (columnar, particionado) + CSV plano para Power BI
FORMATO_GOLD = 'parquet'
PARTICIONAR_POR_MES = True
# Columnas de trazabilidad agregadas en la capa bronze (id_lote, fecha_carga, tabla_origen)
AGREGAR_METADATOS_CARGA = True

# Conexión a SQL Server (mover credenciales a un .env si cambia de servidor)
SERVER = 'MONITOR'
DATABASE = 'proyecto_dw'
DRIVER = 'ODBC Driver 17 for SQL Server'
TIMEOUT_CONEXION_SEG = 30

# Orden garantizado: primero dimensiones, luego puente y hechos
# (la validación referencial necesita las dimensiones ya limpias)
TABLAS_DIMENSIONES = [
    'Dim_Producto',
    'Dim_Cliente',
    'Dim_Proveedor',
    'Dim_Trabajador',
    'Dim_Condicion_Venta',
    'Dim_Documento_Ingreso',
    'Dim_Tiempo',
]
TABLAS_PUENTE = ['Bridge_Abastecimiento']
TABLAS_HECHOS = [
    'Fact_Ventas',
    'Fact_Compras',
    'Fact_Inventario_Snapshot',
]
# Tablas que se validan contra las dimensiones (hechos + puente)
TABLAS_CON_REFERENCIAL = TABLAS_PUENTE + TABLAS_HECHOS
TABLAS = TABLAS_DIMENSIONES + TABLAS_PUENTE + TABLAS_HECHOS


def crear_engine():
    """Crea el engine de SQLAlchemy de forma perezosa (solo cuando se extrae)."""
    import urllib
    from sqlalchemy import create_engine

    params = urllib.parse.quote_plus(
        f'DRIVER={DRIVER};SERVER={SERVER};DATABASE={DATABASE};'
        f'Trusted_Connection=yes;'
    )
    return create_engine(
        f'mssql+pyodbc:///?odbc_connect={params}',
        pool_pre_ping=True,
        connect_args={'timeout': TIMEOUT_CONEXION_SEG},
    )
