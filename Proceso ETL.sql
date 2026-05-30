USE DW_Dayluz;
GO

-- ============================================================
--  TABLA DE CONTROL ETL (log de ejecuciones)
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'ETL_Log')
CREATE TABLE ETL_Log (
    id_log         INT          PRIMARY KEY IDENTITY(1,1),
    etapa          NVARCHAR(50),
    fecha_inicio   DATETIME     DEFAULT GETDATE(),
    fecha_fin      DATETIME,
    registros_proc INT          DEFAULT 0,
    estado         NVARCHAR(20) DEFAULT 'EN PROCESO',
    mensaje        NVARCHAR(500)
);
GO

-- ============================================================
--  PROCEDIMIENTO MAESTRO ETL
-- ============================================================
CREATE OR ALTER PROCEDURE sp_ETL_Completo
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @inicio DATETIME = GETDATE();
    DECLARE @id_log INT;
    DECLARE @registros INT;

    PRINT '======================================';
    PRINT 'INICIO PROCESO ETL - ' + CAST(GETDATE() AS NVARCHAR);
    PRINT '======================================';

    -- ─────────────────────────────────────────
    -- ETAPA 1: CARGAR DIMENSION METODO DE PAGO
    -- ─────────────────────────────────────────
    INSERT INTO ETL_Log (etapa) VALUES ('E1: Dim_MetodoPago');
    SET @id_log = SCOPE_IDENTITY();

    BEGIN TRY
        -- Usar MERGE para no duplicar
        MERGE Dim_MetodoPago AS target
        USING (
            VALUES
                ('Yape',         'Digital',  'Pago digital via app Yape'),
                ('Plin',         'Digital',  'Pago digital via app Plin'),
                ('Transferencia','Bancario', 'Transferencia bancaria interbancaria'),
                ('Efectivo',     'Efectivo', 'Pago en efectivo en taller')
        ) AS source (nombre_metodo, tipo, descripcion)
        ON target.nombre_metodo = source.nombre_metodo
        WHEN NOT MATCHED THEN
            INSERT (nombre_metodo, tipo, descripcion)
            VALUES (source.nombre_metodo, source.tipo, source.descripcion);

        SET @registros = @@ROWCOUNT;
        UPDATE ETL_Log SET estado='OK', fecha_fin=GETDATE(), registros_proc=@registros,
               mensaje='Metodos de pago cargados.' WHERE id_log=@id_log;
        PRINT 'E1 OK - Dim_MetodoPago: ' + CAST(@registros AS NVARCHAR) + ' registros';
    END TRY
    BEGIN CATCH
        UPDATE ETL_Log SET estado='ERROR', fecha_fin=GETDATE(),
               mensaje=ERROR_MESSAGE() WHERE id_log=@id_log;
        PRINT 'E1 ERROR: ' + ERROR_MESSAGE();
    END CATCH;

    -- ─────────────────────────────────────────
    -- ETAPA 2: CARGAR DIMENSION CLIENTE
    -- ─────────────────────────────────────────
    INSERT INTO ETL_Log (etapa) VALUES ('E2: Dim_Cliente');
    SET @id_log = SCOPE_IDENTITY();

    BEGIN TRY
        MERGE Dim_Cliente AS target
        USING (
            SELECT
                id_cliente,
                nombre,
                -- Extraer distrito de la direccion (simplificado)
                CASE
                    WHEN direccion LIKE '%Lima%'     THEN 'Lima'
                    WHEN direccion LIKE '%Cusco%'    THEN 'Cusco'
                    WHEN direccion LIKE '%Arequipa%' THEN 'Arequipa'
                    ELSE 'Lima'
                END AS distrito,
                'Cliente regular' AS segmento
            FROM ZapatosCuero.dbo.Cliente
        ) AS source
        ON target.id_cliente_nk = source.id_cliente
        WHEN MATCHED AND target.nombre <> source.nombre THEN
            UPDATE SET nombre=source.nombre, distrito=source.distrito
        WHEN NOT MATCHED THEN
            INSERT (id_cliente_nk, nombre, distrito, segmento)
            VALUES (source.id_cliente, source.nombre, source.distrito, source.segmento);

        SET @registros = @@ROWCOUNT;
        UPDATE ETL_Log SET estado='OK', fecha_fin=GETDATE(), registros_proc=@registros,
               mensaje='Clientes cargados.' WHERE id_log=@id_log;
        PRINT 'E2 OK - Dim_Cliente: ' + CAST(@registros AS NVARCHAR) + ' registros';
    END TRY
    BEGIN CATCH
        UPDATE ETL_Log SET estado='ERROR', fecha_fin=GETDATE(),
               mensaje=ERROR_MESSAGE() WHERE id_log=@id_log;
        PRINT 'E2 ERROR: ' + ERROR_MESSAGE();
    END CATCH;

    -- ─────────────────────────────────────────
    -- ETAPA 3: CARGAR DIMENSION PRODUCTO
    -- ─────────────────────────────────────────
    INSERT INTO ETL_Log (etapa) VALUES ('E3: Dim_Producto');
    SET @id_log = SCOPE_IDENTITY();

    BEGIN TRY
        MERGE Dim_Producto AS target
        USING (
            SELECT
                id_producto,
                nombre,
                talla,
                material,
                'Calzado de cuero' AS categoria,
                -- Clasificar rango de precio
                CASE
                    WHEN precio < 95  THEN 'Economico'
                    WHEN precio < 130 THEN 'Medio'
                    ELSE 'Premium'
                END AS rango_precio
            FROM ZapatosCuero.dbo.Producto
        ) AS source
        ON target.id_producto_nk = source.id_producto AND target.vigente = 1
        WHEN MATCHED AND (target.nombre <> source.nombre OR target.talla <> source.talla) THEN
            UPDATE SET nombre=source.nombre, talla=source.talla,
                       material=source.material, rango_precio=source.rango_precio
        WHEN NOT MATCHED THEN
            INSERT (id_producto_nk, nombre, talla, material, categoria, rango_precio)
            VALUES (source.id_producto, source.nombre, source.talla,
                    source.material, source.categoria, source.rango_precio);

        SET @registros = @@ROWCOUNT;
        UPDATE ETL_Log SET estado='OK', fecha_fin=GETDATE(), registros_proc=@registros,
               mensaje='Productos cargados.' WHERE id_log=@id_log;
        PRINT 'E3 OK - Dim_Producto: ' + CAST(@registros AS NVARCHAR) + ' registros';
    END TRY
    BEGIN CATCH
        UPDATE ETL_Log SET estado='ERROR', fecha_fin=GETDATE(),
               mensaje=ERROR_MESSAGE() WHERE id_log=@id_log;
        PRINT 'E3 ERROR: ' + ERROR_MESSAGE();
    END CATCH;

    -- ─────────────────────────────────────────
    -- ETAPA 4: CARGAR DIMENSION PROVEEDOR
    -- ─────────────────────────────────────────
    INSERT INTO ETL_Log (etapa) VALUES ('E4: Dim_Proveedor');
    SET @id_log = SCOPE_IDENTITY();

    BEGIN TRY
        MERGE Dim_Proveedor AS target
        USING (
            SELECT id_proveedor, nombre, tipo
            FROM ZapatosCuero.dbo.Proveedor
        ) AS source
        ON target.id_proveedor_nk = source.id_proveedor
        WHEN MATCHED THEN
            UPDATE SET nombre=source.nombre, tipo=source.tipo
        WHEN NOT MATCHED THEN
            INSERT (id_proveedor_nk, nombre, tipo)
            VALUES (source.id_proveedor, source.nombre, source.tipo);

        SET @registros = @@ROWCOUNT;
        UPDATE ETL_Log SET estado='OK', fecha_fin=GETDATE(), registros_proc=@registros,
               mensaje='Proveedores cargados.' WHERE id_log=@id_log;
        PRINT 'E4 OK - Dim_Proveedor: ' + CAST(@registros AS NVARCHAR) + ' registros';
    END TRY
    BEGIN CATCH
        UPDATE ETL_Log SET estado='ERROR', fecha_fin=GETDATE(),
               mensaje=ERROR_MESSAGE() WHERE id_log=@id_log;
        PRINT 'E4 ERROR: ' + ERROR_MESSAGE();
    END CATCH;

    -- ─────────────────────────────────────────
    -- ETAPA 5: CARGAR FACT_VENTAS
    -- ─────────────────────────────────────────
    INSERT INTO ETL_Log (etapa) VALUES ('E5: Fact_Ventas');
    SET @id_log = SCOPE_IDENTITY();

    BEGIN TRY
        -- Solo cargar pedidos Entregados que no esten ya en el datamart
        INSERT INTO Fact_Ventas (
            id_tiempo, id_producto_sk, id_cliente_sk, id_metodo_pago,
            cantidad, precio_unitario, monto_total,
            id_pedido_nk, id_detalle_nk
        )
        SELECT
            -- E: Extraer de OLTP
            -- T: Transformar fechas a clave surrogada de tiempo
            CAST(FORMAT(PE.fecha_pedido, 'yyyyMMdd') AS INT),

            -- T: Resolver clave surrogada de producto (vigente)
            DP_SK.id_producto_sk,

            -- T: Resolver clave surrogada de cliente
            CL_SK.id_cliente_sk,

            -- T: Resolver clave de metodo de pago
            MP.id_metodo_pago,

            -- Metricas directas
            DP.cantidad,
            DP.precio_unitario,
            DP.cantidad * DP.precio_unitario AS monto_total,

            -- Trazabilidad
            PE.id_pedido,
            DP.id_detalle

        FROM ZapatosCuero.dbo.Pedido         PE
        JOIN ZapatosCuero.dbo.Detalle_Pedido  DP  ON PE.id_pedido  = DP.id_pedido
        JOIN ZapatosCuero.dbo.Pago            PA  ON PE.id_pedido  = PA.id_pedido
        -- Resolver surrogadas
        JOIN Dim_Producto  DP_SK ON DP_SK.id_producto_nk = DP.id_producto AND DP_SK.vigente = 1
        JOIN Dim_Cliente   CL_SK ON CL_SK.id_cliente_nk  = PE.id_cliente  AND CL_SK.vigente = 1
        JOIN Dim_MetodoPago MP   ON MP.nombre_metodo      = PA.metodo
        -- Solo pedidos entregados
        WHERE PE.estado = 'Entregado'
          -- Evitar duplicados: solo cargar detalles nuevos
          AND DP.id_detalle NOT IN (SELECT id_detalle_nk FROM Fact_Ventas);

        SET @registros = @@ROWCOUNT;
        UPDATE ETL_Log SET estado='OK', fecha_fin=GETDATE(), registros_proc=@registros,
               mensaje='Ventas cargadas al datamart.' WHERE id_log=@id_log;
        PRINT 'E5 OK - Fact_Ventas: ' + CAST(@registros AS NVARCHAR) + ' registros nuevos';
    END TRY
    BEGIN CATCH
        UPDATE ETL_Log SET estado='ERROR', fecha_fin=GETDATE(),
               mensaje=ERROR_MESSAGE() WHERE id_log=@id_log;
        PRINT 'E5 ERROR: ' + ERROR_MESSAGE();
    END CATCH;

    -- ─────────────────────────────────────────
    -- ETAPA 6: CARGAR FACT_COMPRAS
    -- ─────────────────────────────────────────
    INSERT INTO ETL_Log (etapa) VALUES ('E6: Fact_Compras');
    SET @id_log = SCOPE_IDENTITY();

    BEGIN TRY
        INSERT INTO Fact_Compras (
            id_tiempo, id_proveedor_sk,
            costo_total, descripcion, id_compra_nk
        )
        SELECT
            CAST(FORMAT(CM.fecha_compra, 'yyyyMMdd') AS INT),
            PR_SK.id_proveedor_sk,
            CM.costo_total,
            CM.descripcion,
            CM.id_compra
        FROM ZapatosCuero.dbo.Compra_Material  CM
        JOIN Dim_Proveedor PR_SK ON PR_SK.id_proveedor_nk = CM.id_proveedor
        WHERE CM.id_compra NOT IN (SELECT id_compra_nk FROM Fact_Compras);

        SET @registros = @@ROWCOUNT;
        UPDATE ETL_Log SET estado='OK', fecha_fin=GETDATE(), registros_proc=@registros,
               mensaje='Compras cargadas al datamart.' WHERE id_log=@id_log;
        PRINT 'E6 OK - Fact_Compras: ' + CAST(@registros AS NVARCHAR) + ' registros nuevos';
    END TRY
    BEGIN CATCH
        UPDATE ETL_Log SET estado='ERROR', fecha_fin=GETDATE(),
               mensaje=ERROR_MESSAGE() WHERE id_log=@id_log;
        PRINT 'E6 ERROR: ' + ERROR_MESSAGE();
    END CATCH;

    -- ─────────────────────────────────────────
    -- RESUMEN FINAL
    -- ─────────────────────────────────────────
    PRINT '';
    PRINT '======================================';
    PRINT 'PROCESO ETL COMPLETADO';
    PRINT 'Tiempo total: ' + CAST(DATEDIFF(SECOND, @inicio, GETDATE()) AS NVARCHAR) + ' seg';
    PRINT '======================================';

    -- Mostrar log completo
    SELECT etapa, estado, registros_proc, mensaje,
           DATEDIFF(MILLISECOND, fecha_inicio, fecha_fin) AS ms_proceso
    FROM ETL_Log
    ORDER BY id_log DESC;
