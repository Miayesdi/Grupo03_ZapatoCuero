USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'ZapatosCuero')
    DROP DATABASE ZapatosCuero;
GO

CREATE DATABASE ZapatosCuero;
GO

USE ZapatosCuero;
GO

--  1. CREACION DE TABLAS

-- Tabla: Cliente
CREATE TABLE Cliente (
    id_cliente   INT           PRIMARY KEY IDENTITY(1,1),
    nombre       NVARCHAR(100) NOT NULL,
    telefono     NVARCHAR(15),
    direccion    NVARCHAR(200),
    email        NVARCHAR(100),
    fecha_registro DATE        DEFAULT GETDATE()
);
GO

-- Tabla: Producto
CREATE TABLE Producto (
    id_producto  INT           PRIMARY KEY IDENTITY(1,1),
    nombre       NVARCHAR(100) NOT NULL,
    talla        INT           NOT NULL CHECK (talla BETWEEN 35 AND 39),
    precio       DECIMAL(10,2) NOT NULL CHECK (precio > 0),
    material     NVARCHAR(50)  DEFAULT 'Cuero',
    stock        INT           DEFAULT 0 CHECK (stock >= 0)
);
GO

-- Tabla: Proveedor
CREATE TABLE Proveedor (
    id_proveedor INT           PRIMARY KEY IDENTITY(1,1),
    nombre       NVARCHAR(100) NOT NULL,
    tipo         NVARCHAR(50)  CHECK (tipo IN ('Fabrica','Material','Ambos')),
    telefono     NVARCHAR(15)
);
GO

-- Tabla: Pedido
CREATE TABLE Pedido (
    id_pedido    INT           PRIMARY KEY IDENTITY(1,1),
    id_cliente   INT           NOT NULL REFERENCES Cliente(id_cliente),
    fecha_pedido DATE          NOT NULL DEFAULT GETDATE(),
    estado       NVARCHAR(20)  DEFAULT 'Pendiente'
                               CHECK (estado IN ('Pendiente','En produccion','Listo','Entregado','Cancelado')),
    tipo_retiro  NVARCHAR(30)  DEFAULT 'Recojo en taller'
);
GO

-- Tabla: Detalle_Pedido
CREATE TABLE Detalle_Pedido (
    id_detalle      INT           PRIMARY KEY IDENTITY(1,1),
    id_pedido       INT           NOT NULL REFERENCES Pedido(id_pedido),
    id_producto     INT           NOT NULL REFERENCES Producto(id_producto),
    cantidad        INT           NOT NULL CHECK (cantidad > 0),
    precio_unitario DECIMAL(10,2) NOT NULL CHECK (precio_unitario > 0)
);
GO

-- Tabla: Pago
CREATE TABLE Pago (
    id_pago    INT           PRIMARY KEY IDENTITY(1,1),
    id_pedido  INT           NOT NULL REFERENCES Pedido(id_pedido),
    metodo     NVARCHAR(20)  NOT NULL
                             CHECK (metodo IN ('Yape','Plin','Transferencia','Efectivo')),
    monto      DECIMAL(10,2) NOT NULL CHECK (monto > 0),
    fecha_pago DATE          NOT NULL DEFAULT GETDATE()
);
GO

-- Tabla: Compra_Material
CREATE TABLE Compra_Material (
    id_compra    INT           PRIMARY KEY IDENTITY(1,1),
    id_proveedor INT           NOT NULL REFERENCES Proveedor(id_proveedor),
    fecha_compra DATE          NOT NULL DEFAULT GETDATE(),
    costo_total  DECIMAL(10,2) NOT NULL CHECK (costo_total > 0),
    descripcion  NVARCHAR(200)
);
GO

