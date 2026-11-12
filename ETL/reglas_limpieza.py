"""
Reglas de limpieza y calidad de datos (RNF03) — única fuente de verdad.
Usada por `etl-limpieza` y `ETL-controlador` (elimina la lógica duplicada).
"""
import pandas as pd

TOLERANCIA_IMPORTE = 0.05  # tolerancia por redondeo al validar importes

CAMPOS_OBLIGATORIOS = {
    'Fact_Ventas': ['sk_cliente', 'sk_producto', 'sk_tiempo', 'sk_trabajador', 'sk_condicion_venta'],
    'Fact_Compras': ['sk_proveedor', 'sk_producto', 'sk_tiempo', 'sk_trabajador', 'sk_documento_ingreso'],
    'Fact_Inventario_Snapshot': ['sk_producto', 'sk_tiempo'],
    'Bridge_Abastecimiento': ['sk_proveedor', 'sk_producto', 'precio_abastecimiento'],
    'Dim_Cliente': ['id_cliente', 'nombres', 'apellidos'],
    'Dim_Producto': ['cod_producto', 'descripcion', 'precio_lista'],
    'Dim_Proveedor': ['id_provedor', 'nombre_proveedor', 'limite_credito', 'plazo_pago_dias'],
    'Dim_Trabajador': ['id_trabajador', 'nombres', 'apellidos'],
    'Dim_Condicion_Venta': ['tipo_comprobante', 'tipo_venta', 'metodo_pago', 'estado_pago', 'estado_pago_desc'],
    'Dim_Documento_Ingreso': ['tipo_documento', 'tipo_pago'],
    'Dim_Tiempo': ['sk_tiempo', 'fecha'],
}

CAMPOS_NUMERICOS = {
    'Fact_Ventas': ['cantidad', 'importe_total', 'precio_unitario'],
    'Fact_Compras': ['cantidad', 'precio_unitario', 'subtotal'],
    'Fact_Inventario_Snapshot': ['stock_cantidad'],
    'Bridge_Abastecimiento': ['precio_abastecimiento'],
    'Dim_Producto': ['precio_lista'],
    'Dim_Proveedor': ['limite_credito', 'plazo_pago_dias'],
    'Dim_Tiempo': ['anio', 'trimestre', 'mes', 'dia'],
}

# Valores que no pueden ser negativos (si la columna existe)
CAMPOS_NO_NEGATIVOS = [
    'importe_total', 'precio_unitario', 'subtotal', 'stock_cantidad',
    'precio_lista', 'limite_credito', 'plazo_pago_dias',
]

# Claves de negocio: espejan las restricciones UNIQUE de la BD (Tablas_T2.sql)
CLAVE_NEGOCIO = {
    'Dim_Cliente': ['id_cliente', 'fecha_inicio'],
    'Dim_Producto': ['cod_producto', 'fecha_inicio'],
    'Dim_Proveedor': ['id_provedor', 'fecha_inicio'],
    'Dim_Trabajador': ['id_trabajador', 'fecha_inicio'],
    'Dim_Tiempo': ['sk_tiempo'],
    'Dim_Condicion_Venta': ['tipo_comprobante', 'tipo_venta', 'metodo_pago', 'estado_pago'],
    'Dim_Documento_Ingreso': ['tipo_documento', 'tipo_pago'],
    'Bridge_Abastecimiento': ['sk_proveedor', 'sk_producto'],
    'Fact_Ventas': ['nro_comprobante', 'id_detalle'],
    'Fact_Compras': ['id_ingreso', 'id_detalle_ingreso'],
    'Fact_Inventario_Snapshot': ['sk_producto', 'sk_tiempo'],
}

# Relaciones esperadas hechos/puente -> dimensiones (validación referencial)
DEPENDENCIAS = {
    'Fact_Ventas': {
        'sk_cliente': 'Dim_Cliente',
        'sk_producto': 'Dim_Producto',
        'sk_trabajador': 'Dim_Trabajador',
        'sk_tiempo': 'Dim_Tiempo',
        'sk_condicion_venta': 'Dim_Condicion_Venta',
    },
    'Fact_Compras': {
        'sk_proveedor': 'Dim_Proveedor',
        'sk_producto': 'Dim_Producto',
        'sk_trabajador': 'Dim_Trabajador',
        'sk_tiempo': 'Dim_Tiempo',
        'sk_documento_ingreso': 'Dim_Documento_Ingreso',
    },
    'Fact_Inventario_Snapshot': {
        'sk_producto': 'Dim_Producto',
        'sk_tiempo': 'Dim_Tiempo',
    },
    'Bridge_Abastecimiento': {
        'sk_proveedor': 'Dim_Proveedor',
        'sk_producto': 'Dim_Producto',
    },
}


