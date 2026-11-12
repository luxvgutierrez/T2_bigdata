/* =========================================================================
   auditoria_bd.sql  —  Infraestructura de auditoría del DW
   Ejecutar en MONITOR, sobre la BD proyecto_dw (después de Tablas_T2.sql).

   Crea:
     1. Tablas   : Aud_Corrida_ETL, Aud_Evento_ETL, Aud_Calidad_Datos,
                   Aud_Historial_SCD2
     2. Vista    : vw_evaluacion_calidad (evalúa RNF03 en vivo sobre la BD)
     3. Procs    : sp_aud_evaluar_calidad (persiste snapshot de la vista),
                   sp_aud_registrar_corrida / _evento / _cerrar (para la ETL)
     4. Triggers : historial automático de versiones SCD-2 (4 dimensiones)

   Uso rápido de evaluación:
     SELECT * FROM dbo.vw_evaluacion_calidad WHERE filas_fallidas > 0;
     EXEC dbo.sp_aud_evaluar_calidad;          -- persiste el snapshot
     SELECT * FROM dbo.Aud_Calidad_Datos ORDER BY fecha_evaluacion DESC;
   ========================================================================= */
USE proyecto_dw
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* =====================================================================
   1. TABLAS DE AUDITORÍA
   ===================================================================== */

/* Re-ejecutable: se sueltan primero las tablas hijas (sus FK bloquean el
   drop de la cabecera). ATENCIÓN: re-ejecutar BORRA el historial previo. */
IF OBJECT_ID('dbo.Aud_Evento_ETL') IS NOT NULL DROP TABLE dbo.Aud_Evento_ETL
GO
IF OBJECT_ID('dbo.Aud_Calidad_Datos') IS NOT NULL DROP TABLE dbo.Aud_Calidad_Datos
GO
IF OBJECT_ID('dbo.Aud_Historial_SCD2') IS NOT NULL DROP TABLE dbo.Aud_Historial_SCD2
GO
IF OBJECT_ID('dbo.Aud_Corrida_ETL') IS NOT NULL DROP TABLE dbo.Aud_Corrida_ETL
GO

CREATE TABLE dbo.Aud_Corrida_ETL (
    id_corrida     INT IDENTITY(1,1) NOT NULL,
    fecha_inicio   DATETIME2(0)  NOT NULL CONSTRAINT DF_AudCor_ini DEFAULT (GETDATE()),
    fecha_fin      DATETIME2(0)  NULL,
    duracion_seg   DECIMAL(10,3) NULL,
    estado         VARCHAR(15)   NOT NULL CONSTRAINT DF_AudCor_est DEFAULT ('EN_PROCESO')
                     CONSTRAINT CK_AudCor_estado CHECK (estado IN ('EN_PROCESO','EXITOSO','CON_ERRORES')),
    origen         VARCHAR(60)   NOT NULL,                    -- script: ETL-controlador, etl-limpieza...
    ejecutado_por  VARCHAR(100)  NOT NULL CONSTRAINT DF_AudCor_usr DEFAULT (SUSER_SNAME()),
    detalle_error  NVARCHAR(500) NULL,
    CONSTRAINT PK_Aud_Corrida_ETL PRIMARY KEY (id_corrida)
)
GO

CREATE TABLE dbo.Aud_Evento_ETL (
    id_evento         INT IDENTITY(1,1) NOT NULL,
    id_corrida        INT           NOT NULL,
    fecha_evento      DATETIME2(0)  NOT NULL CONSTRAINT DF_AudEvt_fec DEFAULT (GETDATE()),
    etapa             VARCHAR(30)   NOT NULL,   -- EXTRACCION/LIMPIEZA/CUARENTENA/VALIDACION_REFERENCIAL
    tabla             VARCHAR(60)   NULL,
    estado            VARCHAR(10)   NOT NULL CONSTRAINT CK_AudEvt_estado CHECK (estado IN ('OK','ERROR','INFO')),
    duracion_seg      DECIMAL(10,3) NULL,
    filas_leidas      INT           NULL,
    filas_descartadas INT           NULL,
    filas_salida      INT           NULL,
    mensaje           NVARCHAR(500) NULL,
    CONSTRAINT PK_Aud_Evento_ETL PRIMARY KEY (id_evento),
    CONSTRAINT FK_AudEvt_Corrida FOREIGN KEY (id_corrida) REFERENCES dbo.Aud_Corrida_ETL(id_corrida)
)
GO
CREATE INDEX IX_AudEvt_Corrida ON dbo.Aud_Evento_ETL (id_corrida, etapa)
GO

