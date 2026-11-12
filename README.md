# T2_BigData — MiniMarket `proyecto_dw`

Data warehouse en estrella + Data Lake en Python con auditoría de calidad.
Proyecto: modelado dimensional, ETL con reglas RNF03, capa gold lista para Power BI.

## Estructura

```
T2_bigdata/
├── README.md                     # Este documento (guía general del proyecto)
├── requirements.txt              # pandas, SQLAlchemy, pyodbc, pyarrow
├── SQL/                          # Base de datos (SQL Server)
│   ├── Tablas_T2.sql             # DDL: dimensiones, puente, hechos, índices
│   ├── sp_carga_scd2.sql         # Procedimientos SCD-2 (cierra vigente + nueva versión)
│   ├── vw_comparativo_conteos.sql# Conteos oficiales (la ETL verifica la ingesta)
│   ├── auditoria_bd.sql          # Tablas de auditoría + vista de calidad + triggers
│   ├── vw_evaluacion_calidad.sql # Las 41 reglas de calidad evaluadas en vivo
│   ├── evaluar_calidad.sql       # Consultas de evaluación y evidencia
│   ├── esquema_estrella.md       # Documento del modelo en estrella
│   ├── esquema_estrella_mejoras.sql # Índices, coherencia temporal SCD, CHECKs
│   └── README.md
└── ETL/                          # Pipeline en Python (Data Lake)
    ├── contrato_data_lake.md     # Contrato del lake (capas, tipos, granularidad)
    ├── config.py                 # Conexión, rutas y configuración por capa
    ├── utilidades.py             # Escritura atómica, lector con contrato de tipos
    ├── auditoria.py              # Tiempos de respuesta, log, JSON e histórico
    ├── reglas_limpieza.py        # Reglas RNF03 (única fuente de verdad)
    ├── extraccion.py             # Ingesta con reintentos y verificación de conteos
    ├── curacion.py               # Capa gold: tipado, columnas derivadas, particionado
    ├── etl-extract               # FASE 1: BD -> raw (bronze)
    ├── etl-limpieza              # FASE 2: raw -> processed (silver) + cuarentena
    ├── etl-curado                # FASE 3: processed -> curated (gold)
    ├── ETL-controlador           # Orquestador: fases 1+2+3 + auditoría
    ├── raw/                      # Bronze
    ├── processed/                # Silver (+ rechazados/ = cuarentena)
    ├── curated/                  # Gold (Parquet particionado + CSV para Power BI)
    └── auditoria/                # Log, resumen JSON e histórico por corrida
```

## El modelo en estrella

`Dim_Tiempo`, `Dim_Cliente`, `Dim_Producto`, `Dim_Proveedor`, `Dim_Trabajador`
(SCD-2), `Dim_Condicion_Venta` y `Dim_Documento_Ingreso` (dimensiones basura),
`Bridge_Abastecimiento` (N:M Producto–Proveedor) y los hechos `Fact_Ventas`,
`Fact_Compras` y `Fact_Inventario_Snapshot`.

Detalle completo (grano, medidas, aditividad, reglas R1–R6) en
[`SQL/esquema_estrella.md`](SQL/esquema_estrella.md).

## El Data Lake (medallón)

```
proyecto_dw ──▶ raw/ (bronze) ──▶ processed/ (silver) ──▶ curated/ (gold) ──▶ Power BI
                 + id_lote          + reglas RNF03           + parquet/mes
                 + fecha_carga      + cuarentena            + CSV tipado
```

Contrato (capas, convenciones, tipos, granularidad, retención) en
[`ETL/contrato_data_lake.md`](ETL/contrato_data_lake.md).

## Ejecución

```powershell
pip install -r requirements.txt

python "ETL\ETL-controlador"   # pipeline completo (bronze + silver + gold + auditoría)
python "ETL\etl-extract"       # solo ingesta
python "ETL\etl-limpieza"      # solo limpieza
python "ETL\etl-curado"        # solo curaduría (capa gold)
```

La conexión usa la cuenta de Windows del usuario que ejecuta (`Trusted_Connection=yes`),
servidor `MONITOR`, BD `proyecto_dw`.

## Calidad y auditoría

- **41 reglas de calidad** evaluadas en la BD (`vw_evaluacion_calidad`) y en Python
  (`reglas_limpieza.py`): duplicados, nulos, rangos, coherencia de importes, fechas,
  consistencia SCD-2, integridad referencial y unicidad del grano.
- **Nada se borra en silencio**: lo descartado va a `processed/rechazados/` con `motivo_rechazo`.
- **Auditoría de tiempos**: cada corrida deja `auditoria/corrida_<id>.log`,
  `resumen_corrida_<id>.json` (duración por fase) y `historico_corridas.csv` (acumulado).
- **Ingesta verificada**: las filas extraídas se comparan contra `vw_comparativo_conteos`;
  si difieren, la tabla se marca con ERROR y no se publica.
- **Exit codes**: `0` = EXITOSO, `1` = CON_ERRORES (apto para tareas programadas).
