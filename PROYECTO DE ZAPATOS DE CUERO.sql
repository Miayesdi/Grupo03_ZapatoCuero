CREATE DATABASE ZapatosCuero;
GO
USE ZapatosCuero;
GO

-- ------------------------------------------------------------
-- 1. CLIENTE
-- ------------------------------------------------------------
CREATE TABLE Cliente (
    id_cliente   INT           PRIMARY KEY IDENTITY(1,1),
    nombre       VARCHAR(100)  NOT NULL,
    telefono     VARCHAR(15),
    direccion    VARCHAR(200),
    email        VARCHAR(100)
);
GO

-- ------------------------------------------------------------
-- 2. PRODUCTO
-- ------------------------------------------------------------
CREATE TABLE Producto (
    id_producto  INT           PRIMARY KEY IDENTITY(1,1),
    nombre       VARCHAR(100)  NOT NULL,
    talla        INT           NOT NULL CHECK (talla BETWEEN 35 AND 39),
    precio       DECIMAL(10,2) NOT NULL,
    material     VARCHAR(50)   DEFAULT 'Cuero',
    stock        INT           DEFAULT 0 CHECK (stock >= 0)
);
GO

-- ------------------------------------------------------------
-- 3. PROVEEDOR
-- ------------------------------------------------------------
CREATE TABLE Proveedor (
    id_proveedor INT          PRIMARY KEY IDENTITY(1,1),
    nombre       VARCHAR(100) NOT NULL,
    tipo         VARCHAR(50),          -- 'Fabrica' o 'Material'
    telefono     VARCHAR(15)
);
GO

-- ------------------------------------------------------------
-- 4. PEDIDO
-- ------------------------------------------------------------
CREATE TABLE Pedido (
    id_pedido    INT          PRIMARY KEY IDENTITY(1,1),
    id_cliente   INT          NOT NULL REFERENCES Cliente(id_cliente),
    fecha_pedido DATE         NOT NULL DEFAULT GETDATE(),
    estado       VARCHAR(20)  DEFAULT 'Pendiente'
                              CHECK (estado IN ('Pendiente','En produccion','Listo','Entregado')),
    tipo_retiro  VARCHAR(30)  DEFAULT 'Recojo en taller'
);
GO

-- ------------------------------------------------------------
-- 5. DETALLE_PEDIDO  (tabla intermedia Pedido <-> Producto)
-- ------------------------------------------------------------
CREATE TABLE Detalle_Pedido (
    id_detalle      INT           PRIMARY KEY IDENTITY(1,1),
    id_pedido       INT           NOT NULL REFERENCES Pedido(id_pedido),
    id_producto     INT           NOT NULL REFERENCES Producto(id_producto),
    cantidad        INT           NOT NULL CHECK (cantidad > 0),
    precio_unitario DECIMAL(10,2) NOT NULL
);
GO

-- ------------------------------------------------------------
-- 6. PAGO
-- ------------------------------------------------------------
CREATE TABLE Pago (
    id_pago    INT           PRIMARY KEY IDENTITY(1,1),
    id_pedido  INT           NOT NULL REFERENCES Pedido(id_pedido),
    metodo     VARCHAR(20)   NOT NULL
                             CHECK (metodo IN ('Yape','Plin','Transferencia','Efectivo')),
    monto      DECIMAL(10,2) NOT NULL,
    fecha_pago DATE          NOT NULL DEFAULT GETDATE()
);
GO

-- ------------------------------------------------------------
-- 7. COMPRA_MATERIAL
-- ------------------------------------------------------------
CREATE TABLE Compra_Material (
    id_compra    INT           PRIMARY KEY IDENTITY(1,1),
    id_proveedor INT           NOT NULL REFERENCES Proveedor(id_proveedor),
    fecha_compra DATE          NOT NULL DEFAULT GETDATE(),
    costo_total  DECIMAL(10,2) NOT NULL,
    descripcion  VARCHAR(200)
);
GO

-- ------------------------------------------------------------
-- 8. REPORTE  (se genera mensualmente)
-- ------------------------------------------------------------
CREATE TABLE Reporte (
    id_reporte       INT           PRIMARY KEY IDENTITY(1,1),
    periodo          VARCHAR(20)   NOT NULL,   -- Ej: '2025-01'
    fecha_generacion DATE          NOT NULL DEFAULT GETDATE(),
    total_ventas     DECIMAL(10,2),
    total_pedidos    INT
);
GO


-- ============================================================
--  DATOS DE PRUEBA
-- ============================================================

