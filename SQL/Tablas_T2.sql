
IF DB_ID('proyecto_dw') IS NULL
    CREATE DATABASE proyecto_dw
GO
USE proyecto_dw
GO

/* =====================================================================
   1. DIMENSIONES
   ===================================================================== */

-- Dim_Tiempo: la clave es la fecha en formato AAAAMMDD
CREATE TABLE Dim_Tiempo (
    sk_tiempo     INT          NOT NULL,
    fecha         DATE         NOT NULL,
    anio          SMALLINT     NOT NULL,
    trimestre     TINYINT      NOT NULL,
    mes           TINYINT      NOT NULL,
    nombre_mes    VARCHAR(15)  NOT NULL,
    dia           TINYINT      NOT NULL,
    dia_semana    TINYINT      NOT NULL,   -- 1 = Lunes ... 7 = Domingo
    nombre_dia    VARCHAR(15)  NOT NULL,
    es_fin_semana BIT          NOT NULL,
    CONSTRAINT PK_Dim_Tiempo PRIMARY KEY (sk_tiempo),
    CONSTRAINT UQ_Dim_Tiempo_fecha UNIQUE (fecha)
)
GO

CREATE TABLE Dim_Cliente (
    sk_cliente       INT IDENTITY(1,1) NOT NULL,
    id_cliente       CHAR(6)       NOT NULL,          -- clave de negocio
    dni              CHAR(10)      NULL,
    nombres          VARCHAR(100)  NOT NULL,
    apellidos        VARCHAR(100)  NOT NULL,
    fecha_nacimiento DATE          NULL,
    correo           VARCHAR(50)   NULL,
    telefono         VARCHAR(50)   NULL,
    tipo_cliente     VARCHAR(100)  NOT NULL,
    direccion        VARCHAR(150)  NULL,
    fecha_inicio     DATE          NOT NULL CONSTRAINT DF_DimCli_ini DEFAULT (CAST(GETDATE() AS DATE)),
    fecha_fin        DATE          NULL,
    es_vigente       BIT           NOT NULL CONSTRAINT DF_DimCli_vig DEFAULT (1),
    CONSTRAINT PK_Dim_Cliente PRIMARY KEY (sk_cliente),
    CONSTRAINT UQ_Dim_Cliente_bk UNIQUE (id_cliente, fecha_inicio)
)
GO

CREATE TABLE Dim_Trabajador (
    sk_trabajador    INT IDENTITY(1,1) NOT NULL,
    id_trabajador    CHAR(6)       NOT NULL,          -- clave de negocio
    dni              CHAR(10)      NULL,
    nombres          VARCHAR(100)  NOT NULL,
    apellidos        VARCHAR(100)  NOT NULL,
    fecha_nacimiento DATE          NULL,
    tipo_trabajador  VARCHAR(100)  NOT NULL,
    cat_laboral      VARCHAR(100)  NOT NULL,
    fecha_inicio     DATE          NOT NULL CONSTRAINT DF_DimTra_ini DEFAULT (CAST(GETDATE() AS DATE)),
    fecha_fin        DATE          NULL,
    es_vigente       BIT           NOT NULL CONSTRAINT DF_DimTra_vig DEFAULT (1),
    CONSTRAINT PK_Dim_Trabajador PRIMARY KEY (sk_trabajador),
    CONSTRAINT UQ_Dim_Trabajador_bk UNIQUE (id_trabajador, fecha_inicio)
)
GO

-- Dim_Producto: incluye el tipo de producto (desnormalizado = estrella)
CREATE TABLE Dim_Producto (
    sk_producto       INT IDENTITY(1,1) NOT NULL,
    cod_producto      CHAR(6)        NOT NULL,        -- clave de negocio
    descripcion       VARCHAR(255)   NOT NULL,
    cod_tipo_producto CHAR(6)        NULL,
    tipo_producto     VARCHAR(255)   NULL,
    estado_producto   VARCHAR(100)   NOT NULL,
    precio_lista      DECIMAL(10,2)  NOT NULL,
    fecha_inicio      DATE           NOT NULL CONSTRAINT DF_DimPro_ini DEFAULT (CAST(GETDATE() AS DATE)),
    fecha_fin         DATE           NULL,
    es_vigente        BIT            NOT NULL CONSTRAINT DF_DimPro_vig DEFAULT (1),
    CONSTRAINT PK_Dim_Producto PRIMARY KEY (sk_producto),
    CONSTRAINT UQ_Dim_Producto_bk UNIQUE (cod_producto, fecha_inicio)
)
GO

