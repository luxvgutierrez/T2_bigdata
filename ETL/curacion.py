"""
Capa GOLD (curated): proyección del modelo en estrella para el BI.

Responsabilidades:
  - Tipos definitivos (Int64 / Float64 / date / boolean / string).
  - Columnas derivadas: anio_mes (clave de particionado) y fecha (para los hechos).
  - Particionado mensual en Parquet + copia plana CSV para Power BI.
  - Eliminación de los metadatos de ingestión (id_lote, fecha_carga, tabla_origen).
"""
import os

import pandas as pd

import config
from utilidades import COLUMNAS_BOOLEANAS, COLUMNAS_DECIMALES, COLUMNAS_FECHA, leer_csv_contrato

# Las claves de negocio (id_cliente, id_trabajador, cod_producto...) son TEXTO:
# son CHAR(6) en la BD ('000001', 'T00001') y convertirlas a número perdería
# los ceros a la izquierda. Solo se tipan las claves surrogate (sk_*) y las
# medidas declaradas como numéricas.

COLUMNAS_METADATOS = ('id_lote', 'fecha_carga', 'tabla_origen')


def _es_de_tipo(columna: str, prefijos) -> bool:
    return any(columna == p or columna.startswith(p) for p in prefijos)


def tipar_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """Aplica los tipos definitivos del contrato a cada columna."""
    df = df.copy()
    for col in df.columns:
        serie = df[col]
        if col.startswith('sk_'):
            df[col] = pd.to_numeric(serie, errors='coerce').astype('Int64')
        elif col in COLUMNAS_DECIMALES:
            df[col] = pd.to_numeric(serie, errors='coerce').astype('Float64').round(2)
        elif col in COLUMNAS_FECHA:
            fechas = pd.to_datetime(serie, errors='coerce')
            df[col] = fechas.dt.normalize() if col == 'fecha' else fechas
        elif col in COLUMNAS_BOOLEANAS:
            valores = serie.astype(str).str.strip().str.lower()
            df[col] = valores.isin(['true', '1', 't', 'si'])
        elif serie.dtype == object or pd.api.types.is_string_dtype(serie):
            df[col] = serie.astype('string').str.strip()
    return df


def agregar_columnas_derivadas(df: pd.DataFrame, tabla: str, dim_tiempo: pd.DataFrame) -> pd.DataFrame:
    """
    Agrega 'anio_mes' (YYYY-MM) y 'fecha' a los hechos, derivándolos de Dim_Tiempo.
    'anio_mes' es la clave de particionado de la capa gold.
    """
    df = df.copy()
    if tabla.startswith('Fact_') and 'sk_tiempo' in df.columns and dim_tiempo is not None:
        if 'fecha' not in dim_tiempo.columns or 'sk_tiempo' not in dim_tiempo.columns:
            return df
        calendario = dim_tiempo[['sk_tiempo', 'fecha']].copy()
        calendario['fecha'] = pd.to_datetime(calendario['fecha'], errors='coerce')
        calendario['anio_mes'] = calendario['fecha'].dt.strftime('%Y-%m')
        df = df.merge(calendario, on='sk_tiempo', how='left')
        df['anio_mes'] = df['anio_mes'].astype('string')
    return df


def es_tabla_factua(tabla: str) -> bool:
    return tabla.startswith('Fact_')


def construir_capa_gold(datos_por_tabla: dict, formato: str = None,
                        particionar: bool = None) -> dict:
    """
    Construye la capa gold a partir de los DataFrames limpios (silver).

    datos_por_tabla : {nombre_tabla: DataFrame limpio}
    Devuelve un dict con las rutas escritas y las filas publicadas por tabla.
    """
    formato = formato or config.FORMATO_GOLD
    particionar = config.PARTICIONAR_POR_MES if particionar is None else particionar

    dim_tiempo = datos_por_tabla.get('Dim_Tiempo')
    resultados = {}

    for tabla, df in datos_por_tabla.items():
        limpio = tipar_dataframe(df)
        for col in COLUMNAS_METADATOS:
            if col in limpio.columns:
                limpio = limpio.drop(columns=[col])

        limpio = agregar_columnas_derivadas(limpio, tabla, dim_tiempo)

        # 1) Gold particionado (Parquet) para el data lake
        if formato == 'parquet':
            ruta_pq = os.path.join(config.CARPETA_GOLD_PARQUET, tabla)
            columnas_part = ['anio_mes'] if (particionar and 'anio_mes' in limpio.columns) else None
            from utilidades import escribir_capa
            escribir_capa(limpio, ruta_pq, formato='parquet', columnas_particion=columnas_part)

        # 2) Gold plano (CSV) para Power BI
        from utilidades import escribir_capa
        ruta_csv = os.path.join(config.CARPETA_GOLD_POWERBI, f'{tabla}.csv')
        escribir_capa(limpio, ruta_csv, formato='csv')

        resultados[tabla] = {
            'filas': len(limpio),
            'columnas': len(limpio.columns),
            'parquet': os.path.join(config.CARPETA_GOLD_PARQUET, tabla),
            'csv': ruta_csv,
            'particionado': bool(particionar and 'anio_mes' in limpio.columns),
        }

    return resultados