-- Tabla: Reporte
CREATE TABLE Reporte (
    id_reporte       INT           PRIMARY KEY IDENTITY(1,1),
    periodo          NVARCHAR(7)   NOT NULL,   -- Formato: 'YYYY-MM'
    fecha_generacion DATE          NOT NULL DEFAULT GETDATE(),
    total_ventas     DECIMAL(10,2),
    total_compras    DECIMAL(10,2),
    ganancia_neta    DECIMAL(10,2),
    total_pedidos    INT
);
GO

-- Tabla: AuditoriaDB (Log de operaciones)
CREATE TABLE AuditoriaDB (
    id_auditoria   INT           PRIMARY KEY IDENTITY(1,1),
    tabla_afectada NVARCHAR(50),
    operacion      NVARCHAR(10)  CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    usuario_bd     NVARCHAR(100) DEFAULT SUSER_SNAME(),
    fecha_hora     DATETIME      DEFAULT GETDATE(),
    descripcion    NVARCHAR(500)
);
GO

--  2. INDICES
CREATE INDEX IX_Pedido_Cliente    ON Pedido(id_cliente);
CREATE INDEX IX_DetallePedido_Ped ON Detalle_Pedido(id_pedido);
CREATE INDEX IX_DetallePedido_Pro ON Detalle_Pedido(id_producto);
CREATE INDEX IX_Pago_Pedido       ON Pago(id_pedido);
CREATE INDEX IX_Compra_Proveedor  ON Compra_Material(id_proveedor);
GO

--  3. PROCEDIMIENTOS ALMACENADOS

-- SP 1: Registrar un pedido completo (cabecera + detalle + pago atomico)
CREATE OR ALTER PROCEDURE sp_RegistrarPedido
    @id_cliente    INT,
    @metodo_pago   NVARCHAR(20),
    @productos     NVARCHAR(MAX)   -- JSON: [{"id_producto":1,"cantidad":2},...]
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Insertar cabecera de pedido
        INSERT INTO Pedido (id_cliente, fecha_pedido, estado)
        VALUES (@id_cliente, GETDATE(), 'Pendiente');

        DECLARE @id_pedido INT = SCOPE_IDENTITY();
        DECLARE @total DECIMAL(10,2) = 0;

        -- Procesar cada producto del JSON
        DECLARE @id_prod INT, @cant INT, @precio DECIMAL(10,2), @stock_actual INT;

        DECLARE cur CURSOR FOR
            SELECT CAST(JSON_VALUE(value,'$.id_producto') AS INT),
                   CAST(JSON_VALUE(value,'$.cantidad')    AS INT)
            FROM OPENJSON(@productos);

        OPEN cur;
        FETCH NEXT FROM cur INTO @id_prod, @cant;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Verificar stock
            SELECT @stock_actual = stock, @precio = precio
            FROM Producto WHERE id_producto = @id_prod;

            IF @stock_actual < @cant
                THROW 50001, 'Stock insuficiente para el producto solicitado.', 1;

            -- Insertar detalle
            INSERT INTO Detalle_Pedido (id_pedido, id_producto, cantidad, precio_unitario)
            VALUES (@id_pedido, @id_prod, @cant, @precio);

            -- Actualizar stock
            UPDATE Producto SET stock = stock - @cant WHERE id_producto = @id_prod;

            SET @total = @total + (@precio * @cant);
            FETCH NEXT FROM cur INTO @id_prod, @cant;
        END;

        CLOSE cur;
        DEALLOCATE cur;

        -- Registrar pago
        INSERT INTO Pago (id_pedido, metodo, monto, fecha_pago)
        VALUES (@id_pedido, @metodo_pago, @total, GETDATE());

        COMMIT TRANSACTION;
        SELECT @id_pedido AS id_pedido_creado, @total AS total_pagado;
        PRINT 'Pedido registrado exitosamente.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @msg NVARCHAR(500) = ERROR_MESSAGE();
        PRINT 'ERROR: ' + @msg;
        THROW;
    END CATCH;
END;
GO

