
USE proyecto_dw
GO

SELECT tabla, regla, filas_evaluadas, filas_fallidas
  FROM dbo.vw_evaluacion_calidad
 WHERE filas_fallidas > 0
 ORDER BY filas_fallidas DESC, tabla, regla;
GO

SELECT tabla, regla, filas_evaluadas, filas_fallidas, pct_cumplimiento, estado
  FROM dbo.vw_evaluacion_calidad
 ORDER BY filas_fallidas DESC, tabla, regla;
GO

EXEC dbo.sp_aud_evaluar_calidad;
GO

SELECT TOP (30)
       id_check, fecha_evaluacion, tabla, regla,
       filas_evaluadas, filas_fallidas, pct_cumplimiento, estado
  FROM dbo.Aud_Calidad_Datos
 ORDER BY fecha_evaluacion DESC, tabla, regla;
GO


SELECT TOP (30)
       id_version, fecha_registro, tabla, sk, clave_negocio, accion, usuario
  FROM dbo.Aud_Historial_SCD2
 ORDER BY fecha_registro DESC;
GO

SELECT tabla,
       COUNT(*)                                              AS reglas,
       SUM(CASE WHEN filas_fallidas > 0 THEN 1 ELSE 0 END)   AS reglas_con_fallos,
       MIN(CAST(pct_cumplimiento AS DECIMAL(5,2)))           AS peor_cumplimiento_pct
  FROM dbo.vw_evaluacion_calidad
 GROUP BY tabla
 ORDER BY peor_cumplimiento_pct ASC, tabla;
GO