-- Clientes
INSERT INTO Cliente (nombre, telefono, direccion, email) VALUES
('Maria Torres',   '987654321', 'Av. Lima 123',     'maria@gmail.com'),
('Lucia Ramirez',  '912345678', 'Jr. Cusco 456',    'lucia@gmail.com'),
('Carmen Flores',  '965432100', 'Calle Ica 789',    'carmen@gmail.com'),
('Rosa Vargas',    '971234567', 'Av. Arequipa 321', 'rosa@gmail.com');
GO

-- Productos
INSERT INTO Producto (nombre, talla, precio, material, stock) VALUES
('Sandalia clasica',    35, 85.00,  'Cuero', 10),
('Balerina elegante',   36, 95.00,  'Cuero', 8),
('Mocasin confort',     37, 110.00, 'Cuero', 6),
('Zapato formal dama',  38, 130.00, 'Cuero', 5),
('Bota corta cuero',    39, 160.00, 'Cuero', 4);
GO

-- Proveedores
INSERT INTO Proveedor (nombre, tipo, telefono) VALUES
('Fabrica Piel Peru',   'Fabrica',   '01-3456789'),
('Distribuidora Cuero', 'Material',  '01-9876543');
GO

-- Pedidos
INSERT INTO Pedido (id_cliente, fecha_pedido, estado, tipo_retiro) VALUES
(1, '2025-01-05', 'Entregado',    'Recojo en taller'),
(2, '2025-01-12', 'Entregado',    'Recojo en taller'),
(3, '2025-02-03', 'En produccion','Recojo en taller'),
(4, '2025-02-18', 'Pendiente',    'Recojo en taller');
GO

-- Detalle de pedidos
INSERT INTO Detalle_Pedido (id_pedido, id_producto, cantidad, precio_unitario) VALUES
(1, 1, 2,  85.00),
(1, 3, 1, 110.00),
(2, 2, 1,  95.00),
(3, 4, 2, 130.00),
(4, 5, 1, 160.00);
GO

-- Pagos
INSERT INTO Pago (id_pedido, metodo, monto, fecha_pago) VALUES
(1, 'Yape',          280.00, '2025-01-05'),
(2, 'Efectivo',       95.00, '2025-01-12'),
(3, 'Transferencia', 260.00, '2025-02-03');
GO

-- Compras de material
INSERT INTO Compra_Material (id_proveedor, fecha_compra, costo_total, descripcion) VALUES
(2, '2025-01-02', 350.00, 'Cuero vacuno color negro y marron'),
(1, '2025-01-30', 600.00, 'Docena de sandalia clasica sin terminar');
GO


-- ============================================================
--  CONSULTAS UTILES (reportes mensuales y estadisticas)
-- ============================================================

-- 1. Total de ventas por mes
SELECT
    FORMAT(P.fecha_pedido, 'yyyy-MM') AS mes,
    COUNT(DISTINCT P.id_pedido)        AS total_pedidos,
    SUM(PA.monto)                      AS total_cobrado
FROM Pedido P
JOIN Pago PA ON P.id_pedido = PA.id_pedido
GROUP BY FORMAT(P.fecha_pedido, 'yyyy-MM')
ORDER BY mes;
GO

-- 2. Productos mas vendidos
SELECT
    PR.nombre,
    PR.talla,
    SUM(DP.cantidad) AS unidades_vendidas
FROM Detalle_Pedido DP
JOIN Producto PR ON DP.id_producto = PR.id_producto
GROUP BY PR.nombre, PR.talla
ORDER BY unidades_vendidas DESC;
GO

-- 3. Ingresos por metodo de pago
SELECT
    metodo,
    COUNT(*)    AS cantidad_transacciones,
    SUM(monto)  AS total_recaudado
FROM Pago
GROUP BY metodo
ORDER BY total_recaudado DESC;
GO

-- 4. Estado actual de todos los pedidos
SELECT
    P.id_pedido,
    C.nombre       AS cliente,
    P.fecha_pedido,
    P.estado,
    SUM(DP.cantidad * DP.precio_unitario) AS total_pedido
FROM Pedido P
JOIN Cliente C         ON P.id_cliente  = C.id_cliente
JOIN Detalle_Pedido DP ON P.id_pedido   = DP.id_pedido
GROUP BY P.id_pedido, C.nombre, P.fecha_pedido, P.estado
ORDER BY P.fecha_pedido DESC;
GO

-- 5. Generar reporte mensual de enero 2025
INSERT INTO Reporte (periodo, total_ventas, total_pedidos)
SELECT
    '2025-01',
    SUM(PA.monto),
    COUNT(DISTINCT P.id_pedido)
FROM Pedido P
JOIN Pago PA ON P.id_pedido = PA.id_pedido
WHERE FORMAT(P.fecha_pedido, 'yyyy-MM') = '2025-01';
GO

BACKUP DATABASE ZapatosCuero
TO DISK = 'C:\BackupDayluz\Dayluz_Backup.bak'
WITH FORMAT;
GO