-- SP 2: Actualizar estado de un pedido
CREATE OR ALTER PROCEDURE sp_ActualizarEstadoPedido
    @id_pedido INT,
    @nuevo_estado NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Pedido WHERE id_pedido = @id_pedido)
            THROW 50002, 'El pedido especificado no existe.', 1;

        UPDATE Pedido
        SET estado = @nuevo_estado
        WHERE id_pedido = @id_pedido;

        PRINT 'Estado del pedido actualizado a: ' + @nuevo_estado;
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: ' + ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

-- SP 3: Generar reporte mensual automatico
CREATE OR ALTER PROCEDURE sp_GenerarReporteMensual
    @periodo NVARCHAR(7)   -- Formato: 'YYYY-MM'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @total_ventas  DECIMAL(10,2);
        DECLARE @total_compras DECIMAL(10,2);
        DECLARE @total_pedidos INT;
        DECLARE @ganancia      DECIMAL(10,2);

        -- Calcular ventas del periodo
        SELECT @total_ventas = ISNULL(SUM(PA.monto), 0),
               @total_pedidos = COUNT(DISTINCT PE.id_pedido)
        FROM Pedido PE
        JOIN Pago PA ON PE.id_pedido = PA.id_pedido
        WHERE FORMAT(PE.fecha_pedido, 'yyyy-MM') = @periodo
          AND PE.estado = 'Entregado';

        -- Calcular compras del periodo
        SELECT @total_compras = ISNULL(SUM(costo_total), 0)
        FROM Compra_Material
        WHERE FORMAT(fecha_compra, 'yyyy-MM') = @periodo;

        SET @ganancia = @total_ventas - @total_compras;

        -- Insertar o actualizar reporte
        IF EXISTS (SELECT 1 FROM Reporte WHERE periodo = @periodo)
            UPDATE Reporte
            SET total_ventas = @total_ventas,
                total_compras = @total_compras,
                ganancia_neta = @ganancia,
                total_pedidos = @total_pedidos,
                fecha_generacion = GETDATE()
            WHERE periodo = @periodo;
        ELSE
            INSERT INTO Reporte (periodo, total_ventas, total_compras, ganancia_neta, total_pedidos)
            VALUES (@periodo, @total_ventas, @total_compras, @ganancia, @total_pedidos);

        -- Mostrar resultado
        SELECT @periodo            AS periodo,
               @total_ventas       AS total_ventas,
               @total_compras      AS total_compras,
               @ganancia           AS ganancia_neta,
               @total_pedidos      AS total_pedidos;

        PRINT 'Reporte del periodo ' + @periodo + ' generado correctamente.';
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: ' + ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

-- SP 4: Registrar compra de material
CREATE OR ALTER PROCEDURE sp_RegistrarCompra
    @id_proveedor INT,
    @descripcion  NVARCHAR(200),
    @costo_total  DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Proveedor WHERE id_proveedor = @id_proveedor)
            THROW 50003, 'El proveedor especificado no existe.', 1;

        INSERT INTO Compra_Material (id_proveedor, fecha_compra, costo_total, descripcion)
        VALUES (@id_proveedor, GETDATE(), @costo_total, @descripcion);

        PRINT 'Compra de material registrada. ID: ' + CAST(SCOPE_IDENTITY() AS NVARCHAR);
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: ' + ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

-- SP 5: Consultar stock bajo (alerta)
CREATE OR ALTER PROCEDURE sp_AlertaStockBajo
    @stock_minimo INT = 3
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_producto, nombre, talla, stock,
           CASE WHEN stock = 0 THEN 'SIN STOCK' ELSE 'STOCK BAJO' END AS alerta
    FROM Producto
    WHERE stock <= @stock_minimo
    ORDER BY stock ASC;
END;
GO

--  4. FUNCIONES

