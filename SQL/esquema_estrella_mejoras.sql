/* =========================================================================
   esquema_estrella_mejoras.sql  —  Endurecimiento del modelo en estrella
   Ejecutar en MONITOR (o en LocalDB para pruebas) sobre la BD proyecto_dw.
   complements: Tablas_T2.sql, auditoria_bd.sql, sp_carga_scd2.sql

   Contenido (todo idempotente: se puede re-ejecutar sin romper nada):
     1. Índices faltantes sobre las FK de los hechos (D1, D2)
     2. Vista vw_consistencia_scd_temporal  -> regla R4/R5 (D5)
     3. CHECK constraints opcionales en la BD (D3)
     4. Parche opcional de fecha_fin sin solapamiento (D4)
     5. Estadísticas actualizadas
   ========================================================================= */
USE proyecto_dw
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =====================================================================
   1. ÍNDICES FALTANTES SOBRE LAS FK
   (las consultas por trabajador/producto no.usan índice hoy)
   ===================================================================== */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'IX_FVentas_Trabajador' AND object_id = OBJECT_ID('dbo.Fact_Ventas'))
    CREATE INDEX IX_FVentas_Trabajador ON dbo.Fact_Ventas (sk_trabajador)
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'IX_FCompras_Trabajador' AND object_id = OBJECT_ID('dbo.Fact_Compras'))
    CREATE INDEX IX_FCompras_Trabajador ON dbo.Fact_Compras (sk_trabajador)
GO

-- El PK del snapshot empieza por sk_tiempo; falta el acceso por producto
IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE name = 'IX_FInv_Producto' AND object_id = OBJECT_ID('dbo.Fact_Inventario_Snapshot'))
    CREATE INDEX IX_FInv_Producto ON dbo.Fact_Inventario_Snapshot (sk_producto)
GO

/* =====================================================================
   2. REGLA R4/R5: COHERENCIA TEMPORAL SCD
   El hecho debe apuntar a la versión de la dimensión vigente en la
   fecha del hecho:  fecha_inicio <= fecha_hecho <= fecha_fin (o NULL)
   ===================================================================== */
IF OBJECT_ID('dbo.vw_consistencia_scd_temporal') IS NOT NULL
    DROP VIEW dbo.vw_consistencia_scd_temporal
