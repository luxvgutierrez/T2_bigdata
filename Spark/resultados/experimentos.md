# Resultados de los experimentos con Spark

## E1. Escalado

| escala | filas_silver | t_bronze_s | t_silver_s | t_gold_s | t_total_s | filas_por_segundo | tamano_gold_mb |
|---|---|---|---|---|---|---|---|
| 1 | 58598 | 3.652 | 14.202 | 15.678 | 33.532 | 1747.5 | 0.65 |
| 5 | 290438 | 0.68 | 9.195 | 14.663 | 24.538 | 11836.3 | 1.99 |

## E2. CSV vs Parquet

| tabla | filas | t_lectura_csv_s | t_lectura_parquet_s | mb_csv | mb_parquet | factor_compresion | aceleracion_lectura |
|---|---|---|---|---|---|---|---|
| Fact_Inventario_Snapshot | 255200 | 0.104 | 0.242 | 4.07 | 0.25 | 16.28 | 0.43 |

## E3. Particionado por mes

| filas_totales | t_escritura_unica_s | t_escritura_particionada_s | t_lectura_mes_unica_s | t_lectura_mes_particionada_s | aceleracion_lectura_filtrada | particiones |
|---|---|---|---|---|---|---|
| 25000 | 0.959 | 1.776 | 0.261 | 0.12 | 2.18 | 21 |

## E4. Particiones de shuffle

| shuffle_partitions | t_agregacion_s |
|---|---|
| 4 | 0.257 |
| 16 | 0.248 |
| 64 | 0.616 |
| 200 | 1.525 |

## E5. Calidad (errores inyectados)

| fraccion_inyectada | errores_inyectados | ids_con_error | ids_detectados | recall_global | precision_global | falsos_positivos |
|---|---|---|---|---|---|---|
| 0.0 | 0 | 0 | 0 | None | None | 0 |
| 0.01 | 150 | 149 | 149 | 1.0 | 1.0 | 0 |
| 0.05 | 750 | 736 | 736 | 1.0 | 1.0 | 0 |

### Recall por tipo de error — 0%

| tipo_error | inyectados | detectados | recall |
|---|---|---|---|

### Recall por tipo de error — 1%

| tipo_error | inyectados | detectados | recall |
|---|---|---|---|
| duplicado | 50 | 50 | 1.0 |
| fecha_invalida | 17 | 17 | 1.0 |
| huerfano | 16 | 16 | 1.0 |
| importe_incoherente | 18 | 18 | 1.0 |
| negativo | 17 | 17 | 1.0 |
| nulo_clave | 18 | 18 | 1.0 |
| texto_en_numero | 14 | 14 | 1.0 |

### Recall por tipo de error — 5%

| tipo_error | inyectados | detectados | recall |
|---|---|---|---|
| duplicado | 250 | 250 | 1.0 |
| fecha_invalida | 88 | 88 | 1.0 |
| huerfano | 76 | 76 | 1.0 |
| importe_incoherente | 92 | 92 | 1.0 |
| negativo | 84 | 84 | 1.0 |
| nulo_clave | 76 | 76 | 1.0 |
| texto_en_numero | 84 | 84 | 1.0 |