-- Funcion 1: Calcular total de un pedido
CREATE OR ALTER FUNCTION fn_TotalPedido (@id_pedido INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @total DECIMAL(10,2);
    SELECT @total = ISNULL(SUM(cantidad * precio_unitario), 0)
    FROM Detalle_Pedido
    WHERE id_pedido = @id_pedido;
    RETURN @total;
END;
GO

-- Funcion 2: Obtener nombre del metodo de pago mas usado
CREATE OR ALTER FUNCTION fn_MetodoPagoMasUsado ()
RETURNS NVARCHAR(20)
AS
BEGIN
    DECLARE @metodo NVARCHAR(20);
    SELECT TOP 1 @metodo = metodo
    FROM Pago
    GROUP BY metodo
    ORDER BY COUNT(*) DESC;
    RETURN ISNULL(@metodo, 'Sin datos');
END;
GO

-- Funcion 3: Calcular ganancia de un periodo
CREATE OR ALTER FUNCTION fn_GananciaPeriodo (@periodo NVARCHAR(7))
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @ventas  DECIMAL(10,2);
    DECLARE @compras DECIMAL(10,2);

    SELECT @ventas = ISNULL(SUM(PA.monto), 0)
    FROM Pedido PE JOIN Pago PA ON PE.id_pedido = PA.id_pedido
    WHERE FORMAT(PE.fecha_pedido,'yyyy-MM') = @periodo AND PE.estado = 'Entregado';

    SELECT @compras = ISNULL(SUM(costo_total), 0)
    FROM Compra_Material
    WHERE FORMAT(fecha_compra,'yyyy-MM') = @periodo;

    RETURN @ventas - @compras;
END;
GO

--  5. TRIGGERS

-- Trigger 1: Auditoria de INSERT/UPDATE/DELETE en tabla Pedido
CREATE OR ALTER TRIGGER tr_AuditoriaPedido
ON Pedido
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @op NVARCHAR(10);

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @op = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @op = 'INSERT';
    ELSE
        SET @op = 'DELETE';

    INSERT INTO AuditoriaDB (tabla_afectada, operacion, usuario_bd, fecha_hora, descripcion)
    SELECT 'Pedido', @op, SUSER_SNAME(), GETDATE(),
           'id_pedido: ' + CAST(ISNULL(i.id_pedido, d.id_pedido) AS NVARCHAR)
           + ' | Estado: ' + ISNULL(i.estado, d.estado)
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_pedido = d.id_pedido;
END;
GO

-- Trigger 2: Validar que no se registre un pago duplicado por pedido
CREATE OR ALTER TRIGGER tr_ValidarPagoDuplicado
ON Pago
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT id_pedido FROM Pago
        GROUP BY id_pedido
        HAVING COUNT(*) > 1
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50004, 'Ya existe un pago registrado para este pedido.', 1;
    END;
END;
GO

-- Trigger 3: Auditoria de cambios en Producto (stock)
CREATE OR ALTER TRIGGER tr_AuditoriaProducto
ON Producto
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO AuditoriaDB (tabla_afectada, operacion, usuario_bd, fecha_hora, descripcion)
    SELECT 'Producto', 'UPDATE', SUSER_SNAME(), GETDATE(),
           'id_producto: ' + CAST(i.id_producto AS NVARCHAR)
           + ' | Stock anterior: ' + CAST(d.stock AS NVARCHAR)
           + ' -> Stock nuevo: ' + CAST(i.stock AS NVARCHAR)
    FROM inserted i
    JOIN deleted d ON i.id_producto = d.id_producto
    WHERE i.stock <> d.stock;
END;
GO

--  6. CURSOR - Resumen de compras por proveedor
-- Uso: EXEC sp_ResumenProveedores
CREATE OR ALTER PROCEDURE sp_ResumenProveedores
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_prov     INT;
    DECLARE @nom_prov    NVARCHAR(100);
    DECLARE @total_comp  DECIMAL(10,2);
    DECLARE @num_comp    INT;

    DECLARE cur_prov CURSOR FOR
        SELECT P.id_proveedor, P.nombre,
               ISNULL(SUM(CM.costo_total), 0),
               COUNT(CM.id_compra)
        FROM Proveedor P
        LEFT JOIN Compra_Material CM ON P.id_proveedor = CM.id_proveedor
        GROUP BY P.id_proveedor, P.nombre;

    CREATE TABLE #ResumenProveedores (
        Proveedor       NVARCHAR(100),
        Num_Compras     INT,
        Total_Invertido DECIMAL(10,2)
    );

    OPEN cur_prov;
    FETCH NEXT FROM cur_prov INTO @id_prov, @nom_prov, @total_comp, @num_comp;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #ResumenProveedores VALUES (@nom_prov, @num_comp, @total_comp);
        FETCH NEXT FROM cur_prov INTO @id_prov, @nom_prov, @total_comp, @num_comp;
    END;

    CLOSE cur_prov;
    DEALLOCATE cur_prov;

    SELECT * FROM #ResumenProveedores ORDER BY Total_Invertido DESC;
    DROP TABLE #ResumenProveedores;