-- Dim_Proveedor: incluye el tipo de proveedor (desnormalizado)
CREATE TABLE Dim_Proveedor (
    sk_proveedor      INT IDENTITY(1,1) NOT NULL,
    id_provedor       CHAR(6)        NOT NULL,        -- clave de negocio
    nombre_proveedor  VARCHAR(255)   NOT NULL,
    cod_tipo_provedor CHAR(6)        NULL,
    tipo_proveedor    VARCHAR(255)   NULL,
    limite_credito    DECIMAL(12,2)  NULL,            -- en soles
    plazo_pago_dias   INT            NULL,
    tipo_pago         VARCHAR(100)   NULL,
    estado_credito    VARCHAR(100)   NULL,
    tiene_delivery    BIT            NULL,
    telefono          VARCHAR(50)    NULL,
    fecha_inicio      DATE           NOT NULL CONSTRAINT DF_DimPrv_ini DEFAULT (CAST(GETDATE() AS DATE)),
    fecha_fin         DATE           NULL,
    es_vigente        BIT            NOT NULL CONSTRAINT DF_DimPrv_vig DEFAULT (1),
    CONSTRAINT PK_Dim_Proveedor PRIMARY KEY (sk_proveedor),
    CONSTRAINT UQ_Dim_Proveedor_bk UNIQUE (id_provedor, fecha_inicio)
)
GO

-- Junk dimension: atributos de baja cardinalidad de la venta
CREATE TABLE Dim_Condicion_Venta (
    sk_condicion_venta INT IDENTITY(1,1) NOT NULL,
    tipo_comprobante   VARCHAR(100) NOT NULL,         -- Factura / Boleta
    tipo_venta         VARCHAR(100) NOT NULL,         -- Online / Presencial
    metodo_pago        VARCHAR(100) NOT NULL,         -- Efectivo / Yape / Plin / Tarjeta
    estado_pago        CHAR(1)      NOT NULL,         -- A / P
    estado_pago_desc   VARCHAR(50)  NOT NULL,
    CONSTRAINT PK_Dim_Condicion_Venta PRIMARY KEY (sk_condicion_venta),
    CONSTRAINT UQ_Dim_Condicion_Venta UNIQUE (tipo_comprobante, tipo_venta, metodo_pago, estado_pago)
)
GO

-- Junk dimension: atributos del documento de ingreso
CREATE TABLE Dim_Documento_Ingreso (
    sk_documento_ingreso INT IDENTITY(1,1) NOT NULL,
    tipo_documento       VARCHAR(100) NOT NULL,
    tipo_pago            VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Dim_Documento_Ingreso PRIMARY KEY (sk_documento_ingreso),
    CONSTRAINT UQ_Dim_Documento_Ingreso UNIQUE (tipo_documento, tipo_pago)
)
GO

/* =====================================================================
   2. TABLA PUENTE (relación N:M Producto - Proveedor)
   ===================================================================== */

CREATE TABLE Bridge_Abastecimiento (
    sk_proveedor          INT           NOT NULL,
    sk_producto           INT           NOT NULL,
    precio_abastecimiento DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_Bridge_Abastecimiento PRIMARY KEY (sk_proveedor, sk_producto),
    CONSTRAINT FK_Bridge_Proveedor FOREIGN KEY (sk_proveedor) REFERENCES Dim_Proveedor(sk_proveedor),
    CONSTRAINT FK_Bridge_Producto  FOREIGN KEY (sk_producto)  REFERENCES Dim_Producto(sk_producto)
)
GO

/* =====================================================================
   3. TABLAS DE HECHOS
   ===================================================================== */

