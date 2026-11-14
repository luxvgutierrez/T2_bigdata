# Procesamiento con Spark (local y Databricks)

Implementación del pipeline **bronze → silver → gold** con Spark sobre los CSV
del minimarket, más un generador de datos sintéticos y una batería de
experimentos de escalabilidad y calidad.

```
Spark/
├── config_spark.py          # Esquemas explícitos, claves, reglas y sesión Spark
├── generador_sintetico.py   # Datasets 1x/5x/10x/25x + inyección de errores
├── pipeline_spark.py        # bronze -> silver -> gold + métricas
├── experimentos.py          # E1..E5 (escalado, formatos, particiones, calidad)
├── databricks_pipeline.py   # Notebook único para Databricks (descarga todo del repo)
├── datos/                   # Datasets generados (no versionado)
├── salida/                  # Capa gold + métricas (no versionado)
└── resultados/              # experimentos.csv / .json / .md (versionado)
```

## 1. Ejecución local

Requisitos: **Java 17/21** y `pip install pyspark==4.3.0` (ver `requirements.txt`).

```powershell
cd Spark

# 1) Datasets: real (1x) y sintéticos
python generador_sintetico.py --escalas 1,5,10

# 2) Pipeline sobre un dataset
python pipeline_spark.py --datos datos\escala_5x --salida salida\escala_5x

# 3) Experimentos (genera resultados/experimentos.md)
python experimentos.py --escalas 1,5,10 --calidad 0,0.01,0.05
```

### Windows: `winutils`

Spark en Windows necesita los binarios de Hadoop para escribir archivos:

1. Descargar `winutils.exe` y `hadoop.dll` (Hadoop 3.3.6, repo `cdarlint/winutils`).
2. Dejarlos en `%HADOOP_HOME%\bin`.
3. Definir `HADOOP_HOME` y agregar `%HADOOP_HOME%\bin` al `PATH`.

Sin esto, la lectura funciona pero la escritura falla con
`HADOOP_HOME and hadoop.home.dir are unset`.

## 2. Databricks (Free Edition, navegador)

**Opción A — notebook único (recomendada):**

1. *Workspace* → tu carpeta → **Create → Notebook**.
2. Pegar el contenido de `databricks_pipeline.py` (o importarlo).
3. Adjuntar el cluster (*Serverless* o *Single node*).
4. Elegir en los widgets: `escala`, `errores`, `experimentos`, `rama` y
   `ruta_base` (vacío = automática) y **Run all**.

El notebook descarga el código y los 8 CSV reales desde GitHub (rama
`jesusdev`), busca una carpeta escribible (Volume de Unity Catalog o `/tmp`),
genera el dataset sintético si hace falta y ejecuta el pipeline.

**Si el cluster no tiene salida a Internet**, subir a mano al Volume:

```
/Volumes/<catálogo>/default/t2_bigdata/codigo/     <- los 4 .py de Spark/
/Volumes/<catálogo>/default/t2_bigdata/raw_real/   <- los 8 CSV de ETL/raw/
```

El notebook detecta esos archivos y continúa sin descargar nada.

**Qué deberías ver al ejecutar (escala 5, sin errores):**

| Tabla | Bronze | Silver | Rechazadas |
|---|---|---|---|
| Dim_* (5 tablas) | 2.738 | 2.738 | 0 |
| Fact_Ventas | 25.000 | 25.000 | 0 |
| Fact_Compras | 7.500 | 7.500 | 0 |
| Fact_Inventario_Snapshot | 255.200 | 255.200 | 0 |
| **Total** | **290.438** | **290.438** | **0** |

Con `errores = 0.05` se inyectan defectos conocidos: la tabla de calidad debe
mostrar los rechazos por regla y el recall debe ser alto (ver E5).

### Dónde quedan los datos en Databricks

| Ruta | Uso |
|---|---|
| `/Volumes/<catálogo>/default/t2_bigdata` | Volume (recomendado; visible desde Spark y pandas) |
| `/tmp/t2_bigdata` | Alternativa en clusters de un solo nodo |

El notebook intenta crear el Volume `workspace.default.t2_bigdata`; si no tiene
permisos, cae a `/tmp`.

## 3. Qué hace el pipeline

### Bronze
- Lee cada CSV con **esquema explícito** (sin `inferSchema`: evita leer dos veces
  y que un valor sucio cambie el tipo de una columna).
- Todo entra como **texto** (conserva `'000001'`, `'T00001'`).
- Agrega trazabilidad: `_id_lote`, `_fecha_carga`, `_tabla_origen`.

### Silver
Reglas (la primera que falla define el `motivo_rechazo`):

