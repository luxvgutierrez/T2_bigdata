"""
Fase de ingesta: SQL Server -> capa raw (CSV).
Usada por `etl-extract` y `ETL-controlador`.
"""
import time

import pandas as pd
from sqlalchemy import text

from config import TABLAS


def probar_conexion(engine) -> None:
    """
    Valida que el servidor sea accesible ANTES de iterar tablas.
    Lanza excepción si no hay conexión (las llamadas abortan la corrida
    completa en vez de gastar reintentos tabla por tabla).
    """
    with engine.connect() as con:
        con.execute(text('SELECT 1'))


def conteo_bd(engine, tabla: str) -> int:
    """
    Número de filas reales de la tabla en la BD (punto 2: verificación de
    ingesta). Usa la vista vw_comparativo_conteos; si aún no fue creada,
    cae a un COUNT(*) directo.
    """
    try:
        with engine.connect() as con:
            filas = pd.read_sql(
                text('SELECT conteo FROM dbo.vw_comparativo_conteos WHERE tabla = :t'),
                con,
                params={'t': tabla},
            )
            return int(filas.iloc[0, 0])
    except Exception:
        with engine.connect() as con:
            filas = pd.read_sql(
                text(f'SELECT COUNT(*) AS conteo FROM {tabla}'), con
            )
            return int(filas.iloc[0, 0])


def extraer_tabla(engine, tabla: str, auditoria=None,
                  reintentos: int = 3, pausa_seg: float = 2.0) -> pd.DataFrame:
    """
    Extrae una tabla completa con lectura determinista (ORDER BY) y
    reintentos ante fallos transitorios de conexión.
    """
    if tabla not in TABLAS:
        raise ValueError(f'Tabla no autorizada: {tabla}')

    sql = f'SELECT * FROM {tabla} ORDER BY 1'
    ultimo_error = None

    for intento in range(1, reintentos + 1):
        try:
            # Contexto de conexión explícito: evita el warning de
            # deprecación de pandas 2.x con un engine directo.
            with engine.connect() as conexion:
                return pd.read_sql(sql, con=conexion)
        except Exception as exc:
            ultimo_error = exc
            if intento < reintentos:
                if auditoria is not None:
                    auditoria.registrar_simple(
                        'EXTRACCION', tabla,
                        f'Reintento {intento}/{reintentos} tras error: {exc}',
                    )
                time.sleep(pausa_seg)

    raise ultimo_error
