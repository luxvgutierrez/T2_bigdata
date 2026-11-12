/* =========================================================================
   sp_carga_scd2.sql  —  Carga automática SCD-2 para las dimensiones
   Ejecutar en MONITOR, sobre la BD proyecto_dw.

   Cada procedimiento:
     1. Busca la fila vigente (es_vigente = 1) de la clave de negocio.
     2. La compara atributo por atributo (comparación nula-segura).
     3. Si NO hay cambios -> no hace nada (idempotente).
     4. Si es la primera versión -> inserta con es_vigente = 1.
     5. Si cambió -> cierra la vigente (fecha_fin = @fecha_efectiva,
        es_vigente = 0) e inserta la nueva versión.

   Idempotencia del mismo día: si ya existe una fila de (clave, fecha_efectiva)
   se actualizan sus atributos en vez de fallar por la UNIQUE.
   Devuelve: sk de la fila final y la acción aplicada.
   ========================================================================= */
USE proyecto_dw
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* ---------------------------- Dim_Cliente ------------------------------- */
IF OBJECT_ID('dbo.sp_cargar_dim_cliente') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_dim_cliente
GO
CREATE PROCEDURE dbo.sp_cargar_dim_cliente
    @id_cliente       CHAR(6),
    @fecha_efectiva   DATE = NULL,
    @dni              CHAR(10) = NULL,
    @nombres          VARCHAR(100) = NULL,
    @apellidos        VARCHAR(100) = NULL,
    @fecha_nacimiento DATE = NULL,
    @correo           VARCHAR(50) = NULL,
    @telefono         VARCHAR(50) = NULL,
    @tipo_cliente     VARCHAR(100) = NULL,
    @direccion        VARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Fecha DATE = ISNULL(@fecha_efectiva, CAST(GETDATE() AS DATE));
    DECLARE @sk_actual INT, @sk_hoy INT, @igual BIT;

    SELECT @sk_actual = sk_cliente
      FROM dbo.Dim_Cliente
     WHERE id_cliente = @id_cliente AND es_vigente = 1;

    -- ¿Existe una fila de esta clave iniciada hoy?
    SELECT @sk_hoy = sk_cliente
      FROM dbo.Dim_Cliente
     WHERE id_cliente = @id_cliente AND fecha_inicio = @Fecha;

    -- Comparación de atributos (nula-segura)
    IF @sk_actual IS NOT NULL
        SELECT @igual = CASE WHEN
               (dni = @dni OR (dni IS NULL AND @dni IS NULL))
           AND nombres = @nombres
           AND apellidos = @apellidos
           AND (fecha_nacimiento = @fecha_nacimiento
                OR (fecha_nacimiento IS NULL AND @fecha_nacimiento IS NULL))
           AND (correo = @correo OR (correo IS NULL AND @correo IS NULL))
           AND (telefono = @telefono OR (telefono IS NULL AND @telefono IS NULL))
           AND (tipo_cliente = @tipo_cliente OR (tipo_cliente IS NULL AND @tipo_cliente IS NULL))
           AND (direccion = @direccion OR (direccion IS NULL AND @direccion IS NULL))
           THEN 1 ELSE 0 END
          FROM dbo.Dim_Cliente
         WHERE sk_cliente = @sk_actual;

    /* Caso A: fila de hoy re-procesada el mismo día -> actualizar atributos */
    IF @sk_actual = @sk_hoy AND @sk_hoy IS NOT NULL
    BEGIN
        IF @igual = 1
            SELECT @sk_actual AS sk_cliente, 'SIN_CAMBIOS' AS accion;
        ELSE
        BEGIN
            BEGIN TRY
                BEGIN TRAN
                  UPDATE dbo.Dim_Cliente
                     SET dni = @dni, nombres = @nombres, apellidos = @apellidos,
                         fecha_nacimiento = @fecha_nacimiento, correo = @correo,
                         telefono = @telefono, tipo_cliente = @tipo_cliente,
                         direccion = @direccion
                   WHERE sk_cliente = @sk_actual;
                COMMIT TRAN
                SELECT @sk_actual AS sk_cliente, 'ACTUALIZADA_MISMO_DIA' AS accion;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRAN;
                THROW;
            END CATCH
        END
        RETURN
    END

    /* Caso B: sin cambios -> no-op */
    IF @igual = 1
    BEGIN
        SELECT @sk_actual AS sk_cliente, 'SIN_CAMBIOS' AS accion;
        RETURN
    END

    /* Caso C: primera vez o cambio de atributos -> cerrar vigente + insertar nueva */
    BEGIN TRY
        BEGIN TRAN

        IF @sk_actual IS NOT NULL
            UPDATE dbo.Dim_Cliente
               SET fecha_fin = @Fecha, es_vigente = 0
             WHERE sk_cliente = @sk_actual;

        IF @sk_hoy IS NOT NULL   -- fila de hoy ya creada por otra corrida
            UPDATE dbo.Dim_Cliente
               SET dni = @dni, nombres = @nombres, apellidos = @apellidos,
                   fecha_nacimiento = @fecha_nacimiento, correo = @correo,
                   telefono = @telefono, tipo_cliente = @tipo_cliente,
                   direccion = @direccion, fecha_fin = NULL, es_vigente = 1
             WHERE sk_cliente = @sk_hoy
        ELSE
            INSERT INTO dbo.Dim_Cliente
                (id_cliente, dni, nombres, apellidos, fecha_nacimiento,
                 correo, telefono, tipo_cliente, direccion,
                 fecha_inicio, fecha_fin, es_vigente)
            VALUES
                (@id_cliente, @dni, @nombres, @apellidos, @fecha_nacimiento,
                 @correo, @telefono, @tipo_cliente, @direccion,
                 @Fecha, NULL, 1)

        COMMIT TRAN

        SELECT ISNULL(@sk_hoy, SCOPE_IDENTITY()) AS sk_cliente,
               CASE WHEN @sk_actual IS NULL THEN 'NUEVO'
                    ELSE 'NUEVA_VERSION' END AS accion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