END;
GO

--  7. TRANSACCION - Cancelar pedido y restaurar stock
CREATE OR ALTER PROCEDURE sp_CancelarPedido
    @id_pedido INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Verificar que el pedido existe y no esta entregado
        IF NOT EXISTS (SELECT 1 FROM Pedido WHERE id_pedido = @id_pedido)
            THROW 50005, 'El pedido no existe.', 1;

        IF EXISTS (SELECT 1 FROM Pedido WHERE id_pedido = @id_pedido AND estado = 'Entregado')
            THROW 50006, 'No se puede cancelar un pedido ya entregado.', 1;

        -- Restaurar stock de cada producto del pedido
        UPDATE PR
        SET PR.stock = PR.stock + DP.cantidad
        FROM Producto PR
        JOIN Detalle_Pedido DP ON PR.id_producto = DP.id_producto
        WHERE DP.id_pedido = @id_pedido;

        -- Cambiar estado a Cancelado
        UPDATE Pedido SET estado = 'Cancelado' WHERE id_pedido = @id_pedido;

        COMMIT TRANSACTION;
        PRINT 'Pedido ' + CAST(@id_pedido AS NVARCHAR) + ' cancelado. Stock restaurado.';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        PRINT 'ERROR: ' + ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

--  8. ROLES Y SEGURIDAD

-- Crear roles
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_administrador')
    CREATE ROLE rol_administrador;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_operador')
    CREATE ROLE rol_operador;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_analista')
    CREATE ROLE rol_analista;
GO

-- Permisos Administrador: acceso total
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO rol_administrador;
GO

-- Permisos Operador: registrar operaciones (sin DELETE, sin Reporte)
GRANT SELECT, INSERT, UPDATE ON Cliente         TO rol_operador;
GRANT SELECT, INSERT, UPDATE ON Producto        TO rol_operador;
GRANT SELECT, INSERT, UPDATE ON Pedido          TO rol_operador;
GRANT SELECT, INSERT         ON Detalle_Pedido  TO rol_operador;
GRANT SELECT, INSERT         ON Pago            TO rol_operador;
GRANT SELECT, INSERT         ON Compra_Material TO rol_operador;
GRANT SELECT, INSERT         ON Proveedor       TO rol_operador;
GRANT EXECUTE ON sp_RegistrarPedido    TO rol_operador;
GRANT EXECUTE ON sp_ActualizarEstadoPedido TO rol_operador;
GRANT EXECUTE ON sp_RegistrarCompra    TO rol_operador;
GO

-- Permisos Analista: solo lectura y reportes
GRANT SELECT ON Cliente        TO rol_analista;
GRANT SELECT ON Producto       TO rol_analista;
GRANT SELECT ON Pedido         TO rol_analista;
GRANT SELECT ON Detalle_Pedido TO rol_analista;
GRANT SELECT ON Pago           TO rol_analista;
GRANT SELECT ON Compra_Material TO rol_analista;
GRANT SELECT ON Reporte        TO rol_analista;
GRANT EXECUTE ON sp_GenerarReporteMensual TO rol_analista;
GRANT EXECUTE ON sp_AlertaStockBajo       TO rol_analista;
GO