| # | Regla | Ejemplo |
|---|---|---|
| 1 | Nulo en clave obligatoria | `sk_cliente` vacío |
| 2 | Valor no numérico donde se espera número | `cantidad = 'ABC'` |
| 3 | Medida negativa | `cantidad = -5` |
| 4 | Importe incoherente | `importe ≠ cantidad × precio` (tolerancia 0.05) |
| 5 | Fecha inválida | `fecha = '2025-13-45'` |
| 6 | FK huérfana | `sk_producto = 999999` |
| 7 | Duplicado por clave primaria | dos filas con el mismo `sk_fact_venta` |

- Las dimensiones se validan **antes** que los hechos y se usan como referencia
  (broadcast join) para detectar huérfanos.
- Los rechazos van a cuarentena con `motivo_rechazo`; nada se borra en silencio.

### Gold
- Hechos enriquecidos con `fecha` y `anio_mes` (derivados de `Dim_Tiempo`).
- **Parquet particionado** por `anio_mes` (un archivo por mes).
- Marts para BI: `mart_ventas_mes_producto`, `mart_stock_ultimo_dia`.

## 4. Generador de datos sintéticos

```powershell
python generador_sintetico.py --escalas 1,5,10
python generador_sintetico.py --escala 10 --errores 0.05
```

- `escala = 1` → copia los datos reales.
- `escala = N` → N veces las ventas/compras; las dimensiones crecen
  (productos, clientes, proveedores, trabajadores) y el snapshot se genera como
  **producto × día** (su grano real).
- Todas las FK generadas son válidas: el dataset limpio no debe tener rechazos.
- `--errores` corrompe una fracción de las ventas con 6 tipos de defecto y
  escribe `_verdad_errores.csv` (tabla, fila, tipo) para medir **recall** y
  **precisión** de las reglas.

## 5. Experimentos

| Exp. | Pregunta | Métricas |
|---|---|---|
| **E1** | ¿Cómo escala el pipeline? | tiempo por fase, filas/s, tamaño gold |
| **E2** | ¿CSV o Parquet? | tiempo de lectura/escritura, MB, compresión, aceleración |
| **E3** | ¿Particionar por mes? | tiempo de escritura y de lectura filtrada, particiones |
| **E4** | ¿Cuántas particiones de shuffle? | tiempo de una agregación con 4/16/64/200 |
| **E5** | ¿Las reglas detectan lo que deben? | recall global y por tipo, precisión, falsos positivos |

Salidas en `resultados/`: `experimentos.csv` (formato largo), `experimentos.json`
(detalle) y `experimentos.md` (tablas para el informe).

### Resultados medidos (local, Windows, 1x y 5x)

| Exp. | Hallazgo |
|---|---|
| **E1** | 1x: 33,5 s (1.748 filas/s) · 5x: 24,5 s (11.836 filas/s). El tiempo **no crece linealmente** porque en volúmenes pequeños dominan los costos fijos (arranque de JVM, creación de archivos). |
| **E2** | Parquet comprime **16,3x** (4,07 MB → 0,25 MB). A 255 mil filas el CSV se lee más rápido (0,10 s vs 0,24 s): la ventaja de Parquet está en el tamaño y en el *pruning* de columnas, no en archivos pequeños. |
| **E3** | Particionar cuesta al escribir (1,78 s vs 0,96 s) pero acelera **2,2x** la lectura filtrada por mes (0,12 s vs 0,26 s). |
| **E4** | 16 particiones de shuffle es el óptimo local (0,25 s); con 200 el tiempo se multiplica por **6** (1,53 s). |
| **E5** | **Recall 1,0 y precisión 1,0** en los 7 tipos de error (nulo, negativo, importe, huérfano, fecha, texto y duplicado), con **0 falsos positivos** sobre datos limpios. |

> Estos números son de un solo nodo en Windows: sirven para validar el
> comportamiento y la calidad, no para afirmar escalabilidad. Los tiempos
> representativos para el informe son los de Databricks con `escala = 10/25`.

## 6. Decisiones de diseño

- **Claves de negocio como texto**: `id_cliente`, `cod_producto`, etc. son
  `CHAR(6)` con ceros a la izquierda; convertirlas a número las corrompe.
- **Esquema explícito** en bronze y tipado en silver (mismo contrato que la ETL
  de pandas, `ETL/utilidades.py`).
- **Tolerancia de importes 0.05**, igual que `reglas_limpieza.py` y
  `vw_evaluacion_calidad`.
- **Broadcast join** para las FK: las dimensiones son pequeñas frente a los hechos.
- **Persistencia** de la capa limpia: se calcula una vez y se reutiliza en gold.
- **Un archivo por partición** en gold (`repartition('anio_mes')`) para no dejar
  cientos de archivos pequeños.

## 7. Limitaciones

- En local (Windows) el rendimiento no representa a un cluster: mide
  *corrección*, no *escalabilidad*. Los números de E1 en Databricks son los
  válidos para el informe.
- En clusters con varios workers, `/tmp` no se comparte: usar un Volume.
- La extracción desde SQL Server sigue siendo responsabilidad de `ETL/`
  (pandas + pyodbc); Spark procesa el lake, no la BD transaccional.