GO
CREATE VIEW dbo.vw_consistencia_scd_temporal
AS
    /* Fact_Ventas vs Dim_Cliente */
    SELECT 'Fact_Ventas' AS tabla, 'SCD_TEMPORAL_VS_DIM_CLIENTE' AS regla,
           COUNT_BIG(*) AS filas_evaluadas,
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN c.sk_cliente IS NULL THEN 1
                          WHEN c.fecha_inicio > t.fecha THEN 1
                          WHEN (c.fecha_fin IS NOT NULL AND c.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT) AS filas_fallidas
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Cliente c ON c.sk_cliente = f.sk_cliente
    UNION ALL
    /* Fact_Ventas vs Dim_Producto */
    SELECT 'Fact_Ventas', 'SCD_TEMPORAL_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN p.sk_producto IS NULL THEN 1
                          WHEN p.fecha_inicio > t.fecha THEN 1
                          WHEN (p.fecha_fin IS NOT NULL AND p.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
    UNION ALL
    /* Fact_Ventas vs Dim_Trabajador */
    SELECT 'Fact_Ventas', 'SCD_TEMPORAL_VS_DIM_TRABAJADOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN w.sk_trabajador IS NULL THEN 1
                          WHEN w.fecha_inicio > t.fecha THEN 1
                          WHEN (w.fecha_fin IS NOT NULL AND w.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Trabajador w ON w.sk_trabajador = f.sk_trabajador
    UNION ALL
    /* Fact_Compras vs Dim_Proveedor */
    SELECT 'Fact_Compras', 'SCD_TEMPORAL_VS_DIM_PROVEEDOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN pv.sk_proveedor IS NULL THEN 1
                          WHEN pv.fecha_inicio > t.fecha THEN 1
                          WHEN (pv.fecha_fin IS NOT NULL AND pv.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Proveedor pv ON pv.sk_proveedor = f.sk_proveedor
    UNION ALL
    /* Fact_Compras vs Dim_Producto */
    SELECT 'Fact_Compras', 'SCD_TEMPORAL_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN p.sk_producto IS NULL THEN 1
                          WHEN p.fecha_inicio > t.fecha THEN 1
                          WHEN (p.fecha_fin IS NOT NULL AND p.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
    UNION ALL
    /* Fact_Compras vs Dim_Trabajador */
    SELECT 'Fact_Compras', 'SCD_TEMPORAL_VS_DIM_TRABAJADOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN w.sk_trabajador IS NULL THEN 1
                          WHEN w.fecha_inicio > t.fecha THEN 1
                          WHEN (w.fecha_fin IS NOT NULL AND w.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Trabajador w ON w.sk_trabajador = f.sk_trabajador
    UNION ALL
    /* Snapshot vs Dim_Producto */
    SELECT 'Fact_Inventario_Snapshot', 'SCD_TEMPORAL_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.fecha IS NULL THEN 1
                          WHEN p.sk_producto IS NULL THEN 1
                          WHEN p.fecha_inicio > t.fecha THEN 1
                          WHEN (p.fecha_fin IS NOT NULL AND p.fecha_fin < t.fecha) THEN 1
                         ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Inventario_Snapshot f
           LEFT JOIN dbo.Dim_Tiempo t ON t.sk_tiempo = f.sk_tiempo
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
GO

-- Verificación: debe dar 0 filas
SELECT tabla, regla, filas_evaluadas, filas_fallidas
  FROM dbo.vw_consistencia_scd_temporal
 WHERE filas_fallidas > 0;
GO

/* =====================================================================
   3. CHECK CONSTRAINTS EN LA BD (D3) — la última línea de defensa
   Opcional: si los datos actuales tienen alguna fila inválida, el ALTER
   fallará; en ese caso primero corrige los datos.
   ===================================================================== */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_FVentas_cantidad')
    ALTER TABLE dbo.Fact_Ventas ADD CONSTRAINT CK_FVentas_cantidad
        CHECK (cantidad > 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_FVentas_importe')
    ALTER TABLE dbo.Fact_Ventas ADD CONSTRAINT CK_FVentas_importe
        CHECK (importe_total >= 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_FCompras_cantidad')
    ALTER TABLE dbo.Fact_Compras ADD CONSTRAINT CK_FCompras_cantidad
        CHECK (cantidad > 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_FCompras_precio')
    ALTER TABLE dbo.Fact_Compras ADD CONSTRAINT CK_FCompras_precio
        CHECK (precio_unitario >= 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_FInv_stock')
    ALTER TABLE dbo.Fact_Inventario_Snapshot ADD CONSTRAINT CK_FInv_stock
        CHECK (stock_cantidad >= 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DimPro_precio')
    ALTER TABLE dbo.Dim_Producto ADD CONSTRAINT CK_DimPro_precio
        CHECK (precio_lista >= 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DimPrv_limite')
    ALTER TABLE dbo.Dim_Proveedor ADD CONSTRAINT CK_DimPrv_limite
        CHECK (limite_credito IS NULL OR limite_credito >= 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DimPrv_plazo')
    ALTER TABLE dbo.Dim_Proveedor ADD CONSTRAINT CK_DimPrv_plazo
        CHECK (plazo_pago_dias IS NULL OR plazo_pago_dias >= 0)
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Bridge_precio')
    ALTER TABLE dbo.Bridge_Abastecimiento ADD CONSTRAINT CK_Bridge_precio
        CHECK (precio_abastecimiento >= 0)
GO

/* =====================================================================
   4. PARCHE OPCIONAL: fecha_fin sin solapamiento (D4)
   La versión anterior debe cerrar el DÍA ANTERIOR al inicio de la nueva.
   Aplica solo a versiones ya cerradas; no toca las vigentes.
   ===================================================================== */
/*
UPDATE dbo.Dim_Cliente
   SET fecha_fin = DATEADD(DAY, -1, fecha_fin)
 WHERE es_vigente = 0 AND fecha_fin IS NOT NULL
   AND EXISTS (SELECT 1 FROM dbo.Dim_Cliente n
                WHERE n.id_cliente = Dim_Cliente.id_cliente
                  AND n.fecha_inicio = Dim_Cliente.fecha_fin);
-- Repetir para Dim_Producto, Dim_Proveedor y Dim_Trabajador.

Y en sp_carga_scd2.sql, cambiar:
    UPDATE ... SET fecha_fin = @Fecha, es_vigente = 0
por:
    UPDATE ... SET fecha_fin = DATEADD(DAY, -1, @Fecha), es_vigente = 0
*/

-- Comprobación de solapamientos actuales (debería dar 0 filas):
/*
SELECT id_cliente, sk_cliente, fecha_inicio, fecha_fin, es_vigente
  FROM dbo.Dim_Cliente
 ORDER BY id_cliente, fecha_inicio;
*/

/* =====================================================================
   5. ESTADÍSTICAS (para que el optimizador use los índices nuevos)
   ===================================================================== */
UPDATE STATISTICS dbo.Fact_Ventas              WITH FULLSCAN
UPDATE STATISTICS dbo.Fact_Compras             WITH FULLSCAN
UPDATE STATISTICS dbo.Fact_Inventario_Snapshot WITH FULLSCAN
UPDATE STATISTICS dbo.Dim_Producto             WITH FULLSCAN
UPDATE STATISTICS dbo.Dim_Cliente              WITH FULLSCAN
UPDATE STATISTICS dbo.Dim_Proveedor            WITH FULLSCAN
UPDATE STATISTICS dbo.Dim_Trabajador           WITH FULLSCAN
GO

/* =====================================================================
   VERIFICACIÓN FINAL
   =====================================================================
   -- Reglas del modelo en estrella (incluye la nueva R4):
   SELECT * FROM dbo.vw_consistencia_scd_temporal ORDER BY filas_fallidas DESC;

   -- Coherencia temporal junto al resto de reglas:
   SELECT 'Regla SCD temporal' AS origen, tabla, regla, filas_evaluadas, filas_fallidas
     FROM dbo.vw_consistencia_scd_temporal
   UNION ALL
   SELECT 'Calidad RNF03', tabla, regla, filas_evaluadas, filas_fallidas
     FROM dbo.vw_evaluacion_calidad
    WHERE filas_fallidas > 0;

   -- Índices creados:
   SELECT t.name AS tabla, i.name AS indice, i.type_desc
     FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
    WHERE t.name IN ('Fact_Ventas','Fact_Compras','Fact_Inventario_Snapshot')
      AND i.name IS NOT NULL
    ORDER BY t.name, i.name;
   ===================================================================== */
