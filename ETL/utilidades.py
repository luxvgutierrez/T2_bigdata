"""Utilidades comunes de la ETL."""
import os
import pandas as pd

from config import CARPETA_RAW, CARPETA_PROCESSED, CARPETA_RECHAZADOS


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
