USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'DW_Dayluz')
    DROP DATABASE DW_Dayluz;
GO

CREATE DATABASE DW_Dayluz;
GO

USE DW_Dayluz;
GO

-- ============================================================
--  1. TABLAS DE DIMENSION
-- ============================================================

-- Dimension Tiempo
CREATE TABLE Dim_Tiempo (
    id_tiempo    INT          PRIMARY KEY,   -- Clave surrogada: YYYYMMDD
    fecha        DATE         NOT NULL,
    dia          INT          NOT NULL,
    nombre_dia   NVARCHAR(15) NOT NULL,
    semana       INT          NOT NULL,
    mes          INT          NOT NULL,
    nombre_mes   NVARCHAR(15) NOT NULL,
    trimestre    INT          NOT NULL,
    anio         INT          NOT NULL,
    es_fin_semana BIT         DEFAULT 0
);
GO

-- Dimension Producto
CREATE TABLE Dim_Producto (
    id_producto_sk  INT          PRIMARY KEY IDENTITY(1,1),  -- Clave surrogada
    id_producto_nk  INT          NOT NULL,                   -- Clave natural (de OLTP)
    nombre          NVARCHAR(100) NOT NULL,
    talla           INT          NOT NULL,
    material        NVARCHAR(50),
    categoria       NVARCHAR(50) DEFAULT 'Calzado de cuero',
    rango_precio    NVARCHAR(20),  -- 'Economico', 'Medio', 'Premium'
    fecha_inicio    DATE         DEFAULT GETDATE(),
    fecha_fin       DATE         DEFAULT '9999-12-31',
    vigente         BIT          DEFAULT 1
);
GO

-- Dimension Cliente
CREATE TABLE Dim_Cliente (
    id_cliente_sk  INT          PRIMARY KEY IDENTITY(1,1),
    id_cliente_nk  INT          NOT NULL,
    nombre         NVARCHAR(100),
    distrito       NVARCHAR(100),
    segmento       NVARCHAR(50) DEFAULT 'Cliente regular',
    fecha_inicio   DATE         DEFAULT GETDATE(),
    vigente        BIT          DEFAULT 1
);
GO

-- Dimension Metodo de Pago
CREATE TABLE Dim_MetodoPago (
    id_metodo_pago INT          PRIMARY KEY IDENTITY(1,1),
    nombre_metodo  NVARCHAR(20) NOT NULL,
    tipo           NVARCHAR(30),  -- 'Digital', 'Bancario', 'Efectivo'
    descripcion    NVARCHAR(100)
);
GO

-- Dimension Proveedor
CREATE TABLE Dim_Proveedor (
    id_proveedor_sk INT          PRIMARY KEY IDENTITY(1,1),
    id_proveedor_nk INT          NOT NULL,
    nombre          NVARCHAR(100),
    tipo            NVARCHAR(50),
    vigente         BIT          DEFAULT 1
);
GO

-- ============================================================
--  2. TABLA DE HECHOS: Ventas
-- ============================================================
CREATE TABLE Fact_Ventas (
    id_venta              INT           PRIMARY KEY IDENTITY(1,1),
    id_tiempo             INT           NOT NULL REFERENCES Dim_Tiempo(id_tiempo),
    id_producto_sk        INT           NOT NULL REFERENCES Dim_Producto(id_producto_sk),
    id_cliente_sk         INT           NOT NULL REFERENCES Dim_Cliente(id_cliente_sk),
    id_metodo_pago        INT           NOT NULL REFERENCES Dim_MetodoPago(id_metodo_pago),
    -- Metricas
    cantidad              INT           NOT NULL,
    precio_unitario       DECIMAL(10,2) NOT NULL,
    monto_total           DECIMAL(10,2) NOT NULL,
    -- Claves naturales para trazabilidad
    id_pedido_nk          INT           NOT NULL,
    id_detalle_nk         INT           NOT NULL
);
GO

-- ============================================================
--  3. TABLA DE HECHOS: Compras de Material
-- ============================================================
CREATE TABLE Fact_Compras (
    id_hecho_compra  INT           PRIMARY KEY IDENTITY(1,1),
    id_tiempo        INT           NOT NULL REFERENCES Dim_Tiempo(id_tiempo),
    id_proveedor_sk  INT           NOT NULL REFERENCES Dim_Proveedor(id_proveedor_sk),
    costo_total      DECIMAL(10,2) NOT NULL,
    descripcion      NVARCHAR(200),
    id_compra_nk     INT           NOT NULL
);
GO

-- ============================================================
--  4. INDICES para optimizar consultas OLAP
-- ============================================================
CREATE INDEX IX_FactVentas_Tiempo    ON Fact_Ventas(id_tiempo);
CREATE INDEX IX_FactVentas_Producto  ON Fact_Ventas(id_producto_sk);
CREATE INDEX IX_FactVentas_Cliente   ON Fact_Ventas(id_cliente_sk);
CREATE INDEX IX_FactVentas_Pago      ON Fact_Ventas(id_metodo_pago);
CREATE INDEX IX_FactCompras_Tiempo   ON Fact_Compras(id_tiempo);
CREATE INDEX IX_FactCompras_Prov     ON Fact_Compras(id_proveedor_sk);
GO