/* --------------------------- Dim_Trabajador ----------------------------- */
IF OBJECT_ID('dbo.sp_cargar_dim_trabajador') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_dim_trabajador
GO
CREATE PROCEDURE dbo.sp_cargar_dim_trabajador
    @id_trabajador    CHAR(6),
    @fecha_efectiva   DATE = NULL,
    @dni              CHAR(10) = NULL,
    @nombres          VARCHAR(100) = NULL,
    @apellidos        VARCHAR(100) = NULL,
    @fecha_nacimiento DATE = NULL,
    @tipo_trabajador  VARCHAR(100) = NULL,
    @cat_laboral      VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Fecha DATE = ISNULL(@fecha_efectiva, CAST(GETDATE() AS DATE));
    DECLARE @sk_actual INT, @sk_hoy INT, @igual BIT;

    SELECT @sk_actual = sk_trabajador
      FROM dbo.Dim_Trabajador
     WHERE id_trabajador = @id_trabajador AND es_vigente = 1;

    SELECT @sk_hoy = sk_trabajador
      FROM dbo.Dim_Trabajador
     WHERE id_trabajador = @id_trabajador AND fecha_inicio = @Fecha;

    IF @sk_actual IS NOT NULL
        SELECT @igual = CASE WHEN
               (dni = @dni OR (dni IS NULL AND @dni IS NULL))
           AND nombres = @nombres
           AND apellidos = @apellidos
           AND (fecha_nacimiento = @fecha_nacimiento
                OR (fecha_nacimiento IS NULL AND @fecha_nacimiento IS NULL))
           AND (tipo_trabajador = @tipo_trabajador
                OR (tipo_trabajador IS NULL AND @tipo_trabajador IS NULL))
           AND (cat_laboral = @cat_laboral
                OR (cat_laboral IS NULL AND @cat_laboral IS NULL))
           THEN 1 ELSE 0 END
          FROM dbo.Dim_Trabajador
         WHERE sk_trabajador = @sk_actual;

    IF @sk_actual = @sk_hoy AND @sk_hoy IS NOT NULL
    BEGIN
        IF @igual = 1
            SELECT @sk_actual AS sk_trabajador, 'SIN_CAMBIOS' AS accion;
        ELSE
        BEGIN
            BEGIN TRY
                BEGIN TRAN
                  UPDATE dbo.Dim_Trabajador
                     SET dni = @dni, nombres = @nombres, apellidos = @apellidos,
                         fecha_nacimiento = @fecha_nacimiento,
                         tipo_trabajador = @tipo_trabajador,
                         cat_laboral = @cat_laboral
                   WHERE sk_trabajador = @sk_actual;
                COMMIT TRAN
                SELECT @sk_actual AS sk_trabajador, 'ACTUALIZADA_MISMO_DIA' AS accion;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRAN;
                THROW;
            END CATCH
        END
        RETURN
    END

    IF @igual = 1
    BEGIN
        SELECT @sk_actual AS sk_trabajador, 'SIN_CAMBIOS' AS accion;
        RETURN
    END

    BEGIN TRY
        BEGIN TRAN

        IF @sk_actual IS NOT NULL
            UPDATE dbo.Dim_Trabajador
               SET fecha_fin = @Fecha, es_vigente = 0
             WHERE sk_trabajador = @sk_actual;

        IF @sk_hoy IS NOT NULL
            UPDATE dbo.Dim_Trabajador
               SET dni = @dni, nombres = @nombres, apellidos = @apellidos,
                   fecha_nacimiento = @fecha_nacimiento,
                   tipo_trabajador = @tipo_trabajador,
                   cat_laboral = @cat_laboral,
                   fecha_fin = NULL, es_vigente = 1
             WHERE sk_trabajador = @sk_hoy
        ELSE
            INSERT INTO dbo.Dim_Trabajador
                (id_trabajador, dni, nombres, apellidos, fecha_nacimiento,
                 tipo_trabajador, cat_laboral, fecha_inicio, fecha_fin, es_vigente)
            VALUES
                (@id_trabajador, @dni, @nombres, @apellidos, @fecha_nacimiento,
                 @tipo_trabajador, @cat_laboral, @Fecha, NULL, 1)

        COMMIT TRAN

        SELECT ISNULL(@sk_hoy, SCOPE_IDENTITY()) AS sk_trabajador,
               CASE WHEN @sk_actual IS NULL THEN 'NUEVO'
                    ELSE 'NUEVA_VERSION' END AS accion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