def limpiar_tabla(df: pd.DataFrame, tabla: str):
    """
    Aplica todas las reglas de calidad a la tabla.
    Devuelve (df_limpio, df_rechazados_con_motivo, metricas).
    Ninguna fila se borra "en silencio": todo lo descartado va a cuarentena.
    """
    df = df.copy()

    # Normalización de texto: el SQL Server devuelve los CHAR con relleno de
    # espacios ('000001   '). Se recortan para que el lake no arrastre ruido.
    for col in df.columns:
        if df[col].dtype == object or pd.api.types.is_string_dtype(df[col]):
            df[col] = df[col].astype('string').str.strip()

    # --- Coerción de tipos: texto no numérico -> NaN (y salta la regla de nulos) ---
    for col in CAMPOS_NUMERICOS.get(tabla, []):
        if col in df.columns and not pd.api.types.is_numeric_dtype(df[col]):
            df[col] = pd.to_numeric(df[col], errors='coerce')

    motivos = pd.Series([''] * len(df), index=df.index, dtype=object)

    def invalidar(mascara: pd.Series, motivo: str) -> None:
        nuevos = mascara.fillna(False) & (motivos == '')
        motivos.loc[nuevos] = motivo

    # 1. Nulos en campos obligatorios y numéricos
    requeridos = CAMPOS_OBLIGATORIOS.get(tabla, [])
    for col in requeridos:
        if col in df.columns:
            invalidar(df[col].isna(), f'campo_obligatorio_nulo:{col}')
    for col in CAMPOS_NUMERICOS.get(tabla, []):
        if col in df.columns and col not in requeridos:
            invalidar(df[col].isna(), f'valor_no_numerico:{col}')

    # 2. Rangos imposibles
    if 'cantidad' in df.columns:
        invalidar(df['cantidad'] <= 0, 'cantidad_no_positiva')
    for col in CAMPOS_NO_NEGATIVOS:
        if col in df.columns:
            invalidar(df[col].notna() & (df[col] < 0), f'valor_negativo:{col}')

    # 3. Coherencia de importes (cantidad x precio == importe/subtotal)
    if tabla == 'Fact_Ventas' and {'cantidad', 'precio_unitario', 'importe_total'} <= set(df.columns):
        esperado = df['cantidad'] * df['precio_unitario']
        invalidar(
            esperado.notna() & ((esperado - df['importe_total']).abs() > TOLERANCIA_IMPORTE),
            'importe_inconsistente',
        )
    if tabla == 'Fact_Compras' and {'cantidad', 'precio_unitario', 'subtotal'} <= set(df.columns):
        esperado = df['cantidad'] * df['precio_unitario']
        invalidar(
            esperado.notna() & ((esperado - df['subtotal']).abs() > TOLERANCIA_IMPORTE),
            'subtotal_inconsistente',
        )

    # 4. Fechas inválidas (Dim_Tiempo)
    if 'fecha' in df.columns:
        invalidar(pd.to_datetime(df['fecha'], errors='coerce').isna(), 'fecha_invalida')

    # 5. Consistencia SCD-2 en dimensiones: fecha_fin nulo <-> es_vigente activo
    if 'es_vigente' in df.columns and 'fecha_fin' in df.columns:
        vigente = df['es_vigente'].astype(str).str.strip().str.lower().isin(['true', '1', 't', 'si'])
        fecha_fin = pd.to_datetime(df['fecha_fin'], errors='coerce')
        invalidar(vigente & fecha_fin.notna(), 'scd_inconsistente')
        invalidar(~vigente & fecha_fin.isna(), 'scd_inconsistente')

    # 6. Duplicados por clave de negocio (más fuerte que duplicado exacto)
    clave = CLAVE_NEGOCIO.get(tabla)
    if clave and set(clave) <= set(df.columns):
        invalidar(df.duplicated(subset=clave, keep='first'), 'duplicado_clave_negocio')

    # 7. Duplicados exactos
    invalidar(df.duplicated(keep='first'), 'duplicado_exacto')

    rechazados = df[motivos != ''].copy()
    rechazados['motivo_rechazo'] = motivos[motivos != '']
    limpio = df[motivos == ''].reset_index(drop=True)

    metricas = {
        'filas_leidas': len(df),
        'filas_descartadas': int((motivos != '').sum()),
        'filas_salida': len(limpio),
        'desglose_rechazos': motivos[motivos != ''].value_counts().to_dict(),
    }
    return limpio, rechazados, metricas


def filtrar_huerfanos(df: pd.DataFrame, tabla: str, dims: dict):
    """
    Validación referencial: descarta filas cuyo sk no exista en la dimensión.
    `dims` = {nombre_dim: DataFrame_limpio}.
    Devuelve (df_con_integridad, df_huerfanos_con_motivo).
    """
    dependencias = DEPENDENCIAS.get(tabla, {})
    if not dependencias or df.empty:
        return df, None

    integro = pd.Series(True, index=df.index)
    for col_fk, nombre_dim in dependencias.items():
        dim = dims.get(nombre_dim)
        if dim is None or col_fk not in df.columns:
            continue  # sin dimensión disponible: no se puede validar
        sks_validos = set(dim[col_fk].dropna())
        integro &= df[col_fk].isin(sks_validos)

    huerfanos = df[~integro].copy()
    if not huerfanos.empty:
        huerfanos['motivo_rechazo'] = 'clave_huerfana'
    return df[integro].reset_index(drop=True), huerfanos


def procesar_tabla(df: pd.DataFrame, tabla: str, dims=None) -> dict:
    """
    Pipeline completo de una tabla: reglas internas + integridad referencial.
    Devuelve dict con 'limpio', 'rechazados', 'huerfanos' y 'metricas'.
    """
    limpio, rechazados, metricas = limpiar_tabla(df, tabla)

    huerfanos = None
    if dims:
        dimname_map = {n: d for n, d in dims.items()}
        limpio, huerfanos = filtrar_huerfanos(limpio, tabla, dimname_map)
        if huerfanos is not None and not huerfanos.empty:
            metricas['huerfanos_descartados'] = len(huerfanos)
            metricas['filas_descartadas'] += len(huerfanos)
            metricas['filas_salida'] = len(limpio)

    return {'limpio': limpio, 'rechazados': rechazados, 'huerfanos': huerfanos, 'metricas': metricas}
