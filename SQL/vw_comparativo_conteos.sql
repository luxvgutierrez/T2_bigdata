/* =========================================================================
   vw_comparativo_conteos.sql  —  Conteos oficiales de cada tabla del DW
   Ejecutar en MONITOR, sobre la BD proyecto_dw.

   La ETL la consulta después de cada extracción para comparar el número de
   filas leídas del CSV contra el número real de filas de la tabla, y así
   garantizar que la extracción fue completa (auditoría de ingesta).
   ========================================================================= */
USE proyecto_dw
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.vw_comparativo_conteos') IS NOT NULL
    DROP VIEW dbo.vw_comparativo_conteos
GO
CREATE VIEW dbo.vw_comparativo_conteos
AS
    SELECT 'Dim_Producto'            AS tabla, COUNT_BIG(*) AS conteo FROM dbo.Dim_Producto
    UNION ALL SELECT 'Dim_Cliente',            COUNT_BIG(*) FROM dbo.Dim_Cliente
    UNION ALL SELECT 'Dim_Proveedor',          COUNT_BIG(*) FROM dbo.Dim_Proveedor
    UNION ALL SELECT 'Dim_Trabajador',         COUNT_BIG(*) FROM dbo.Dim_Trabajador
    UNION ALL SELECT 'Dim_Condicion_Venta',    COUNT_BIG(*) FROM dbo.Dim_Condicion_Venta
    UNION ALL SELECT 'Dim_Documento_Ingreso',  COUNT_BIG(*) FROM dbo.Dim_Documento_Ingreso
    UNION ALL SELECT 'Dim_Tiempo',             COUNT_BIG(*) FROM dbo.Dim_Tiempo
    UNION ALL SELECT 'Bridge_Abastecimiento',  COUNT_BIG(*) FROM dbo.Bridge_Abastecimiento
    UNION ALL SELECT 'Fact_Ventas',            COUNT_BIG(*) FROM dbo.Fact_Ventas
    UNION ALL SELECT 'Fact_Compras',           COUNT_BIG(*) FROM dbo.Fact_Compras
    UNION ALL SELECT 'Fact_Inventario_Snapshot', COUNT_BIG(*) FROM dbo.Fact_Inventario_Snapshot
GO

-- Verificación manual:
-- SELECT * FROM dbo.vw_comparativo_conteos ORDER BY tabla;