CREATE TABLE dbo.Aud_Calidad_Datos (
    id_check          INT IDENTITY(1,1) NOT NULL,
    id_corrida        INT           NULL,          -- NULL = evaluación manual en BD
    fecha_evaluacion  DATETIME2(0)  NOT NULL CONSTRAINT DF_AudCal_fec DEFAULT (GETDATE()),
    tabla             VARCHAR(60)   NOT NULL,
    regla             VARCHAR(60)   NOT NULL,
    filas_evaluadas   INT           NOT NULL,
    filas_fallidas    INT           NOT NULL CONSTRAINT CK_AudCal_fall CHECK (filas_fallidas >= 0),
    pct_cumplimiento  AS CAST(100.0 * (filas_evaluadas - filas_fallidas) / NULLIF(filas_evaluadas, 0) AS DECIMAL(5,2)) PERSISTED,
    estado            AS CASE WHEN filas_fallidas = 0 THEN 'OK' ELSE 'FALLO' END PERSISTED,
    CONSTRAINT PK_Aud_Calidad_Datos PRIMARY KEY (id_check),
    CONSTRAINT FK_AudCal_Corrida FOREIGN KEY (id_corrida) REFERENCES dbo.Aud_Corrida_ETL(id_corrida)
)
GO
CREATE INDEX IX_AudCal_Tabla ON dbo.Aud_Calidad_Datos (tabla, regla, fecha_evaluacion DESC)
GO

CREATE TABLE dbo.Aud_Historial_SCD2 (
    id_version     INT IDENTITY(1,1) NOT NULL,
    fecha_registro DATETIME2(0)  NOT NULL CONSTRAINT DF_AudSCD_fec DEFAULT (GETDATE()),
    tabla          VARCHAR(60)   NOT NULL,
    sk             INT           NOT NULL,
    clave_negocio  VARCHAR(255)  NOT NULL,
    accion         VARCHAR(20)   NOT NULL CONSTRAINT CK_AudSCD_acc CHECK (accion IN ('NUEVO','CIERRE','VERSION')),
    usuario        VARCHAR(100)  NOT NULL CONSTRAINT DF_AudSCD_usr DEFAULT (SUSER_SNAME()),
    CONSTRAINT PK_Aud_Historial_SCD2 PRIMARY KEY (id_version)
)
GO
CREATE INDEX IX_AudSCD_Tabla ON dbo.Aud_Historial_SCD2 (tabla, sk, fecha_registro DESC)
GO

/* =====================================================================
   2. VISTA DE EVALUACIÓN EN VIVO (RNF03 sobre las tablas de la BD)
   Devuelve una fila por regla: filas_evaluadas vs filas_fallidas.
   ===================================================================== */
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

/* =====================================================================
   3. PROCEDIMIENTOS
   ===================================================================== */

-- Persiste el snapshot de la evaluación en Aud_Calidad_Datos (con fecha/hora)
IF OBJECT_ID('dbo.sp_aud_evaluar_calidad') IS NOT NULL
    DROP PROCEDURE dbo.sp_aud_evaluar_calidad
GO
CREATE PROCEDURE dbo.sp_aud_evaluar_calidad
    @id_corrida INT = NULL      -- opcional: ligarlo a una corrida de la ETL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Aud_Calidad_Datos (id_corrida, tabla, regla, filas_evaluadas, filas_fallidas)
    SELECT @id_corrida, tabla, regla, filas_evaluadas, CAST(filas_fallidas AS INT)
      FROM dbo.vw_evaluacion_calidad;

    SELECT COUNT(*)            AS reglas_evaluadas,
           SUM(CASE WHEN filas_fallidas > 0 THEN 1 ELSE 0 END) AS reglas_con_fallos
      FROM dbo.Aud_Calidad_Datos
     WHERE fecha_evaluacion >= DATEADD(MINUTE, -1, GETDATE())
       AND ((id_corrida = @id_corrida)
            OR (id_corrida IS NULL AND @id_corrida IS NULL));
END
GO

-- Cabecera de corrida (para que la ETL registre sus ejecuciones en BD)
IF OBJECT_ID('dbo.sp_aud_registrar_corrida') IS NOT NULL
    DROP PROCEDURE dbo.sp_aud_registrar_corrida
GO
CREATE PROCEDURE dbo.sp_aud_registrar_corrida
    @origen VARCHAR(60)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Aud_Corrida_ETL (origen) VALUES (@origen);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS id_corrida;
END
GO

-- Evento por fase/tabla dentro de la corrida
IF OBJECT_ID('dbo.sp_aud_registrar_evento') IS NOT NULL
    DROP PROCEDURE dbo.sp_aud_registrar_evento
GO
CREATE PROCEDURE dbo.sp_aud_registrar_evento
    @id_corrida       INT,
    @etapa            VARCHAR(30),
    @tabla            VARCHAR(60) = NULL,
    @estado           VARCHAR(10) = 'OK',
    @duracion_seg     DECIMAL(10,3) = NULL,
    @filas_leidas     INT = NULL,
    @filas_descartadas INT = NULL,
    @filas_salida     INT = NULL,
    @mensaje          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Aud_Evento_ETL
        (id_corrida, etapa, tabla, estado, duracion_seg,
         filas_leidas, filas_descartadas, filas_salida, mensaje)
    VALUES
        (@id_corrida, @etapa, @tabla, @estado, @duracion_seg,
         @filas_leidas, @filas_descartadas, @filas_salida, @mensaje);
END
GO