/* ---------------------------- Dim_Producto ------------------------------ */
IF OBJECT_ID('dbo.sp_cargar_dim_producto') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_dim_producto
GO
CREATE PROCEDURE dbo.sp_cargar_dim_producto
    @cod_producto      CHAR(6),
    @fecha_efectiva    DATE = NULL,
    @descripcion       VARCHAR(255) = NULL,
    @cod_tipo_producto CHAR(6) = NULL,
    @tipo_producto     VARCHAR(255) = NULL,
    @estado_producto   VARCHAR(100) = NULL,
    @precio_lista      DECIMAL(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Fecha DATE = ISNULL(@fecha_efectiva, CAST(GETDATE() AS DATE));
    DECLARE @sk_actual INT, @sk_hoy INT, @igual BIT;

    SELECT @sk_actual = sk_producto
      FROM dbo.Dim_Producto
     WHERE cod_producto = @cod_producto AND es_vigente = 1;

    SELECT @sk_hoy = sk_producto
      FROM dbo.Dim_Producto
     WHERE cod_producto = @cod_producto AND fecha_inicio = @Fecha;

    IF @sk_actual IS NOT NULL
        SELECT @igual = CASE WHEN
           descripcion = @descripcion
           AND (cod_tipo_producto = @cod_tipo_producto
                OR (cod_tipo_producto IS NULL AND @cod_tipo_producto IS NULL))
           AND (tipo_producto = @tipo_producto
                OR (tipo_producto IS NULL AND @tipo_producto IS NULL))
           AND (estado_producto = @estado_producto
                OR (estado_producto IS NULL AND @estado_producto IS NULL))
           AND (precio_lista = @precio_lista
                OR (precio_lista IS NULL AND @precio_lista IS NULL))
           THEN 1 ELSE 0 END
          FROM dbo.Dim_Producto
         WHERE sk_producto = @sk_actual;

    IF @sk_actual = @sk_hoy AND @sk_hoy IS NOT NULL
    BEGIN
        IF @igual = 1
            SELECT @sk_actual AS sk_producto, 'SIN_CAMBIOS' AS accion;
        ELSE
        BEGIN
            BEGIN TRY
                BEGIN TRAN
                  UPDATE dbo.Dim_Producto
                     SET descripcion = @descripcion,
                         cod_tipo_producto = @cod_tipo_producto,
                         tipo_producto = @tipo_producto,
                         estado_producto = @estado_producto,
                         precio_lista = @precio_lista
                   WHERE sk_producto = @sk_actual;
                COMMIT TRAN
                SELECT @sk_actual AS sk_producto, 'ACTUALIZADA_MISMO_DIA' AS accion;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRAN;
                THROW;
            END CATCH
        END
        RETURN
    END

    IF @igual = 1
    BEGIN
        SELECT @sk_actual AS sk_producto, 'SIN_CAMBIOS' AS accion;
        RETURN
    END

    BEGIN TRY
        BEGIN TRAN

        IF @sk_actual IS NOT NULL
            UPDATE dbo.Dim_Producto
               SET fecha_fin = @Fecha, es_vigente = 0
             WHERE sk_producto = @sk_actual;

        IF @sk_hoy IS NOT NULL
            UPDATE dbo.Dim_Producto
               SET descripcion = @descripcion,
                   cod_tipo_producto = @cod_tipo_producto,
                   tipo_producto = @tipo_producto,
                   estado_producto = @estado_producto,
                   precio_lista = @precio_lista,
                   fecha_fin = NULL, es_vigente = 1
             WHERE sk_producto = @sk_hoy
        ELSE
            INSERT INTO dbo.Dim_Producto
                (cod_producto, descripcion, cod_tipo_producto, tipo_producto,
                 estado_producto, precio_lista, fecha_inicio, fecha_fin, es_vigente)
            VALUES
                (@cod_producto, @descripcion, @cod_tipo_producto, @tipo_producto,
                 @estado_producto, @precio_lista, @Fecha, NULL, 1)

        COMMIT TRAN

        SELECT ISNULL(@sk_hoy, SCOPE_IDENTITY()) AS sk_producto,
               CASE WHEN @sk_actual IS NULL THEN 'NUEVO'
                    ELSE 'NUEVA_VERSION' END AS accion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

/* ---------------------------- Dim_Proveedor ----------------------------- */
IF OBJECT_ID('dbo.sp_cargar_dim_proveedor') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_dim_proveedor
GO
CREATE PROCEDURE dbo.sp_cargar_dim_proveedor
    @id_provedor       CHAR(6),
    @fecha_efectiva    DATE = NULL,
    @nombre_proveedor  VARCHAR(255) = NULL,
    @cod_tipo_provedor CHAR(6) = NULL,
    @tipo_proveedor    VARCHAR(255) = NULL,
    @limite_credito    DECIMAL(12,2) = NULL,
    @plazo_pago_dias   INT = NULL,
    @tipo_pago         VARCHAR(100) = NULL,
    @estado_credito    VARCHAR(100) = NULL,
    @tiene_delivery    BIT = NULL,
    @telefono          VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Fecha DATE = ISNULL(@fecha_efectiva, CAST(GETDATE() AS DATE));
    DECLARE @sk_actual INT, @sk_hoy INT, @igual BIT;

    SELECT @sk_actual = sk_proveedor
      FROM dbo.Dim_Proveedor
     WHERE id_provedor = @id_provedor AND es_vigente = 1;

    SELECT @sk_hoy = sk_proveedor
      FROM dbo.Dim_Proveedor
     WHERE id_provedor = @id_provedor AND fecha_inicio = @Fecha;

    IF @sk_actual IS NOT NULL
        SELECT @igual = CASE WHEN
           nombre_proveedor = @nombre_proveedor
           AND (cod_tipo_provedor = @cod_tipo_provedor
                OR (cod_tipo_provedor IS NULL AND @cod_tipo_provedor IS NULL))
           AND (tipo_proveedor = @tipo_proveedor
                OR (tipo_proveedor IS NULL AND @tipo_proveedor IS NULL))
           AND (limite_credito = @limite_credito
                OR (limite_credito IS NULL AND @limite_credito IS NULL))
           AND (plazo_pago_dias = @plazo_pago_dias
                OR (plazo_pago_dias IS NULL AND @plazo_pago_dias IS NULL))
           AND (tipo_pago = @tipo_pago OR (tipo_pago IS NULL AND @tipo_pago IS NULL))
           AND (estado_credito = @estado_credito
                OR (estado_credito IS NULL AND @estado_credito IS NULL))
           AND (tiene_delivery = @tiene_delivery
                OR (tiene_delivery IS NULL AND @tiene_delivery IS NULL))
           AND (telefono = @telefono OR (telefono IS NULL AND @telefono IS NULL))
           THEN 1 ELSE 0 END
          FROM dbo.Dim_Proveedor
         WHERE sk_proveedor = @sk_actual;

    IF @sk_actual = @sk_hoy AND @sk_hoy IS NOT NULL
    BEGIN
        IF @igual = 1
            SELECT @sk_actual AS sk_proveedor, 'SIN_CAMBIOS' AS accion;
        ELSE
        BEGIN
            BEGIN TRY
                BEGIN TRAN
                  UPDATE dbo.Dim_Proveedor
                     SET nombre_proveedor = @nombre_proveedor,
                         cod_tipo_provedor = @cod_tipo_provedor,
                         tipo_proveedor = @tipo_proveedor,
                         limite_credito = @limite_credito,
                         plazo_pago_dias = @plazo_pago_dias,
                         tipo_pago = @tipo_pago,
                         estado_credito = @estado_credito,
                         tiene_delivery = @tiene_delivery,
                         telefono = @telefono
                   WHERE sk_proveedor = @sk_actual;
                COMMIT TRAN
                SELECT @sk_actual AS sk_proveedor, 'ACTUALIZADA_MISMO_DIA' AS accion;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRAN;
                THROW;
            END CATCH
        END
        RETURN
    END

    IF @igual = 1
    BEGIN
        SELECT @sk_actual AS sk_proveedor, 'SIN_CAMBIOS' AS accion;
        RETURN
    END

    BEGIN TRY
        BEGIN TRAN

        IF @sk_actual IS NOT NULL
            UPDATE dbo.Dim_Proveedor
               SET fecha_fin = @Fecha, es_vigente = 0
             WHERE sk_proveedor = @sk_actual;

        IF @sk_hoy IS NOT NULL
            UPDATE dbo.Dim_Proveedor
               SET nombre_proveedor = @nombre_proveedor,
                   cod_tipo_provedor = @cod_tipo_provedor,
                   tipo_proveedor = @tipo_proveedor,
                   limite_credito = @limite_credito,
                   plazo_pago_dias = @plazo_pago_dias,
                   tipo_pago = @tipo_pago,
                   estado_credito = @estado_credito,
                   tiene_delivery = @tiene_delivery,
                   telefono = @telefono,
                   fecha_fin = NULL, es_vigente = 1
             WHERE sk_proveedor = @sk_hoy
        ELSE
            INSERT INTO dbo.Dim_Proveedor
                (id_provedor, nombre_proveedor, cod_tipo_provedor, tipo_proveedor,
                 limite_credito, plazo_pago_dias, tipo_pago, estado_credito,
                 tiene_delivery, telefono, fecha_inicio, fecha_fin, es_vigente)
            VALUES
                (@id_provedor, @nombre_proveedor, @cod_tipo_provedor, @tipo_proveedor,
                 @limite_credito, @plazo_pago_dias, @tipo_pago, @estado_credito,
                 @tiene_delivery, @telefono, @Fecha, NULL, 1)

        COMMIT TRAN

        SELECT ISNULL(@sk_hoy, SCOPE_IDENTITY()) AS sk_proveedor,
               CASE WHEN @sk_actual IS NULL THEN 'NUEVO'
                    ELSE 'NUEVA_VERSION' END AS accion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END
GO

/* =======================================================================
   EJEMPLOS DE USO
   - Primera carga de un cliente:
     EXEC dbo.sp_cargar_dim_cliente @id_cliente='CLI001', @nombres='Juan',
          @apellidos='Pérez', @tipo_cliente='Regular', @dni='7418529630';

   - Cliente cambió de correo -> cierra la vigente e inserta nueva versión:
     EXEC dbo.sp_cargar_dim_cliente @id_cliente='CLI001', @nombres='Juan',
          @apellidos='Pérez', @tipo_cliente='Frecuente',
          @correo='juan.nuevo@correo.com';

   - Volver a correr lo mismo el mismo día -> NO crea duplicado
     (devuelve SIN_CAMBIOS o ACTUALIZADA_MISMO_DIA).
   ======================================================================= */