-- ============================================================
--  9. DATOS INICIALES DE PRUEBA
-- ============================================================

INSERT INTO Cliente (nombre, telefono, direccion, email) VALUES
('Maria Torres',   '987654321', 'Av. Lima 123',      'maria@gmail.com'),
('Lucia Ramirez',  '912345678', 'Jr. Cusco 456',     'lucia@gmail.com'),
('Carmen Flores',  '965432100', 'Calle Ica 789',     'carmen@gmail.com'),
('Rosa Vargas',    '971234567', 'Av. Arequipa 321',  'rosa@gmail.com'),
('Ana Gutierrez',  '983210987', 'Jr. Moquegua 55',   'ana@gmail.com'),
('Patricia Rios',  '976543210', 'Av. Brasil 200',    'patricia@gmail.com'),
('Sandra Medina',  '954321098', 'Calle Junin 88',    'sandra@gmail.com'),
('Beatriz Chavez', '943210987', 'Av. Tacna 300',     'beatriz@gmail.com');
GO

INSERT INTO Producto (nombre, talla, precio, material, stock) VALUES
('Sandalia clasica cuero',   35,  85.00, 'Cuero', 12),
('Balerina elegante cuero',  36,  95.00, 'Cuero', 10),
('Mocasin confort cuero',    37, 110.00, 'Cuero',  8),
('Zapato formal dama',       38, 130.00, 'Cuero',  7),
('Bota corta cuero',         39, 160.00, 'Cuero',  5),
('Sandalia tira cuero',      35,  90.00, 'Cuero',  9),
('Zapato casual cuero',      36, 105.00, 'Cuero',  6),
('Mocasin con hebilla',      37, 120.00, 'Cuero',  4);
GO

INSERT INTO Proveedor (nombre, tipo, telefono) VALUES
('Fabrica Piel Peru',    'Fabrica',  '01-3456789'),
('Distribuidora Cuero',  'Material', '01-9876543'),
('Acabados Lima SAC',    'Material', '01-1234567');
GO

INSERT INTO Pedido (id_cliente, fecha_pedido, estado) VALUES
(1, '2025-01-05', 'Entregado'),
(2, '2025-01-12', 'Entregado'),
(3, '2025-02-03', 'Entregado'),
(4, '2025-02-18', 'Entregado'),
(5, '2025-03-01', 'Entregado'),
(6, '2025-03-15', 'Entregado'),
(7, '2025-04-02', 'En produccion'),
(8, '2025-04-10', 'Pendiente'),
(1, '2025-04-15', 'Entregado'),
(2, '2025-05-02', 'Entregado');
GO

INSERT INTO Detalle_Pedido (id_pedido, id_producto, cantidad, precio_unitario) VALUES
(1, 1, 2,  85.00),
(1, 3, 1, 110.00),
(2, 2, 1,  95.00),
(3, 4, 2, 130.00),
(4, 5, 1, 160.00),
(5, 6, 3,  90.00),
(6, 7, 2, 105.00),
(7, 8, 1, 120.00),
(8, 4, 1, 130.00),
(9, 2, 2,  95.00),
(10,1, 1,  85.00),
(10,3, 1, 110.00);
GO

INSERT INTO Pago (id_pedido, metodo, monto, fecha_pago) VALUES
(1,  'Yape',          280.00, '2025-01-05'),
(2,  'Efectivo',       95.00, '2025-01-12'),
(3,  'Transferencia', 260.00, '2025-02-03'),
(4,  'Yape',          160.00, '2025-02-18'),
(5,  'Plin',          270.00, '2025-03-01'),
(6,  'Efectivo',      210.00, '2025-03-15'),
(9,  'Yape',          190.00, '2025-04-15'),
(10, 'Transferencia', 195.00, '2025-05-02');
GO

