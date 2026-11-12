/* =========================================================================
   vw_evaluacion_calidad.sql  —  SOLO la vista de evaluación de calidad
   Ejecutar en MONITOR, sobre la BD proyecto_dw.
   (Versión aislada del bloque 2 de auditoria_bd.sql, por si ese script
    grande no llegó a crearla.)

   ANTES DE EJECUTAR: la vista referencia las 11 tablas del modelo.
   Si al ejecutar aparece "Invalid object name 'dbo.<tabla>'", primero
   crea esa tabla con Tablas_T2.sql y vuelve a ejecutar este archivo.
   ========================================================================= */
USE proyecto_dw
GO

-- ¿Falta alguna tabla del modelo? (ejecutar si la vista falla)
/*
SELECT t.tabla,
       CASE WHEN OBJECT_ID('dbo.' + t.tabla) IS NULL THEN 'FALTA' ELSE 'OK' END AS estado
  FROM (VALUES
    ('Dim_Producto'),('Dim_Cliente'),('Dim_Proveedor'),('Dim_Trabajador'),
    ('Dim_Condicion_Venta'),('Dim_Documento_Ingreso'),('Dim_Tiempo'),
    ('Bridge_Abastecimiento'),
    ('Fact_Ventas'),('Fact_Compras'),('Fact_Inventario_Snapshot')
  ) AS t(tabla);
*/

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.vw_evaluacion_calidad') IS NOT NULL DROP VIEW dbo.vw_evaluacion_calidad
GO
CREATE VIEW dbo.vw_evaluacion_calidad
AS
    /* ---------- Fact_Ventas ---------- */
    SELECT 'Fact_Ventas' AS tabla, 'CANTIDAD_NO_POSITIVA' AS regla,
           COUNT_BIG(*) AS filas_evaluadas,
           CAST(SUM(CASE WHEN cantidad <= 0 THEN 1 ELSE 0 END) AS BIGINT) AS filas_fallidas
      FROM dbo.Fact_Ventas
    UNION ALL
    SELECT 'Fact_Ventas', 'IMPORTE_NEGATIVO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN importe_total < 0 THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas
    UNION ALL
    SELECT 'Fact_Ventas', 'CLAVES_NULAS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN sk_cliente IS NULL OR sk_producto IS NULL OR sk_tiempo IS NULL
                           OR sk_trabajador IS NULL OR sk_condicion_venta IS NULL
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas
    UNION ALL
    SELECT 'Fact_Ventas', 'IMPORTE_INCONSISTENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN ABS(CAST(cantidad AS DECIMAL(14,2)) * precio_unitario - importe_total) > 0.05
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas
    UNION ALL
    SELECT 'Fact_Ventas', 'DUPLICADOS_CLAVE_NEGOCIO',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(nro_comprobante, '|', id_detalle))
      FROM dbo.Fact_Ventas

    /* ---------- Fact_Compras ---------- */
    UNION ALL
    SELECT 'Fact_Compras', 'CANTIDAD_NO_POSITIVA',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN cantidad <= 0 THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras
    UNION ALL
    SELECT 'Fact_Compras', 'PRECIO_NEGATIVO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN precio_unitario < 0 THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras
    UNION ALL
    SELECT 'Fact_Compras', 'CLAVES_NULAS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN sk_proveedor IS NULL OR sk_producto IS NULL OR sk_tiempo IS NULL
                           OR sk_trabajador IS NULL OR sk_documento_ingreso IS NULL
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras
    UNION ALL
    SELECT 'Fact_Compras', 'SUBTOTAL_INCONSISTENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN ABS(CAST(cantidad AS DECIMAL(14,2)) * precio_unitario - subtotal) > 0.05
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras
    UNION ALL
    SELECT 'Fact_Compras', 'DUPLICADOS_CLAVE_NEGOCIO',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(id_ingreso, '|', id_detalle_ingreso))
      FROM dbo.Fact_Compras

    /* ---------- Fact_Inventario_Snapshot ---------- */
    UNION ALL
    SELECT 'Fact_Inventario_Snapshot', 'STOCK_NEGATIVO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN stock_cantidad < 0 THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Inventario_Snapshot
    UNION ALL
    SELECT 'Fact_Inventario_Snapshot', 'CLAVES_NULAS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN sk_producto IS NULL OR sk_tiempo IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Inventario_Snapshot
    UNION ALL
    SELECT 'Fact_Inventario_Snapshot', 'DUPLICADOS_PAR_PRODUCTO_DIA',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(sk_producto, '|', sk_tiempo))
      FROM dbo.Fact_Inventario_Snapshot

    /* ---------- Bridge_Abastecimiento ---------- */
    UNION ALL
    SELECT 'Bridge_Abastecimiento', 'PRECIO_NEGATIVO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN precio_abastecimiento < 0 THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Bridge_Abastecimiento

    /* ---------- Dimensiones SCD-2 ---------- */
    UNION ALL
    SELECT 'Dim_Cliente', 'CAMPOS_OBLIGATORIOS_NULOS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN id_cliente IS NULL OR nombres IS NULL OR apellidos IS NULL OR tipo_cliente IS NULL
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Cliente
    UNION ALL
    SELECT 'Dim_Cliente', 'DUPLICADOS_CLAVE_NEGOCIO',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(id_cliente, '|', fecha_inicio))
      FROM dbo.Dim_Cliente
    UNION ALL
    SELECT 'Dim_Cliente', 'SCD_INCONSISTENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN (es_vigente = 1 AND fecha_fin IS NOT NULL)
                           OR (es_vigente = 0 AND fecha_fin IS NULL)
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Cliente

    UNION ALL
    SELECT 'Dim_Producto', 'CAMPOS_OBLIGATORIOS_NULOS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN cod_producto IS NULL OR descripcion IS NULL OR precio_lista IS NULL
                           OR estado_producto IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Producto
    UNION ALL
    SELECT 'Dim_Producto', 'DUPLICADOS_CLAVE_NEGOCIO',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(cod_producto, '|', fecha_inicio))
      FROM dbo.Dim_Producto
    UNION ALL
    SELECT 'Dim_Producto', 'SCD_INCONSISTENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN (es_vigente = 1 AND fecha_fin IS NOT NULL)
                           OR (es_vigente = 0 AND fecha_fin IS NULL)
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Producto

    UNION ALL
    SELECT 'Dim_Proveedor', 'CAMPOS_OBLIGATORIOS_NULOS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN id_provedor IS NULL OR nombre_proveedor IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Proveedor
    UNION ALL
    SELECT 'Dim_Proveedor', 'DUPLICADOS_CLAVE_NEGOCIO',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(id_provedor, '|', fecha_inicio))
      FROM dbo.Dim_Proveedor
    UNION ALL
    SELECT 'Dim_Proveedor', 'SCD_INCONSISTENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN (es_vigente = 1 AND fecha_fin IS NOT NULL)
                           OR (es_vigente = 0 AND fecha_fin IS NULL)
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Proveedor

    UNION ALL
    SELECT 'Dim_Trabajador', 'CAMPOS_OBLIGATORIOS_NULOS',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN id_trabajador IS NULL OR nombres IS NULL OR apellidos IS NULL
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Trabajador
    UNION ALL
    SELECT 'Dim_Trabajador', 'DUPLICADOS_CLAVE_NEGOCIO',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT CONCAT(id_trabajador, '|', fecha_inicio))
      FROM dbo.Dim_Trabajador
    UNION ALL
    SELECT 'Dim_Trabajador', 'SCD_INCONSISTENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN (es_vigente = 1 AND fecha_fin IS NOT NULL)
                           OR (es_vigente = 0 AND fecha_fin IS NULL)
                         THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Dim_Trabajador

    /* ---------- Dim_Tiempo ---------- */
    UNION ALL
    SELECT 'Dim_Tiempo', 'DUPLICADOS_FECHA',
           COUNT_BIG(*),
           COUNT_BIG(*) - COUNT_BIG(DISTINCT fecha)
      FROM dbo.Dim_Tiempo

    /* ---------- Integridad referencial (húérfanos) ---------- */
    UNION ALL
    SELECT 'Fact_Ventas', 'HUERFANOS_VS_DIM_CLIENTE',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN c.sk_cliente IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Cliente c ON c.sk_cliente = f.sk_cliente
    UNION ALL
    SELECT 'Fact_Ventas', 'HUERFANOS_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN p.sk_producto IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
    UNION ALL
    SELECT 'Fact_Ventas', 'HUERFANOS_VS_DIM_TRABAJADOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.sk_trabajador IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Trabajador t ON t.sk_trabajador = f.sk_trabajador
    UNION ALL
    SELECT 'Fact_Ventas', 'HUERFANOS_VS_DIM_TIEMPO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN d.sk_tiempo IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Tiempo d ON d.sk_tiempo = f.sk_tiempo
    UNION ALL
    SELECT 'Fact_Ventas', 'HUERFANOS_VS_DIM_CONDICION',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN cv.sk_condicion_venta IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Ventas f
           LEFT JOIN dbo.Dim_Condicion_Venta cv ON cv.sk_condicion_venta = f.sk_condicion_venta

    UNION ALL
    SELECT 'Fact_Compras', 'HUERFANOS_VS_DIM_PROVEEDOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN pv.sk_proveedor IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Proveedor pv ON pv.sk_proveedor = f.sk_proveedor
    UNION ALL
    SELECT 'Fact_Compras', 'HUERFANOS_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN p.sk_producto IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
    UNION ALL
    SELECT 'Fact_Compras', 'HUERFANOS_VS_DIM_TRABAJADOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN t.sk_trabajador IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Trabajador t ON t.sk_trabajador = f.sk_trabajador
    UNION ALL
    SELECT 'Fact_Compras', 'HUERFANOS_VS_DIM_TIEMPO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN d.sk_tiempo IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Tiempo d ON d.sk_tiempo = f.sk_tiempo
    UNION ALL
    SELECT 'Fact_Compras', 'HUERFANOS_VS_DIM_DOCUMENTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN di.sk_documento_ingreso IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Compras f
           LEFT JOIN dbo.Dim_Documento_Ingreso di ON di.sk_documento_ingreso = f.sk_documento_ingreso

    UNION ALL
    SELECT 'Fact_Inventario_Snapshot', 'HUERFANOS_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN p.sk_producto IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Inventario_Snapshot f
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
    UNION ALL
    SELECT 'Fact_Inventario_Snapshot', 'HUERFANOS_VS_DIM_TIEMPO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN d.sk_tiempo IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Fact_Inventario_Snapshot f
           LEFT JOIN dbo.Dim_Tiempo d ON d.sk_tiempo = f.sk_tiempo

    UNION ALL
    SELECT 'Bridge_Abastecimiento', 'HUERFANOS_VS_DIM_PROVEEDOR',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN pv.sk_proveedor IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Bridge_Abastecimiento f
           LEFT JOIN dbo.Dim_Proveedor pv ON pv.sk_proveedor = f.sk_proveedor
    UNION ALL
    SELECT 'Bridge_Abastecimiento', 'HUERFANOS_VS_DIM_PRODUCTO',
           COUNT_BIG(*),
           CAST(SUM(CASE WHEN p.sk_producto IS NULL THEN 1 ELSE 0 END) AS BIGINT)
      FROM dbo.Bridge_Abastecimiento f
           LEFT JOIN dbo.Dim_Producto p ON p.sk_producto = f.sk_producto
GO

-- VERIFICACIÓN INMEDIATA: debe listar las 41 reglas
SELECT COUNT(*) AS total_reglas, SUM(CASE WHEN filas_fallidas > 0 THEN 1 ELSE 0 END) AS con_fallos
  FROM dbo.vw_evaluacion_calidad;
GO