-- Granularidad: una fila por línea de comprobante de venta
CREATE TABLE Fact_Ventas (
    sk_fact_venta      BIGINT IDENTITY(1,1) NOT NULL,
    sk_tiempo          INT           NOT NULL,
    sk_cliente         INT           NOT NULL,
    sk_trabajador      INT           NOT NULL,
    sk_producto        INT           NOT NULL,
    sk_condicion_venta INT           NOT NULL,
    nro_comprobante    INT           NOT NULL,        -- dimensión degenerada
    id_detalle         CHAR(6)       NOT NULL,        -- dimensión degenerada
    cantidad           INT           NOT NULL,
    importe_total      DECIMAL(12,2) NOT NULL,
    precio_unitario AS CAST(importe_total / NULLIF(cantidad, 0) AS DECIMAL(10,2)) PERSISTED,
    CONSTRAINT PK_Fact_Ventas PRIMARY KEY (sk_fact_venta),
    CONSTRAINT UQ_Fact_Ventas_bk UNIQUE (nro_comprobante, id_detalle),
    CONSTRAINT FK_FVentas_Tiempo     FOREIGN KEY (sk_tiempo)          REFERENCES Dim_Tiempo(sk_tiempo),
    CONSTRAINT FK_FVentas_Cliente    FOREIGN KEY (sk_cliente)         REFERENCES Dim_Cliente(sk_cliente),
    CONSTRAINT FK_FVentas_Trabajador FOREIGN KEY (sk_trabajador)      REFERENCES Dim_Trabajador(sk_trabajador),
    CONSTRAINT FK_FVentas_Producto   FOREIGN KEY (sk_producto)        REFERENCES Dim_Producto(sk_producto),
    CONSTRAINT FK_FVentas_Condicion  FOREIGN KEY (sk_condicion_venta) REFERENCES Dim_Condicion_Venta(sk_condicion_venta)
)
GO

-- Granularidad: una fila por línea de ingreso de mercadería
CREATE TABLE Fact_Compras (
    sk_fact_compra       BIGINT IDENTITY(1,1) NOT NULL,
    sk_tiempo            INT           NOT NULL,
    sk_proveedor         INT           NOT NULL,
    sk_trabajador        INT           NOT NULL,
    sk_producto          INT           NOT NULL,
    sk_documento_ingreso INT           NOT NULL,
    id_ingreso           CHAR(6)       NOT NULL,      -- dimensión degenerada
    id_detalle_ingreso   CHAR(6)       NOT NULL,      -- dimensión degenerada
    nro_documento        VARCHAR(100)  NULL,          -- dimensión degenerada
    cantidad             INT           NOT NULL,
    precio_unitario      DECIMAL(10,2) NOT NULL,
    subtotal AS CAST(cantidad * precio_unitario AS DECIMAL(14,2)) PERSISTED,
    CONSTRAINT PK_Fact_Compras PRIMARY KEY (sk_fact_compra),
    CONSTRAINT UQ_Fact_Compras_bk UNIQUE (id_ingreso, id_detalle_ingreso),
    CONSTRAINT FK_FCompras_Tiempo     FOREIGN KEY (sk_tiempo)            REFERENCES Dim_Tiempo(sk_tiempo),
    CONSTRAINT FK_FCompras_Proveedor  FOREIGN KEY (sk_proveedor)         REFERENCES Dim_Proveedor(sk_proveedor),
    CONSTRAINT FK_FCompras_Trabajador FOREIGN KEY (sk_trabajador)        REFERENCES Dim_Trabajador(sk_trabajador),
    CONSTRAINT FK_FCompras_Producto   FOREIGN KEY (sk_producto)          REFERENCES Dim_Producto(sk_producto),
    CONSTRAINT FK_FCompras_Documento  FOREIGN KEY (sk_documento_ingreso) REFERENCES Dim_Documento_Ingreso(sk_documento_ingreso)
)
GO

-- Snapshot periódico de stock (medida semi-aditiva): producto x día
CREATE TABLE Fact_Inventario_Snapshot (
    sk_tiempo      INT NOT NULL,
    sk_producto    INT NOT NULL,
    stock_cantidad INT NOT NULL,
    CONSTRAINT PK_Fact_Inventario PRIMARY KEY (sk_tiempo, sk_producto),
    CONSTRAINT FK_FInv_Tiempo   FOREIGN KEY (sk_tiempo)   REFERENCES Dim_Tiempo(sk_tiempo),
    CONSTRAINT FK_FInv_Producto FOREIGN KEY (sk_producto) REFERENCES Dim_Producto(sk_producto)
)
GO

-- Índices sobre las FK de los hechos (acelera joins y filtros)
-- Con volúmenes grandes, evalúa un CLUSTERED COLUMNSTORE INDEX en los hechos.
CREATE INDEX IX_FVentas_Tiempo   ON Fact_Ventas (sk_tiempo)
CREATE INDEX IX_FVentas_Cliente  ON Fact_Ventas (sk_cliente)
CREATE INDEX IX_FVentas_Producto ON Fact_Ventas (sk_producto)
CREATE INDEX IX_FCompras_Tiempo    ON Fact_Compras (sk_tiempo)
CREATE INDEX IX_FCompras_Proveedor ON Fact_Compras (sk_proveedor)
CREATE INDEX IX_FCompras_Producto  ON Fact_Compras (sk_producto)
GO