-- Cierre de la corrida con estado final
IF OBJECT_ID('dbo.sp_aud_cerrar_corrida') IS NOT NULL
    DROP PROCEDURE dbo.sp_aud_cerrar_corrida
GO
CREATE PROCEDURE dbo.sp_aud_cerrar_corrida
    @id_corrida   INT,
    @estado       VARCHAR(15),        -- EXITOSO / CON_ERRORES
    @duracion_seg DECIMAL(10,3) = NULL,
    @detalle_error NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Aud_Corrida_ETL
       SET fecha_fin = GETDATE(),
           duracion_seg = @duracion_seg,
           estado = @estado,
           detalle_error = @detalle_error
     WHERE id_corrida = @id_corrida;
END
GO

/* =====================================================================
   4. TRIGGERS: historial automático de versiones SCD-2
   (complementan a sp_carga_scd2.sql; registran TODO cambio de vigencia,
    venga de quien venga: proc, ETL o edición manual)
   ===================================================================== */

IF OBJECT_ID('dbo.trg_Dim_Cliente_aud') IS NOT NULL DROP TRIGGER dbo.trg_Dim_Cliente_aud
GO
CREATE TRIGGER dbo.trg_Dim_Cliente_aud ON dbo.Dim_Cliente
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Aud_Historial_SCD2 (tabla, sk, clave_negocio, accion)
    SELECT 'Dim_Cliente', i.sk_cliente, i.id_cliente,
           CASE WHEN i.es_vigente = 0 THEN 'CIERRE' ELSE 'VERSION' END
      FROM inserted i
     WHERE NOT EXISTS (SELECT 1 FROM deleted d
                        WHERE d.sk_cliente = i.sk_cliente
                          AND d.es_vigente = i.es_vigente
                          AND d.fecha_fin = i.fecha_fin);
END
GO

IF OBJECT_ID('dbo.trg_Dim_Producto_aud') IS NOT NULL DROP TRIGGER dbo.trg_Dim_Producto_aud
GO
CREATE TRIGGER dbo.trg_Dim_Producto_aud ON dbo.Dim_Producto
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Aud_Historial_SCD2 (tabla, sk, clave_negocio, accion)
    SELECT 'Dim_Producto', i.sk_producto, i.cod_producto,
           CASE WHEN i.es_vigente = 0 THEN 'CIERRE' ELSE 'VERSION' END
      FROM inserted i
     WHERE NOT EXISTS (SELECT 1 FROM deleted d
                        WHERE d.sk_producto = i.sk_producto
                          AND d.es_vigente = i.es_vigente
                          AND d.fecha_fin = i.fecha_fin);
END
GO

IF OBJECT_ID('dbo.trg_Dim_Proveedor_aud') IS NOT NULL DROP TRIGGER dbo.trg_Dim_Proveedor_aud
GO
CREATE TRIGGER dbo.trg_Dim_Proveedor_aud ON dbo.Dim_Proveedor
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Aud_Historial_SCD2 (tabla, sk, clave_negocio, accion)
    SELECT 'Dim_Proveedor', i.sk_proveedor, i.id_provedor,
           CASE WHEN i.es_vigente = 0 THEN 'CIERRE' ELSE 'VERSION' END
      FROM inserted i
     WHERE NOT EXISTS (SELECT 1 FROM deleted d
                        WHERE d.sk_proveedor = i.sk_proveedor
                          AND d.es_vigente = i.es_vigente
                          AND d.fecha_fin = i.fecha_fin);
END
GO

IF OBJECT_ID('dbo.trg_Dim_Trabajador_aud') IS NOT NULL DROP TRIGGER dbo.trg_Dim_Trabajador_aud
GO
CREATE TRIGGER dbo.trg_Dim_Trabajador_aud ON dbo.Dim_Trabajador
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Aud_Historial_SCD2 (tabla, sk, clave_negocio, accion)
    SELECT 'Dim_Trabajador', i.sk_trabajador, i.id_trabajador,
           CASE WHEN i.es_vigente = 0 THEN 'CIERRE' ELSE 'VERSION' END
      FROM inserted i
     WHERE NOT EXISTS (SELECT 1 FROM deleted d
                        WHERE d.sk_trabajador = i.sk_trabajador
                          AND d.es_vigente = i.es_vigente
                          AND d.fecha_fin = i.fecha_fin);
END
GO

/* =====================================================================
   5. VERIFICACIÓN (ejecutar después de crear todo)
   =====================================================================
   -- Reglas de calidad en vivo (deberían salir todas con filas_fallidas = 0):
   SELECT tabla, regla, filas_evaluadas, filas_fallidas
     FROM dbo.vw_evaluacion_calidad
    WHERE filas_fallidas > 0;

   -- Persistir el snapshot con fecha:
   EXEC dbo.sp_aud_evaluar_calidad;

   -- Ver lo guardado:
   SELECT TOP (50) * FROM dbo.Aud_Calidad_Datos ORDER BY fecha_evaluacion DESC;

   -- Resumen de corridas (cuando la ETL ya esté integrada):
   SELECT * FROM dbo.Aud_Corrida_ETL ORDER BY fecha_inicio DESC;
   ===================================================================== */
