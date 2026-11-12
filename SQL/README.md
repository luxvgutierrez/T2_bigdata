# T2_BigData — MiniMarket `proyecto_dw`

Data warehouse estrella para Power BI + ETL en Python con auditoría.

## Estructura

```
T2_bigdata/
├── Tablas_T2.sql                 # DDL: crea BD proyecto_dw (dimensiones, puente, hechos, índices)
├── sp_carga_scd2.sql             # Procedimientos SCD-2 (cierra vigente + inserta nueva versión)
├── vw_comparativo_conteos.sql    # Vista de conteos: la ETL la usa para verificar la ingesta
├── auditoria_bd.sql              # Tablas de auditoría + vista de calidad + triggers SCD-2
├── ETL/                          # Pipeline de datos (Python)
│   ├── config.py                 # Conexión SQL Server + rutas + listado de tablas
│   ├── utilidades.py             # Escritura atómica, rutas raw/processed/cuarentena
│   ├── auditoria.py              # Auditoría: tiempos de respuesta, log, histórico
│   ├── reglas_limpieza.py        # Reglas RNF03 (única fuente de verdad)
│   ├── extraccion.py             # Ingesta con reintentos y ORDER BY determinista
│   ├── etl-extract               # Script FASE 1: BD -> raw/
│   ├── etl-limpieza              # Script FASE 2: raw/ -> processed/
│   ├── ETL-controlador           # Orquestador completo (fases 1+2 + auditoría)
│   ├── raw/                      # Capa cruda (extracción de la BD)
│   ├── processed/                # Capa limpia (entrada de Power BI)
│   │   └── rechazados/           # Cuarentena: filas descartadas con motivo
│   └── auditoria/                # corrida_<id>.log, resumen_corrida_<id>.json,
│                                  # historico_corridas.csv
```

## Tablas procesadas (11)

| Tipo | Tablas |
|---|---|
| Dimensiones | Dim_Producto, Dim_Cliente, Dim_Proveedor, Dim_Trabajador, Dim_Condicion_Venta, Dim_Documento_Ingreso, Dim_Tiempo |
| Puente | Bridge_Abastecimiento (N:M Producto–Proveedor) |
| Hechos | Fact_Ventas, Fact_Compras, Fact_Inventario_Snapshot |

## Reglas de calidad (RNF03)

1. Duplicados exactos y por **clave de negocio** (espejan las UNIQUE de la BD).
2. Nulos en claves (`sk_*`) y campos obligatorios.
3. Rangos imposibles (`cantidad > 0`, stock/importes ≥ 0).
4. Coherencia de importes (`cantidad × precio == importe_total/subtotal`, tolerancia 0.05).
5. Fechas inválidas en `Dim_Tiempo`.
6. Consistencia SCD-2 (`fecha_fin` nulo ⟷ `es_vigente` activo).
7. Integridad referencial: todo `sk_*` de hechos/puente debe existir en su dimensión.
8. Nada se borra en silencio: los rechazos van a `processed/rechazados/` con columna `motivo_rechazo`.

## Objetos auxiliares en SQL Server

- `sp_carga_scd2.sql`: 4 procedimientos (`sp_cargar_dim_cliente`, `sp_cargar_dim_trabajador`,
  `sp_cargar_dim_producto`, `sp_cargar_dim_proveedor`) que mantienen la SCD-2:
  comparan los atributos de la fila vigente; si cambió, cierran la versión anterior
  (`fecha_fin`/`es_vigente=0`) e insertan la nueva. Idempotente: re-ejecuciones el
  mismo día devuelven `SIN_CAMBIOS` o actualizan la fila, nunca duplican.
- `vw_comparativo_conteos.sql`: vista con `COUNT_BIG(*)` de las 11 tablas. La ETL
  la consulta tras cada extracción; si las filas extraídas no coinciden con el
  conteo de la BD, la tabla queda marcada con ERROR en la auditoría.

## Uso

```powershell
# Pipeline completo (ingesta + limpieza + auditoría)
python "T2_bigdata\ETL\ETL-controlador"
# Solo ingesta / solo limpieza
python "T2_bigdata\ETL\etl-extract"
python "T2_bigdata\ETL\etl-limpieza"
```

Salida de cada corrida en `ETL/auditoria/`:
- `corrida_<id>.log` — línea por fase con su tiempo de respuesta.
- `resumen_corrida_<id>.json` — detalle completo (duración por fase, filas, errores).
- `historico_corridas.csv` — una fila por corrida, para comparar duraciones histórico.

## Dependencias (`requirements.txt`)

Conexión: SQL Server `MONITOR`, BD `proyecto_dw`, autenticación integrada de Windows,
ODBC Driver 17 for SQL Server.
