# Contrato del Data Lake — `T2_bigdata`

Define la estructura, las convenciones y las garantías del lake que consume Power BI.
La ETL (`ETL/`) es el único componente que escribe aquí: si un archivo aparece en el lake
sin pasar por la ETL, es un error de proceso.

---

## 1. Capas (arquitectura medallón)

| Capa | Carpeta | Contenido | Formato | Quién la consume |
|---|---|---|---|---|
| **Bronze** (raw) | `ETL/raw/` | Copia **íntegra** de la BD, sin transformar. 1 CSV por tabla. Trazabilidad por lote. | CSV UTF-8 | La ETL (fase de limpieza) |
| **Silver** (processed) | `ETL/processed/` | Datos **limpios** según RNF03, tipados, sin duplicados ni huérfanos. Entrada directa de Power BI. | CSV UTF-8 | Power BI |
| **Quarantine** | `ETL/processed/rechazados/` | Filas **descartadas** con su `motivo_rechazo`. Nunca se pierden: se auditan. | CSV UTF-8 | Data steward / correcciones |
| **Gold** (curated) | `ETL/curated/` | Proyección del **modelo en estrella** listo para el BI: tipos definitivos, columnas derivadas, particionado mensual y copia plana para Power BI. | Parquet + CSV | Power BI / Data Lake |
| **Auditoría** | `ETL/auditoria/` | Log, resumen JSON e histórico de cada corrida (tiempos, filas, errores). | TXT/JSON/CSV | Operación |

```
proyecto_dw (SQL Server)
        │  SELECT * (8→11 tablas, ORDER BY determinista)
        ▼
   BRONZE  raw/<Tabla>.csv          + columnas de trazabilidad (id_lote, fecha_carga)
        │  reglas RNF03 + integridad referencial
        ▼
   SILVER  processed/<Tabla>_Limpio.csv
        │           └─> processed/rechazados/<Tabla>_rechazadas.csv | _huerfanas.csv
        ▼
    GOLD   curated/tablas/<Tabla>/anio_mes=YYYY-MM/...  (Parquet, particionado)
        │           └─> curated/para_powerbi/<Tabla>.csv  (plano, tipado)
        ▼
     POWER BI  (Import CSV / Parquet)
```

## 2. Convenciones de nombres

| Elemento | Patrón | Ejemplo |
|---|---|---|
| Bronze | `<Tabla>.csv` | `Fact_Ventas.csv` |
| Silver | `<Tabla>_Limpio.csv` | `Fact_Ventas_Limpio.csv` |
| Quarantine (reglas) | `<Tabla>_rechazadas.csv` | `Fact_Ventas_rechazadas.csv` |
| Quarantine (referencial) | `<Tabla>_huerfanas.csv` | `Fact_Ventas_huerfanas.csv` |
| Gold particionado | `curated/tablas/<Tabla>/anio_mes=YYYY-MM/*.parquet` | `.../anio_mes=2026-11/` |
| Gold plano (BI) | `curated/para_powerbi/<Tabla>.csv` | `curated/para_powerbi/Fact_Ventas.csv` |
| Auditoría | `corrida_<AAAAMMDD_HHMMSS>.log` / `resumen_corrida_<id>.json` | — |

Nombres de tabla: **PascalCase** en BD y en el lake. Nombres de columna: **snake_case** (coinciden con la BD, sin traducción).

## 3. Trazabilidad (columnas de ingestión)

Toda fila de la capa **bronze** lleva metadatos de carga (agregados por la ETL, no vienen de la BD):

| Columna | Tipo | Significado |
|---|---|---|
| `id_lote` | string | Identificador de la corrida (`AAAAMMDD_HHMMSS`) |
| `fecha_carga` | datetime | Momento exacto de la extracción |
| `tabla_origen` | string | Tabla de la que proviene la fila |

Se conservan en bronze y **se eliminan en gold** (en gold el linaje está en `auditoria/historico_corridas.csv`).

## 4. Granularidad (contrato de grano)

