/*
  DATOS SINTÉTICOS PARA proyecto_dw - MINIMARKET PERUANO
  Importes en soles (PEN). Datos ficticios para fines académicos.
  Ejecutar después de crear las tablas del esquema.
  Ejecutar una sola vez sobre tablas vacías.
*/
USE proyecto_dw;
GO
SET NOCOUNT ON;
SET DATEFIRST 1;
GO

/* Productos */
INSERT INTO dbo.Dim_Producto
(cod_producto, descripcion, cod_tipo_producto, tipo_producto, estado_producto, precio_lista, fecha_inicio, fecha_fin, es_vigente)
VALUES
('000001', N'Arroz Costeño 1 kg', 'ABARR', N'Arroz', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000002', N'Arroz superior a granel 1 kg', 'ABARR', N'Arroz', 'Activo', 3.80, '2025-01-01', NULL, 1),
('000003', N'Azúcar rubia 1 kg', 'ABARR', N'Azúcar', 'Activo', 4.20, '2025-01-01', NULL, 1),
('000004', N'Azúcar blanca 1 kg', 'ABARR', N'Azúcar', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000005', N'Fideos spaghetti 500 g', 'ABARR', N'Pastas', 'Activo', 3.20, '2025-01-01', NULL, 1),
('000006', N'Fideos cabello de ángel 250 g', 'ABARR', N'Pastas', 'Activo', 1.80, '2025-01-01', NULL, 1),
('000007', N'Aceite vegetal 900 ml', 'ABARR', N'Aceites', 'Activo', 8.50, '2025-01-01', NULL, 1),
('000008', N'Aceite vegetal 1 L', 'ABARR', N'Aceites', 'Activo', 9.20, '2025-01-01', NULL, 1),
('000009', N'Sal yodada 1 kg', 'ABARR', N'Condimentos', 'Activo', 2.00, '2025-01-01', NULL, 1),
('000010', N'Lenteja 500 g', 'ABARR', N'Menestras', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000011', N'Frejol canario 500 g', 'ABARR', N'Menestras', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000012', N'Arveja partida 500 g', 'ABARR', N'Menestras', 'Activo', 3.80, '2025-01-01', NULL, 1),
('000013', N'Atún en agua 170 g', 'ABARR', N'Conservas', 'Activo', 5.80, '2025-01-01', NULL, 1),
('000014', N'Sardina en tomate 155 g', 'ABARR', N'Conservas', 'Activo', 4.20, '2025-01-01', NULL, 1),
('000015', N'Leche evaporada 400 g', 'LACTEO', N'Leche', 'Activo', 4.20, '2025-01-01', NULL, 1),
('000016', N'Leche UHT entera 1 L', 'LACTEO', N'Leche', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000017', N'Yogur fresa 1 L', 'LACTEO', N'Yogur', 'Activo', 7.50, '2025-01-01', NULL, 1),
('000018', N'Mantequilla 200 g', 'LACTEO', N'Mantequilla', 'Activo', 8.00, '2025-01-01', NULL, 1),
('000019', N'Queso fresco 250 g', 'LACTEO', N'Quesos', 'Activo', 7.00, '2025-01-01', NULL, 1),
('000020', N'Huevos pardos docena', 'FRESCO', N'Huevos', 'Activo', 9.00, '2025-01-01', NULL, 1),
('000021', N'Pan de molde blanco 500 g', 'PANAD', N'Pan empacado', 'Activo', 7.50, '2025-01-01', NULL, 1),
('000022', N'Galletas de soda 6 pack', 'GOLOSI', N'Galletas', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000023', N'Galletas de vainilla paquete', 'GOLOSI', N'Galletas', 'Activo', 2.20, '2025-01-01', NULL, 1),
('000024', N'Chocolate barra 45 g', 'GOLOSI', N'Chocolates', 'Activo', 3.00, '2025-01-01', NULL, 1),
('000025', N'Caramelos surtidos 100 g', 'GOLOSI', N'Caramelos', 'Activo', 2.50, '2025-01-01', NULL, 1),
('000026', N'Papas fritas 150 g', 'SNACKS', N'Snacks', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000027', N'Chifles 100 g', 'SNACKS', N'Snacks', 'Activo', 3.50, '2025-01-01', NULL, 1),
('000028', N'Maní salado 100 g', 'SNACKS', N'Snacks', 'Activo', 2.80, '2025-01-01', NULL, 1),
('000029', N'Gaseosa cola personal 500 ml', 'BEBIDA', N'Gaseosas', 'Activo', 2.50, '2025-01-01', NULL, 1),
('000030', N'Gaseosa cola 1.5 L', 'BEBIDA', N'Gaseosas', 'Activo', 6.50, '2025-01-01', NULL, 1),
('000031', N'Gaseosa naranja 1.5 L', 'BEBIDA', N'Gaseosas', 'Activo', 5.80, '2025-01-01', NULL, 1),
('000032', N'Agua sin gas 625 ml', 'BEBIDA', N'Agua', 'Activo', 1.50, '2025-01-01', NULL, 1),
('000033', N'Agua sin gas 2.5 L', 'BEBIDA', N'Agua', 'Activo', 3.00, '2025-01-01', NULL, 1),
('000034', N'Jugo néctar durazno 1 L', 'BEBIDA', N'Jugos', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000035', N'Bebida energizante 250 ml', 'BEBIDA', N'Energizantes', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000036', N'Café instantáneo 50 g', 'DESAYU', N'Café', 'Activo', 7.00, '2025-01-01', NULL, 1),
('000037', N'Café molido 250 g', 'DESAYU', N'Café', 'Activo', 12.00, '2025-01-01', NULL, 1),
('000038', N'Avena tradicional 500 g', 'DESAYU', N'Cereales', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000039', N'Hojuelas de maíz 300 g', 'DESAYU', N'Cereales', 'Activo', 8.50, '2025-01-01', NULL, 1),
('000040', N'Cocoa en polvo 160 g', 'DESAYU', N'Cocoa', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000041', N'Harina sin preparar 1 kg', 'ABARR', N'Harinas', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000042', N'Maicena fécula 250 g', 'ABARR', N'Harinas', 'Activo', 3.20, '2025-01-01', NULL, 1),
('000043', N'Vinagre blanco 500 ml', 'ABARR', N'Aderezos', 'Activo', 2.50, '2025-01-01', NULL, 1),
('000044', N'Mayonesa frasco 500 g', 'ABARR', N'Salsas', 'Activo', 8.50, '2025-01-01', NULL, 1),
('000045', N'Kétchup frasco 400 g', 'ABARR', N'Salsas', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000046', N'Sillao 500 ml', 'ABARR', N'Salsas', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000047', N'Detergente en polvo 800 g', 'LIMPIE', N'Detergentes', 'Activo', 8.50, '2025-01-01', NULL, 1),
('000048', N'Lavavajilla 750 ml', 'LIMPIE', N'Lavavajillas', 'Activo', 6.50, '2025-01-01', NULL, 1),
('000049', N'Lejía 1 L', 'LIMPIE', N'Desinfectantes', 'Activo', 3.50, '2025-01-01', NULL, 1),
('000050', N'Limpiador multiuso 900 ml', 'LIMPIE', N'Desinfectantes', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000051', N'Jabón de lavar ropa unidad', 'LIMPIE', N'Jabones', 'Activo', 2.50, '2025-01-01', NULL, 1),
('000052', N'Papel higiénico 4 rollos', 'CUIDAD', N'Papel higiénico', 'Activo', 8.50, '2025-01-01', NULL, 1),
('000053', N'Pañuelos faciales 100 unidades', 'CUIDAD', N'Papel', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000054', N'Jabón de tocador 90 g', 'CUIDAD', N'Jabones', 'Activo', 3.00, '2025-01-01', NULL, 1),
('000055', N'Shampoo sachet 18 ml', 'CUIDAD', N'Cuidado capilar', 'Activo', 1.00, '2025-01-01', NULL, 1),
('000056', N'Pasta dental 90 g', 'CUIDAD', N'Higiene bucal', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000057', N'Cepillo dental adulto', 'CUIDAD', N'Higiene bucal', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000058', N'Toallas higiénicas 8 unidades', 'CUIDAD', N'Higiene femenina', 'Activo', 5.00, '2025-01-01', NULL, 1),
('000059', N'Pañales talla M paquete pequeño', 'BEBE', N'Pañales', 'Activo', 12.00, '2025-01-01', NULL, 1),
('000060', N'Colado infantil 113 g', 'BEBE', N'Alimentos infantiles', 'Activo', 3.50, '2025-01-01', NULL, 1),
('000061', N'Comida para perro 1 kg', 'MASCOT', N'Alimento mascotas', 'Activo', 9.50, '2025-01-01', NULL, 1),
('000062', N'Comida para gato 500 g', 'MASCOT', N'Alimento mascotas', 'Activo', 6.00, '2025-01-01', NULL, 1),
('000063', N'Cebolla roja 1 kg', 'FRESCO', N'Verduras', 'Activo', 3.50, '2025-01-01', NULL, 1),
('000064', N'Papa blanca 1 kg', 'FRESCO', N'Tubérculos', 'Activo', 3.00, '2025-01-01', NULL, 1),
('000065', N'Limón 1 kg', 'FRESCO', N'Frutas', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000066', N'Plátano de seda 1 kg', 'FRESCO', N'Frutas', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000067', N'Manzana corriente 1 kg', 'FRESCO', N'Frutas', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000068', N'Tomate 1 kg', 'FRESCO', N'Verduras', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000069', N'Zanahoria 1 kg', 'FRESCO', N'Verduras', 'Activo', 2.50, '2025-01-01', NULL, 1),
('000070', N'Ajo molido 100 g', 'ABARR', N'Condimentos', 'Activo', 3.00, '2025-01-01', NULL, 1),
('000071', N'Orégano seco 20 g', 'ABARR', N'Condimentos', 'Activo', 1.50, '2025-01-01', NULL, 1),
('000072', N'Ají amarillo pasta 200 g', 'ABARR', N'Salsas', 'Activo', 4.00, '2025-01-01', NULL, 1),
('000073', N'Gelatina sabor fresa 150 g', 'POSTRE', N'Postres', 'Activo', 2.50, '2025-01-01', NULL, 1),
('000074', N'Flan instantáneo 100 g', 'POSTRE', N'Postres', 'Activo', 3.00, '2025-01-01', NULL, 1),
('000075', N'Mermelada fresa 250 g', 'DESAYU', N'Untables', 'Activo', 5.50, '2025-01-01', NULL, 1),
('000076', N'Miel de abeja 250 g', 'DESAYU', N'Untables', 'Activo', 12.00, '2025-01-01', NULL, 1),
('000077', N'Chocolate para taza 90 g', 'DESAYU', N'Chocolate', 'Activo', 4.50, '2025-01-01', NULL, 1),
('000078', N'Chicha morada instantánea 500 g', 'BEBIDA', N'Refrescos', 'Activo', 7.00, '2025-01-01', NULL, 1),
('000079', N'Refresco en polvo sobre', 'BEBIDA', N'Refrescos', 'Activo', 0.80, '2025-01-01', NULL, 1),
('000080', N'Cerveza lager botella 620 ml', 'BEBIDA', N'Cervezas', 'Activo', 6.00, '2025-01-01', NULL, 1);
GO


/* 1. Dim_Tiempo: calendario diario 2025-01-01 a 2026-09-30 */
;WITH Fechas AS (
    SELECT CAST('2025-01-01' AS DATE) AS fecha
    UNION ALL
    SELECT DATEADD(DAY,1,fecha) FROM Fechas WHERE fecha < '2026-09-30'
)
INSERT INTO dbo.Dim_Tiempo
(sk_tiempo,fecha,anio,trimestre,mes,nombre_mes,dia,dia_semana,nombre_dia,es_fin_semana)
SELECT CONVERT(INT,CONVERT(CHAR(8),fecha,112)), fecha, YEAR(fecha),
       DATEPART(QUARTER,fecha), MONTH(fecha),
       CASE MONTH(fecha) WHEN 1 THEN 'enero' WHEN 2 THEN 'febrero' WHEN 3 THEN 'marzo'
       WHEN 4 THEN 'abril' WHEN 5 THEN 'mayo' WHEN 6 THEN 'junio'
       WHEN 7 THEN 'julio' WHEN 8 THEN 'agosto' WHEN 9 THEN 'septiembre'
       WHEN 10 THEN 'octubre' WHEN 11 THEN 'noviembre' ELSE 'diciembre' END,
       DAY(fecha), DATEPART(WEEKDAY,fecha),
       CASE DATEPART(WEEKDAY,fecha) WHEN 1 THEN 'lunes' WHEN 2 THEN 'martes'
       WHEN 3 THEN 'miércoles' WHEN 4 THEN 'jueves' WHEN 5 THEN 'viernes'
       WHEN 6 THEN 'sábado' ELSE 'domingo' END,
       CASE WHEN DATEPART(WEEKDAY,fecha) IN (6,7) THEN 1 ELSE 0 END
FROM Fechas
OPTION (MAXRECURSION 0);
GO

/* 2. Dim_Cliente: 300 clientes ficticios */
DECLARE @Nombres TABLE (id INT IDENTITY(1,1), nombre VARCHAR(40));
INSERT INTO @Nombres(nombre) VALUES
('María'),('José'),('Luis'),('Rosa'),('Carlos'),('Ana'),('Jorge'),('Carmen'),
('Miguel'),('Lucía'),('Pedro'),('Patricia'),('Juan'),('Claudia'),('Diego'),
('Elena'),('Fernando'),('Sofía'),('Ricardo'),('Valeria'),('Andrés'),('Gabriela'),
('Daniel'),('Milagros'),('Marco'),('Fiorella'),('César'),('Paola'),('Arturo'),('Diana');
DECLARE @Apellidos TABLE (id INT IDENTITY(1,1), apellido VARCHAR(40));
INSERT INTO @Apellidos(apellido) VALUES
('Quispe'),('Flores'),('Rojas'),('García'),('Mendoza'),('Torres'),('Ramírez'),
('Huamán'),('Castillo'),('Vargas'),('Chávez'),('Paredes'),('Gutiérrez'),
('Sánchez'),('Fernández'),('Cruz'),('Díaz'),('Medina'),('Vásquez'),('Herrera'),
('Salazar'),('Cárdenas'),('Espinoza'),('Reyes'),('Morales'),('Aguilar'),('Poma'),
('Campos'),('León'),('Romero');
;WITH N AS (SELECT TOP (300) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT INTO dbo.Dim_Cliente
(id_cliente,dni,nombres,apellidos,fecha_nacimiento,correo,telefono,tipo_cliente,direccion,fecha_inicio,fecha_fin,es_vigente)
SELECT RIGHT('000000'+CAST(n AS VARCHAR(6)),6),
       RIGHT('00000000'+CAST(40000000+n AS VARCHAR(8)),8),
       (SELECT nombre FROM @Nombres WHERE id=((n-1)%30)+1),
       (SELECT apellido FROM @Apellidos WHERE id=((n*7-1)%30)+1)+' '+(SELECT apellido FROM @Apellidos WHERE id=((n*11-1)%30)+1),
       DATEADD(DAY, -((n*97)%18000), CAST('2026-01-01' AS DATE)),
       'cliente'+CAST(n AS VARCHAR(3))+'@correo-demo.pe',
       '9'+RIGHT('00000000'+CAST((n*7919)%100000000 AS VARCHAR(8)),8),
       CASE WHEN n%10=0 THEN 'Mayorista' WHEN n%4=0 THEN 'Frecuente' ELSE 'Minorista' END,
       'Lima Norte - Zona '+CAST(((n-1)%8)+1 AS VARCHAR(2)),
       '2025-01-01',NULL,1
FROM N;
GO

/* 3. Dim_Trabajador: 20 colaboradores */
INSERT INTO dbo.Dim_Trabajador
(id_trabajador,dni,nombres,apellidos,fecha_nacimiento,tipo_trabajador,cat_laboral,fecha_inicio,fecha_fin,es_vigente)
VALUES
('T00001','71000001','María','Quispe Rojas','1995-03-12','Cajero','Ventas','2024-01-10',NULL,1),
('T00002','71000002','José','Flores García','1992-07-24','Cajero','Ventas','2024-02-01',NULL,1),
('T00003','71000003','Luis','Mendoza Torres','1998-11-05','Reponedor','Operaciones','2024-03-15',NULL,1),
('T00004','71000004','Rosa','Ramírez Huamán','1990-01-19','Administrador','Administración','2023-06-01',NULL,1),
('T00005','71000005','Carlos','Castillo Vargas','1997-04-30','Cajero','Ventas','2024-05-20',NULL,1),
('T00006','71000006','Ana','Chávez Paredes','1994-09-14','Almacenero','Operaciones','2024-06-03',NULL,1),
('T00007','71000007','Jorge','Gutiérrez Sánchez','1991-12-02','Cajero','Ventas','2024-07-01',NULL,1),
('T00008','71000008','Carmen','Fernández Cruz','1999-02-27','Reponedor','Operaciones','2024-08-12',NULL,1),
('T00009','71000009','Miguel','Díaz Medina','1993-06-18','Supervisor','Administración','2023-04-01',NULL,1),
('T00010','71000010','Lucía','Vásquez Herrera','1996-10-09','Cajero','Ventas','2024-09-02',NULL,1),
('T00011','71000011','Pedro','Salazar Cárdenas','1990-08-21','Almacenero','Operaciones','2023-09-11',NULL,1),
('T00012','71000012','Patricia','Espinoza Reyes','1995-05-16','Cajero','Ventas','2024-10-01',NULL,1),
('T00013','71000013','Juan','Morales Aguilar','1998-01-08','Reponedor','Operaciones','2025-01-02',NULL,1),
('T00014','71000014','Claudia','Poma Campos','1992-03-29','Cajero','Ventas','2025-02-10',NULL,1),
('T00015','71000015','Diego','León Romero','1997-12-17','Auxiliar de almacén','Operaciones','2025-03-01',NULL,1),
('T00016','71000016','Elena','Torres Flores','1991-09-25','Cajero','Ventas','2025-04-14',NULL,1),
('T00017','71000017','Fernando','Rojas Quispe','1994-02-11','Compras','Abastecimiento','2024-01-15',NULL,1),
('T00018','71000018','Sofía','García Mendoza','1996-07-07','Administrador','Administración','2024-04-01',NULL,1),
('T00019','71000019','Ricardo','Huamán Castillo','1989-11-30','Supervisor','Administración','2023-01-10',NULL,1),
('T00020','71000020','Valeria','Vargas Chávez','2000-06-22','Cajero','Ventas','2025-05-05',NULL,1);
GO

/* 5. Dim_Proveedor: mayoristas y distribuidores ficticios */
INSERT INTO dbo.Dim_Proveedor
(id_provedor,nombre_proveedor,cod_tipo_provedor,tipo_proveedor,limite_credito,plazo_pago_dias,tipo_pago,estado_credito,tiene_delivery,telefono,fecha_inicio,fecha_fin,es_vigente)
VALUES
('000001',N'Distribuidora San Jorge',N'TP1',N'Abarrotes y granos', 7500.00, 7, N'Crédito 7 días', N'Aprobado', 1, N'01-640-1001', '2024-01-01', NULL, 1),
('000002',N'Comercializadora Santa Rosa',N'TP2',N'Abarrotes', 10000.00, 15, N'Crédito 15 días', N'Aprobado', 1, N'01-640-1002', '2024-01-01', NULL, 1),
('000003',N'Lácteos del Valle',N'TP3',N'Lácteos y refrigerados', 12500.00, 30, N'Crédito 30 días', N'Aprobado', 1, N'01-640-1003', '2024-01-01', NULL, 1),
('000004',N'Bebidas Lima Norte',N'TP4',N'Bebidas', 15000.00, 0, N'Contado', N'Aprobado', 0, N'01-640-1004', '2024-01-01', NULL, 1),
('000005',N'Alicorp Distribuciones',N'TP5',N'Aceites, pastas y salsas', 5000.00, 7, N'Crédito 7 días', N'En evaluación', 1, N'01-640-1005', '2024-01-01', NULL, 1),
('000006',N'Distribuidora Don Pepe',N'TP6',N'Galletas y snacks', 7500.00, 15, N'Crédito 15 días', N'Aprobado', 1, N'01-640-1006', '2024-01-01', NULL, 1),
('000007',N'Mercado Mayorista Unicachi',N'TP7',N'Frutas y verduras', 10000.00, 30, N'Crédito 30 días', N'Aprobado', 1, N'01-640-1007', '2024-01-01', NULL, 1),
('000008',N'Avícola Los Olivos',N'TP8',N'Huevos y pollo', 12500.00, 0, N'Contado', N'Aprobado', 0, N'01-640-1008', '2024-01-01', NULL, 1),
('000009',N'Limpieza Total Perú',N'TP1',N'Limpieza del hogar', 15000.00, 7, N'Crédito 7 días', N'Aprobado', 1, N'01-640-1009', '2024-01-01', NULL, 1),
('000010',N'Higiene y Hogar SAC',N'TP2',N'Cuidado personal', 5000.00, 15, N'Crédito 15 días', N'En evaluación', 1, N'01-640-1010', '2024-01-01', NULL, 1),
('000011',N'Panificadora San Martín',N'TP3',N'Panadería', 7500.00, 30, N'Crédito 30 días', N'Aprobado', 1, N'01-640-1011', '2024-01-01', NULL, 1),
('000012',N'Dulces del Perú',N'TP4',N'Golosinas y chocolates', 10000.00, 0, N'Contado', N'Aprobado', 0, N'01-640-1012', '2024-01-01', NULL, 1),
('000013',N'Mascotas Felices',N'TP5',N'Alimentos para mascotas', 12500.00, 7, N'Crédito 7 días', N'Aprobado', 1, N'01-640-1013', '2024-01-01', NULL, 1),
('000014',N'Comercial El Ahorro',N'TP6',N'Abarrotes generales', 15000.00, 15, N'Crédito 15 días', N'Aprobado', 1, N'01-640-1014', '2024-01-01', NULL, 1),
('000015',N'Importadora Buen Precio',N'TP7',N'Conservas y enlatados', 5000.00, 30, N'Crédito 30 días', N'En evaluación', 1, N'01-640-1015', '2024-01-01', NULL, 1),
('000016',N'Distribuciones La Canasta',N'TP8',N'Frutas y verduras', 7500.00, 0, N'Contado', N'Aprobado', 0, N'01-640-1016', '2024-01-01', NULL, 1),
('000017',N'Agua Pura Norte',N'TP1',N'Agua y refrescos', 10000.00, 7, N'Crédito 7 días', N'Aprobado', 1, N'01-640-1017', '2024-01-01', NULL, 1),
('000018',N'Mayorista Central',N'TP2',N'Abarrotes y bebidas', 12500.00, 15, N'Crédito 15 días', N'Aprobado', 1, N'01-640-1018', '2024-01-01', NULL, 1),
('000019',N'Productos Andinos SAC',N'TP3',N'Menestras y cereales', 15000.00, 30, N'Crédito 30 días', N'Aprobado', 1, N'01-640-1019', '2024-01-01', NULL, 1),
('000020',N'Distribuidora Primavera',N'TP4',N'Lácteos y postres', 5000.00, 0, N'Contado', N'En evaluación', 0, N'01-640-1020', '2024-01-01', NULL, 1);
GO

/* 6. Dimensiones de condiciones de venta e ingreso */
INSERT INTO dbo.Dim_Condicion_Venta (tipo_comprobante,tipo_venta,metodo_pago,estado_pago,estado_pago_desc)
VALUES
('Boleta','Presencial','Efectivo','A','Pagado'),
('Boleta','Presencial','Yape','A','Pagado'),
('Boleta','Presencial','Plin','A','Pagado'),
('Boleta','Presencial','Tarjeta débito','A','Pagado'),
('Boleta','Presencial','Tarjeta crédito','A','Pagado'),
('Factura','Presencial','Efectivo','A','Pagado'),
('Factura','Presencial','Transferencia','A','Pagado'),
('Factura','Presencial','Tarjeta débito','A','Pagado'),
('Boleta','Online','Yape','A','Pagado'),
('Boleta','Online','Tarjeta débito','A','Pagado'),
('Boleta','Presencial','Efectivo','P','Pendiente'),
('Factura','Presencial','Transferencia','P','Pendiente'),
('Boleta','Online','Yape','P','Pendiente');
GO
INSERT INTO dbo.Dim_Documento_Ingreso (tipo_documento,tipo_pago)
VALUES ('Factura de proveedor','Crédito 15 días'),
       ('Factura de proveedor','Contado'),
       ('Boleta de venta','Contado'),
       ('Guía de remisión','Crédito 30 días'),
       ('Nota de ingreso','Contado');
GO

/* 7. Bridge_Abastecimiento: cada producto se vincula con 3 proveedores */
INSERT INTO dbo.Bridge_Abastecimiento (sk_proveedor,sk_producto,precio_abastecimiento)
SELECT DISTINCT PR.sk_proveedor, P.sk_producto,
       CAST(P.precio_lista * (0.58 + ((PR.sk_proveedor + P.sk_producto) % 12) * 0.015) AS DECIMAL(10,2))
FROM dbo.Dim_Producto P
JOIN dbo.Dim_Proveedor PR ON PR.sk_proveedor IN (((P.sk_producto-1)%20)+1, (P.sk_producto%20)+1, ((P.sk_producto+1)%20)+1);
GO

/* 8. Fact_Ventas: 5,000 líneas de venta, con precios y cantidades verosímiles */
;WITH N AS (
    SELECT TOP (5000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
T AS (
    SELECT
        sk_trabajador,
        ROW_NUMBER() OVER (ORDER BY sk_trabajador) AS rn
    FROM dbo.Dim_Trabajador
),
S AS (
    SELECT
        n,
        DATEADD(
            DAY,
            (n * 7) % 638,
            CAST('2025-01-01' AS DATE)
        ) AS fecha,
        ((n * 13) % 80) + 1 AS producto,
        ((n * 17) % 300) + 1 AS cliente,
        ((n - 1) % (SELECT COUNT(*) FROM dbo.Dim_Trabajador)) + 1
            AS trabajador_rn,
        ((n * 3) % 13) + 1 AS condicion,
        1 + ((n * 11) % 6) AS cantidad
    FROM N
)
INSERT INTO dbo.Fact_Ventas (
    sk_tiempo,
    sk_cliente,
    sk_trabajador,
    sk_producto,
    sk_condicion_venta,
    nro_comprobante,
    id_detalle,
    cantidad,
    importe_total
)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), S.fecha, 112)),
    C.sk_cliente,
    T.sk_trabajador,
    P.sk_producto,
    CV.sk_condicion_venta,
    100000 + S.n,
    RIGHT('000000' + CAST(S.n AS VARCHAR(6)), 6),
    S.cantidad,
    CAST(
        S.cantidad * P.precio_lista
        * (0.94 + ((S.n % 8) * 0.015))
        AS DECIMAL(12,2)
    )
FROM S
JOIN T
    ON T.rn = S.trabajador_rn
JOIN dbo.Dim_Cliente C
    ON C.id_cliente =
       RIGHT('000000' + CAST(S.cliente AS VARCHAR(6)), 6)
JOIN dbo.Dim_Producto P
    ON P.cod_producto =
       RIGHT('000000' + CAST(S.producto AS VARCHAR(6)), 6)
JOIN dbo.Dim_Condicion_Venta CV
    ON CV.sk_condicion_venta = S.condicion;
GO

/* 9. Fact_Compras: 1,500 líneas de ingreso, coste por producto y proveedor */
;WITH N AS (
    SELECT TOP (1500)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),
T AS (
    SELECT
        sk_trabajador,
        ROW_NUMBER() OVER (ORDER BY sk_trabajador) AS rn
    FROM dbo.Dim_Trabajador
),
S AS (
    SELECT
        n,
        DATEADD(DAY, (n * 11) % 638, CAST('2025-01-01' AS DATE)) AS fecha,
        ((n * 13) % 80) + 1 AS producto,
        ((n * 5) % 20) + 1 AS proveedor,
        ((n * 3) % 5) + 1 AS documento,
        10 + ((n * 17) % 100) AS cantidad,
        ((n - 1) % (SELECT COUNT(*) FROM dbo.Dim_Trabajador)) + 1 AS trabajador_rn
    FROM N
)
INSERT INTO dbo.Fact_Compras (
    sk_tiempo,
    sk_proveedor,
    sk_trabajador,
    sk_producto,
    sk_documento_ingreso,
    id_ingreso,
    id_detalle_ingreso,
    nro_documento,
    cantidad,
    precio_unitario
)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), S.fecha, 112)),
    PR.sk_proveedor,
    T.sk_trabajador,
    P.sk_producto,
    D.sk_documento_ingreso,
    RIGHT('000000' + CAST(S.n AS VARCHAR(6)), 6),
    RIGHT('000000' + CAST(S.n AS VARCHAR(6)), 6),
    'F' + RIGHT('000000' + CAST(800000 + S.n AS VARCHAR(6)), 6),
    S.cantidad,
    CAST(
        P.precio_lista * (0.58 + ((S.n % 12) * 0.015))
        AS DECIMAL(10,2)
    )
FROM S
JOIN T
    ON T.rn = S.trabajador_rn
JOIN dbo.Dim_Proveedor PR
    ON PR.id_provedor =
       RIGHT('000000' + CAST(S.proveedor AS VARCHAR(6)), 6)
JOIN dbo.Dim_Producto P
    ON P.cod_producto =
       RIGHT('000000' + CAST(S.producto AS VARCHAR(6)), 6)
JOIN dbo.Dim_Documento_Ingreso D
    ON D.sk_documento_ingreso = S.documento;
GO

/* 10. Inventario diario: producto x día; patrón simulado de reposición y ventas */
;WITH Fechas AS (
    SELECT CAST('2025-01-01' AS DATE) fecha
    UNION ALL SELECT DATEADD(DAY,1,fecha) FROM Fechas WHERE fecha<'2026-09-30'
), Productos AS (
    SELECT sk_producto FROM dbo.Dim_Producto
)
INSERT INTO dbo.Fact_Inventario_Snapshot (sk_tiempo,sk_producto,stock_cantidad)
SELECT CONVERT(INT,CONVERT(CHAR(8),F.fecha,112)), P.sk_producto,
       CASE WHEN ((P.sk_producto*17 + DATEPART(DAYOFYEAR,F.fecha)*7 + MONTH(F.fecha)*13)%100)<8
            THEN 0
            ELSE 5 + ((P.sk_producto*19 + DATEPART(DAYOFYEAR,F.fecha)*3 + MONTH(F.fecha)*11)%85)
       END
FROM Fechas F CROSS JOIN Productos P
OPTION (MAXRECURSION 0);
GO

/* 11. Validación de carga */
SELECT 'Dim_Tiempo' AS tabla, COUNT_BIG(*) AS registros FROM dbo.Dim_Tiempo UNION ALL
SELECT 'Dim_Cliente', COUNT_BIG(*) FROM dbo.Dim_Cliente UNION ALL
SELECT 'Dim_Trabajador', COUNT_BIG(*) FROM dbo.Dim_Trabajador UNION ALL
SELECT 'Dim_Producto', COUNT_BIG(*) FROM dbo.Dim_Producto UNION ALL
SELECT 'Dim_Proveedor', COUNT_BIG(*) FROM dbo.Dim_Proveedor UNION ALL
SELECT 'Dim_Condicion_Venta', COUNT_BIG(*) FROM dbo.Dim_Condicion_Venta UNION ALL
SELECT 'Dim_Documento_Ingreso', COUNT_BIG(*) FROM dbo.Dim_Documento_Ingreso UNION ALL
SELECT 'Bridge_Abastecimiento', COUNT_BIG(*) FROM dbo.Bridge_Abastecimiento UNION ALL
SELECT 'Fact_Ventas', COUNT_BIG(*) FROM dbo.Fact_Ventas UNION ALL
SELECT 'Fact_Compras', COUNT_BIG(*) FROM dbo.Fact_Compras UNION ALL
SELECT 'Fact_Inventario_Snapshot', COUNT_BIG(*) FROM dbo.Fact_Inventario_Snapshot;
GO

/* Ejemplos de comprobación de negocio */
SELECT TOP (10) P.descripcion, SUM(V.cantidad) AS unidades_vendidas, SUM(V.importe_total) AS ventas_soles
FROM dbo.Fact_Ventas V JOIN dbo.Dim_Producto P ON P.sk_producto=V.sk_producto
GROUP BY P.descripcion ORDER BY ventas_soles DESC;
GO

-- VERIFICACIÓN DE TODAS LAS TABLAS --
USE proyecto_dw;
GO

SELECT * FROM dbo.Dim_Tiempo;
GO

SELECT * FROM dbo.Dim_Cliente;
GO

SELECT * FROM dbo.Dim_Trabajador;
GO

SELECT * FROM dbo.Dim_Producto;
GO

SELECT * FROM dbo.Dim_Proveedor;
GO

SELECT * FROM dbo.Dim_Condicion_Venta;
GO

SELECT * FROM dbo.Dim_Documento_Ingreso;
GO

SELECT * FROM dbo.Bridge_Abastecimiento;
GO

SELECT * FROM dbo.Fact_Ventas;
GO

SELECT * FROM dbo.Fact_Compras;
GO

SELECT * FROM dbo.Fact_Inventario_Snapshot;
GO