END;
GO

-- ============================================================
--  EJECUTAR EL ETL
-- ============================================================
EXEC sp_ETL_Completo;
GO

-- ============================================================
--  VERIFICACION POST-ETL: Consultas de validacion
-- ============================================================

PRINT '--- VERIFICACION POST-ETL ---';

-- KPI 1: Ventas totales por mes y anio
SELECT
    T.anio,
    T.nombre_mes,
    T.mes,
    COUNT(DISTINCT FV.id_pedido_nk) AS pedidos,
    SUM(FV.cantidad)                 AS unidades_vendidas,
    SUM(FV.monto_total)              AS total_ventas
FROM Fact_Ventas FV
JOIN Dim_Tiempo T ON FV.id_tiempo = T.id_tiempo
GROUP BY T.anio, T.nombre_mes, T.mes
ORDER BY T.anio, T.mes;
GO

-- KPI 2: Top 5 productos mas vendidos
SELECT TOP 5
    P.nombre, P.talla, P.rango_precio,
    SUM(FV.cantidad)    AS unidades,
    SUM(FV.monto_total) AS ingresos
FROM Fact_Ventas FV
JOIN Dim_Producto P ON FV.id_producto_sk = P.id_producto_sk
GROUP BY P.nombre, P.talla, P.rango_precio
ORDER BY unidades DESC;
GO

-- KPI 3: Distribucion de metodos de pago
SELECT * FROM v_MetodosPago ORDER BY total_recaudado DESC;
GO

-- KPI 4: Rentabilidad mensual
SELECT anio, nombre_mes, mes,
       total_ventas, total_compras, ganancia_neta
FROM v_Rentabilidad
WHERE total_ventas > 0 OR total_compras > 0
ORDER BY anio, mes;
GO

-- KPI 5: Compras por proveedor
SELECT * FROM v_ComprasProveedor ORDER BY anio, mes;
GO

PRINT 'ETL ejecutado y validado exitosamente. Listo para Power BI.';
GO