INSERT INTO Compra_Material (id_proveedor, fecha_compra, costo_total, descripcion) VALUES
(2, '2025-01-02', 350.00, 'Cuero vacuno negro y marron'),
(1, '2025-01-28', 600.00, 'Docena sandalia clasica sin terminar'),
(2, '2025-02-10', 280.00, 'Cuero color camel y beige'),
(3, '2025-02-20', 150.00, 'Pegamento industrial y plantillas'),
(1, '2025-03-05', 420.00, '6 pares zapato formal en crudo'),
(2, '2025-03-25', 200.00, 'Cuero charol negro'),
(3, '2025-04-01', 180.00, 'Hebillas y accesorios decorativos'),
(1, '2025-04-20', 500.00, 'Bota corta sin terminar x5 pares');
GO

--  10. CONSULTAS UTILES (REPORTES)
-- 

-- R1: Total de ventas por mes
SELECT FORMAT(P.fecha_pedido, 'yyyy-MM')  AS mes,
       COUNT(DISTINCT P.id_pedido)          AS total_pedidos,
       SUM(PA.monto)                        AS total_cobrado
FROM Pedido P
JOIN Pago PA ON P.id_pedido = PA.id_pedido
WHERE P.estado = 'Entregado'
GROUP BY FORMAT(P.fecha_pedido, 'yyyy-MM')
ORDER BY mes;
GO

-- R2: Productos mas vendidos
SELECT PR.nombre, PR.talla,
       SUM(DP.cantidad) AS unidades_vendidas,
       SUM(DP.cantidad * DP.precio_unitario) AS total_generado
FROM Detalle_Pedido DP
JOIN Producto PR ON DP.id_producto = PR.id_producto
JOIN Pedido PE ON DP.id_pedido = PE.id_pedido
WHERE PE.estado = 'Entregado'
GROUP BY PR.nombre, PR.talla
ORDER BY unidades_vendidas DESC;
GO

-- R3: Ingresos por metodo de pago
SELECT metodo,
       COUNT(*)    AS transacciones,
       SUM(monto)  AS total_recaudado
FROM Pago
GROUP BY metodo
ORDER BY total_recaudado DESC;
GO

-- R4: Rentabilidad mensual (ventas vs compras)
SELECT mes,
       ventas,
       compras,
       (ventas - compras) AS ganancia_neta
FROM (
    SELECT FORMAT(P.fecha_pedido,'yyyy-MM') AS mes,
           SUM(PA.monto) AS ventas
    FROM Pedido P JOIN Pago PA ON P.id_pedido = PA.id_pedido
    WHERE P.estado = 'Entregado'
    GROUP BY FORMAT(P.fecha_pedido,'yyyy-MM')
) V
JOIN (
    SELECT FORMAT(fecha_compra,'yyyy-MM') AS mes,
           SUM(costo_total) AS compras
    FROM Compra_Material
    GROUP BY FORMAT(fecha_compra,'yyyy-MM')
) C ON V.mes = C.mes
ORDER BY mes;
GO

-- R5: Estado actual de pedidos
SELECT P.id_pedido, C.nombre AS cliente,
       P.fecha_pedido, P.estado,
       dbo.fn_TotalPedido(P.id_pedido) AS total_pedido
FROM Pedido P
JOIN Cliente C ON P.id_cliente = C.id_cliente
ORDER BY P.fecha_pedido DESC;
GO

-- Ejecutar procedimientos de prueba
EXEC sp_GenerarReporteMensual '2025-01';
EXEC sp_GenerarReporteMensual '2025-02';
EXEC sp_GenerarReporteMensual '2025-03';
EXEC sp_AlertaStockBajo 5;
EXEC sp_ResumenProveedores;

SELECT dbo.fn_MetodoPagoMasUsado() AS metodo_preferido;
GO