-- ============================================================
--  5. POBLAR DIMENSION TIEMPO (2025 - 2026)
-- ============================================================
DECLARE @fecha DATE = '2025-01-01';
DECLARE @fecha_fin DATE = '2026-12-31';

WHILE @fecha <= @fecha_fin
BEGIN
    INSERT INTO Dim_Tiempo (
        id_tiempo, fecha, dia, nombre_dia, semana,
        mes, nombre_mes, trimestre, anio, es_fin_semana
    )
    VALUES (
        CAST(FORMAT(@fecha,'yyyyMMdd') AS INT),
        @fecha,
        DAY(@fecha),
        DATENAME(WEEKDAY, @fecha),
        DATEPART(WEEK, @fecha),
        MONTH(@fecha),
        DATENAME(MONTH, @fecha),
        DATEPART(QUARTER, @fecha),
        YEAR(@fecha),
        CASE WHEN DATEPART(WEEKDAY,@fecha) IN (1,7) THEN 1 ELSE 0 END
    );
    SET @fecha = DATEADD(DAY, 1, @fecha);
END;
GO

-- ============================================================
--  6. VISTAS ANALITICAS OLAP
-- ============================================================

-- Vista 1: Ventas mensuales con todas las dimensiones
CREATE VIEW v_VentasMensuales AS
SELECT
    T.anio,
    T.nombre_mes,
    T.mes,
    T.trimestre,
    P.nombre       AS producto,
    P.talla,
    P.rango_precio,
    C.nombre       AS cliente,
    C.distrito,
    MP.nombre_metodo AS metodo_pago,
    MP.tipo          AS tipo_pago,
    FV.cantidad,
    FV.precio_unitario,
    FV.monto_total
FROM Fact_Ventas FV
JOIN Dim_Tiempo      T  ON FV.id_tiempo       = T.id_tiempo
JOIN Dim_Producto    P  ON FV.id_producto_sk  = P.id_producto_sk
JOIN Dim_Cliente     C  ON FV.id_cliente_sk   = C.id_cliente_sk
JOIN Dim_MetodoPago  MP ON FV.id_metodo_pago  = MP.id_metodo_pago;
GO

-- Vista 2: Rentabilidad por periodo (ventas vs compras)
CREATE VIEW v_Rentabilidad AS
SELECT
    T.anio,
    T.nombre_mes,
    T.mes,
    ISNULL(SUM(FV.monto_total), 0)  AS total_ventas,
    ISNULL(SUM(FC.costo_total), 0)  AS total_compras,
    ISNULL(SUM(FV.monto_total), 0) - ISNULL(SUM(FC.costo_total), 0) AS ganancia_neta
FROM Dim_Tiempo T
LEFT JOIN Fact_Ventas   FV ON T.id_tiempo = FV.id_tiempo
LEFT JOIN Fact_Compras  FC ON T.id_tiempo = FC.id_tiempo
WHERE T.anio >= 2025
GROUP BY T.anio, T.nombre_mes, T.mes;
GO

-- Vista 3: Top productos por ventas
CREATE VIEW v_TopProductos AS
SELECT
    P.nombre        AS producto,
    P.talla,
    P.rango_precio,
    SUM(FV.cantidad)      AS unidades_vendidas,
    SUM(FV.monto_total)   AS ingresos_generados,
    COUNT(DISTINCT FV.id_pedido_nk) AS pedidos_distintos
FROM Fact_Ventas FV
JOIN Dim_Producto P ON FV.id_producto_sk = P.id_producto_sk
GROUP BY P.nombre, P.talla, P.rango_precio;
GO

-- Vista 4: Distribucion por metodo de pago
CREATE VIEW v_MetodosPago AS
SELECT
    MP.nombre_metodo,
    MP.tipo,
    COUNT(*)          AS transacciones,
    SUM(FV.monto_total) AS total_recaudado,
    ROUND(SUM(FV.monto_total) * 100.0 / SUM(SUM(FV.monto_total)) OVER(), 2) AS porcentaje
FROM Fact_Ventas FV
JOIN Dim_MetodoPago MP ON FV.id_metodo_pago = MP.id_metodo_pago
GROUP BY MP.nombre_metodo, MP.tipo;
GO

-- Vista 5: Compras por proveedor y periodo
CREATE VIEW v_ComprasProveedor AS
SELECT
    T.anio,
    T.nombre_mes,
    PR.nombre       AS proveedor,
    PR.tipo,
    COUNT(*)        AS num_compras,
    SUM(FC.costo_total) AS total_invertido
FROM Fact_Compras FC
JOIN Dim_Tiempo    T  ON FC.id_tiempo       = T.id_tiempo
JOIN Dim_Proveedor PR ON FC.id_proveedor_sk = PR.id_proveedor_sk
GROUP BY T.anio, T.nombre_mes, PR.nombre, PR.tipo;
GO