| Tabla | 1 fila = | Clave de grano |
|---|---|---|
| `Dim_*` | una versión de la dimensión | `sk_*` (surrogate key) |
| `Fact_Ventas` | una línea de comprobante de venta | `sk_fact_venta` |
| `Fact_Compras` | una línea de ingreso de mercancía | `sk_fact_compra` |
| `Fact_Inventario_Snapshot` | un producto en un día | `(sk_producto, sk_tiempo)` |

**El grano no cambia entre capas**: bronze = silver = gold. Si el lake duplica o agrega filas, el modelo se rompe.

## 5. Contrato de esquema (silver/gold)

Tipos garantizados en la capa limpia:

| Patrón | Columnas | Tipo en gold |
|---|---|---|
| `sk_*` | claves surrogate | `Int64` (nullable) |
| `id_cliente`, `id_trabajador`, `id_provedor`, `id_detalle`, `id_ingreso`, `id_detalle_ingreso`, `cod_producto`, `dni` | **claves de negocio** (`CHAR(6)` en la BD: `'000001'`, `'T00001'`) | `string` — **nunca numérico**: se perderían los ceros a la izquierda |
| `cantidad`, `stock_cantidad`, `nro_comprobante`, `anio`, `trimestre`, `mes`, `dia`, `dia_semana`, `plazo_pago_dias` | conteos | `Int64` |
| `importe_total`, `subtotal`, `precio_unitario`, `precio_lista`, `limite_credito`, `precio_abastecimiento` | importes | `Float64` (2 decimales) |
| `fecha`, `fecha_nacimiento`, `fecha_inicio`, `fecha_fin` | fechas | `date` / `datetime64[ns]` |
| `es_vigente`, `es_fin_semana`, `tiene_delivery` | flags | `boolean` |
| resto | texto | `string` (UTF-8, sin espacios extremos) |

**Regla de la capa gold**: `anio_mes` (`YYYY-MM`) se agrega a los hechos (derivado de `Dim_Tiempo`) y es la clave de particionado.

## 6. Calidad garantizada por capa

| Capa | Garantía | Mecanismo |
|---|---|---|
| Bronze | Copia exacta de la BD | Conteo verificado contra `vw_comparativo_conteos` (si difiere → ERROR y no se publica) |
| Silver | Sin duplicados, nulos en claves, negativos, importes incoherentes, fechas inválidas, huérfanos | 41 reglas (`reglas_limpieza.py` + `vw_evaluacion_calidad`) |
| Quarantine | Nada se borra en silencio | Cada fila descartada con `motivo_rechazo` |
| Gold | Tipos definitivos + partitioning + columnas derivadas | `curacion.py` |

## 7. Retención y retención de datos

| Capa | Retención propuesta | Motivo |
|---|---|---|
| Bronze | 90 días (o el doble del ciclo de reproceso) | Reconstruir silver sin volver a la BD |
| Silver | Permanente | Es la base del BI |
| Gold | Permanente (Parquet, comprimido) | Histórico para análisis |
| Quarantine | 1 año | Investigar y corregir reglas |
| Auditoría | Permanente (texto pequeño) | Evidencia de calidad |

## 8. Actualización (incrementalidad)

- Hoy: **extracción completa** (full refresh) por ser volúmenes pequeños (< 60k filas).
- Cuando el snapshot crezca: extraer por ventana de `sk_tiempo` (watermark) y **fusionar** en parquet particionado en lugar de reescribir todo.
- Regla: el partitional replace solo debe tocar las particiones afectadas (`anio_mes` del lote).

## 9. Seguridad

- La ETL se conecta con la **cuenta de Windows del usuario que la ejecuta** (`Trusted_Connection=yes`) → no hay contraseñas en el código.
- Recomendación: cuenta de servicio con rol `db_datareader` sobre `proyecto_dw`.
- El lake no contiene datos sensibles de negocio más allá de los ya publicados en el BI; evaluar RLS si el proyecto lo requiere.

## 10. Roles y responsabilidades

| Rol | Responsabilidad |
|---|---|
| ETL (Python) | extraer, limpiar, curar, auditar; publica bronze/silver/gold |
| BD (SQL Server) | modelo en estrella, SCD-2, constraints, auditoría de calidad |
| Data steward | revisa `processed/rechazados/` y las reglas con fallos |
| BI (Power BI) | modela medidas sobre `curated/para_powerbi`; no modifica el lake |
