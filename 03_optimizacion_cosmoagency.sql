-- ============================================================
-- COSMOAGENCY — OPTIMIZACIÓN Y MANTENIMIENTO
-- Archivo: 02_optimizacion_cosmoagency.sql
-- SGBD   : SQL Server 2016+
-- ============================================================

USE CosmoAgency;
GO

-- ============================================================
-- SECCIÓN 1: DIAGNÓSTICO INICIAL — identificar problemas reales
-- Ejecutar ANTES de crear cualquier índice
-- ============================================================

-- ------------------------------------------------------------
-- 1A. Tablas sin índices no agrupados (solo tienen PK/clustered)
--     Estas son candidatas inmediatas a optimización
-- ------------------------------------------------------------
SELECT
    t.name                          AS tabla,
    p.rows                          AS filas_estimadas,
    SUM(a.total_pages) * 8 / 1024  AS tamano_MB
FROM sys.tables t
JOIN sys.indexes      i ON t.object_id = i.object_id AND i.type IN (0,1)
JOIN sys.partitions   p ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units a ON p.partition_id = a.container_id
GROUP BY t.name, p.rows
ORDER BY p.rows DESC;
GO

-- ------------------------------------------------------------
-- 1B. Índices existentes y su tasa de uso
--     Si seeks=0 y scans altos → tabla hace full scan siempre
-- ------------------------------------------------------------
SELECT
    OBJECT_NAME(s.object_id)    AS tabla,
    i.name                      AS indice,
    i.type_desc                 AS tipo,
    s.user_seeks                AS busquedas,
    s.user_scans                AS escaneos,
    s.user_lookups              AS lookups,
    s.user_updates              AS actualizaciones,
    s.last_user_seek            AS ultimo_seek
FROM sys.dm_db_index_usage_stats s
JOIN sys.indexes i
    ON s.object_id = i.object_id
    AND s.index_id = i.index_id
WHERE s.database_id = DB_ID('CosmoAgency')
ORDER BY s.user_seeks DESC, s.user_scans DESC;
GO

-- ------------------------------------------------------------
-- 1C. Índices fragmentados (fragmentación > 30% = reconstruir,
--     entre 10-30% = reorganizar)
-- ------------------------------------------------------------
SELECT
    OBJECT_NAME(ips.object_id)          AS tabla,
    i.name                              AS indice,
    ips.index_type_desc                 AS tipo,
    ROUND(ips.avg_fragmentation_in_percent, 2) AS fragmentacion_pct,
    ips.page_count                      AS paginas,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'RECONSTRUIR'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZAR'
        ELSE 'OK'
    END AS accion_recomendada
FROM sys.dm_db_index_physical_stats(
        DB_ID('CosmoAgency'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id
    AND ips.index_id = i.index_id
WHERE ips.page_count > 10   -- ignorar índices triviales
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

-- ------------------------------------------------------------
-- 1D. Consultas más costosas actualmente en caché
--     (top 10 por CPU acumulado)
-- ------------------------------------------------------------
SELECT TOP 10
    qs.execution_count                              AS ejecuciones,
    qs.total_worker_time / 1000                     AS cpu_ms_total,
    qs.total_worker_time / qs.execution_count / 1000 AS cpu_ms_promedio,
    qs.total_logical_reads / qs.execution_count     AS lecturas_promedio,
    qs.total_elapsed_time / qs.execution_count / 1000 AS duracion_ms_prom,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset)/2)+1)   AS consulta_sql
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.dbid = DB_ID('CosmoAgency')
ORDER BY qs.total_worker_time DESC;
GO

-- ------------------------------------------------------------
-- 1E. Índices faltantes sugeridos por el motor de SQL Server
--     El optimizador detecta los column lookups más frecuentes
-- ------------------------------------------------------------
SELECT TOP 15
    DB_NAME(mid.database_id)            AS base_datos,
    OBJECT_NAME(mid.object_id)          AS tabla,
    migs.avg_user_impact                AS mejora_pct_estimada,
    migs.user_seeks + migs.user_scans   AS uso_estimado,
    mid.equality_columns                AS columnas_igualdad,
    mid.inequality_columns              AS columnas_rango,
    mid.included_columns                AS columnas_include,
    'CREATE INDEX IX_' +
        OBJECT_NAME(mid.object_id) + '_sugerido' +
        ' ON ' + mid.statement +
        ' (' + ISNULL(mid.equality_columns,'') +
        CASE WHEN mid.inequality_columns IS NOT NULL
             THEN ',' + mid.inequality_columns ELSE '' END + ')' +
        CASE WHEN mid.included_columns IS NOT NULL
             THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END
    AS script_sugerido
FROM sys.dm_db_missing_index_details   mid
JOIN sys.dm_db_missing_index_groups    mig  ON mid.index_handle  = mig.index_handle
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
WHERE mid.database_id = DB_ID('CosmoAgency')
ORDER BY migs.avg_user_impact DESC;
GO

-- ------------------------------------------------------------
-- 1F. Estadísticas desactualizadas
--     Si rows_sampled << rows → el optimizador toma malas decisiones
-- ------------------------------------------------------------
SELECT
    OBJECT_NAME(s.object_id)    AS tabla,
    s.name                      AS estadistica,
    sp.last_updated             AS ultima_actualizacion,
    sp.rows                     AS filas_totales,
    sp.rows_sampled             AS filas_muestreadas,
    ROUND(100.0 * sp.rows_sampled / NULLIF(sp.rows,0), 1) AS pct_muestra,
    sp.modification_counter     AS modificaciones_desde_update
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) IN (
    'Expediente','Declaracion','ItemDeclaracion',
    'Factura','Pago','LiquidacionTributo',
    'HitoTrazabilidad','DocumentoSoporte','Clientes'
)
ORDER BY sp.modification_counter DESC;
GO




-- ============================================================
-- SECCIÓN 2: IMPLEMENTACIÓN DE ÍNDICES
-- Convención de nombres: IX_Tabla_Columnas
-- ONLINE = ON → no bloquea la tabla durante la creación
-- FILLFACTOR = 85 → deja 15% libre para inserciones futuras
-- ============================================================

-- ------------------------------------------------------------
-- TABLA: Expediente
-- Casos de uso: buscar por cliente, filtrar por estado,
--               rango de fechas de apertura
-- ------------------------------------------------------------

-- Búsquedas por cliente (el más frecuente: "¿qué expedientes tiene X cliente?")
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Expediente_IdCliente'
               AND object_id = OBJECT_ID('dbo.Expediente'))
CREATE NONCLUSTERED INDEX IX_Expediente_IdCliente
    ON dbo.Expediente (id_cliente)
    INCLUDE (codigo, estado, fecha_apertura, fecha_cierre)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Filtro por estado (operaciones consulta esto constantemente)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Expediente_Estado'
               AND object_id = OBJECT_ID('dbo.Expediente'))
CREATE NONCLUSTERED INDEX IX_Expediente_Estado
    ON dbo.Expediente (estado)
    INCLUDE (id_cliente, codigo, fecha_apertura)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Rango de fechas (reportes gerenciales por período)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Expediente_FechaApertura'
               AND object_id = OBJECT_ID('dbo.Expediente'))
CREATE NONCLUSTERED INDEX IX_Expediente_FechaApertura
    ON dbo.Expediente (fecha_apertura DESC)
    INCLUDE (id_cliente, estado, codigo)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Índice compuesto: cliente + estado (la consulta más común del ejecutivo)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Expediente_Cliente_Estado'
               AND object_id = OBJECT_ID('dbo.Expediente'))
CREATE NONCLUSTERED INDEX IX_Expediente_Cliente_Estado
    ON dbo.Expediente (id_cliente, estado)
    INCLUDE (codigo, fecha_apertura, fecha_cierre, cod_aduana)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: Declaracion
-- Casos de uso: listar declaraciones de un expediente,
--               filtrar por tipo IMP/EXP, buscar por número
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Declaracion_IdExpediente'
               AND object_id = OBJECT_ID('dbo.Declaracion'))
CREATE NONCLUSTERED INDEX IX_Declaracion_IdExpediente
    ON dbo.Declaracion (id_expediente)
    INCLUDE (numero, tipo, fecha, moneda, valor_aduana)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Búsqueda por número oficial (DUA, DUCA — búsqueda exacta frecuente)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Declaracion_Numero'
               AND object_id = OBJECT_ID('dbo.Declaracion'))
CREATE NONCLUSTERED INDEX IX_Declaracion_Numero
    ON dbo.Declaracion (numero)
    WITH (FILLFACTOR = 90, ONLINE = ON);
GO

-- Filtro por tipo y fecha (reportes de importación vs exportación por mes)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Declaracion_Tipo_Fecha'
               AND object_id = OBJECT_ID('dbo.Declaracion'))
CREATE NONCLUSTERED INDEX IX_Declaracion_Tipo_Fecha
    ON dbo.Declaracion (tipo, fecha DESC)
    INCLUDE (id_expediente, moneda, valor_aduana)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: ItemDeclaracion
-- Casos de uso: ver ítems de una declaración, buscar por HS
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ItemDeclaracion_IdDeclaracion'
               AND object_id = OBJECT_ID('dbo.ItemDeclaracion'))
CREATE NONCLUSTERED INDEX IX_ItemDeclaracion_IdDeclaracion
    ON dbo.ItemDeclaracion (id_declaracion)
    INCLUDE (partida_hs, pais_origen, cantidad, um, valor_fob)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Búsqueda por código HS (clasificación arancelaria)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ItemDeclaracion_PartidaHS'
               AND object_id = OBJECT_ID('dbo.ItemDeclaracion'))
CREATE NONCLUSTERED INDEX IX_ItemDeclaracion_PartidaHS
    ON dbo.ItemDeclaracion (partida_hs)
    INCLUDE (id_declaracion, descripcion, cantidad, valor_fob)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: HitoTrazabilidad
-- Casos de uso: construir línea de tiempo, validar que existe
--               LEVANTE antes de ENTREGA
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_HitoTrazabilidad_IdExpediente'
               AND object_id = OBJECT_ID('dbo.HitoTrazabilidad'))
CREATE NONCLUSTERED INDEX IX_HitoTrazabilidad_IdExpediente
    ON dbo.HitoTrazabilidad (id_expediente, fecha_hora DESC)
    INCLUDE (evento, responsable, observacion)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Filtro por tipo de evento (¿cuántos en AFORO esta semana?)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_HitoTrazabilidad_Evento'
               AND object_id = OBJECT_ID('dbo.HitoTrazabilidad'))
CREATE NONCLUSTERED INDEX IX_HitoTrazabilidad_Evento
    ON dbo.HitoTrazabilidad (evento, fecha_hora DESC)
    INCLUDE (id_expediente, responsable)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: DocumentoSoporte
-- Casos de uso: validar documentos obligatorios antes del aforo
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_DocumentoSoporte_IdExpediente'
               AND object_id = OBJECT_ID('dbo.DocumentoSoporte'))
CREATE NONCLUSTERED INDEX IX_DocumentoSoporte_IdExpediente
    ON dbo.DocumentoSoporte (id_expediente, tipo)
    INCLUDE (numero, emisor, fecha_emision)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: Factura
-- Casos de uso: cartera por cobrar, facturas por cliente,
--               conciliación con pagos
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Factura_IdCliente'
               AND object_id = OBJECT_ID('dbo.Factura'))
CREATE NONCLUSTERED INDEX IX_Factura_IdCliente
    ON dbo.Factura (id_cliente)
    INCLUDE (numero, fecha, estado, total, moneda)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Cartera pendiente (la consulta más crítica de facturación)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Factura_Estado_Fecha'
               AND object_id = OBJECT_ID('dbo.Factura'))
CREATE NONCLUSTERED INDEX IX_Factura_Estado_Fecha
    ON dbo.Factura (estado, fecha DESC)
    INCLUDE (id_cliente, numero, total, moneda)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO

-- Índice filtrado: solo facturas pendientes (subconjunto más consultado)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Factura_Pendientes'
               AND object_id = OBJECT_ID('dbo.Factura'))
CREATE NONCLUSTERED INDEX IX_Factura_Pendientes
    ON dbo.Factura (fecha DESC, id_cliente)
    INCLUDE (numero, total, moneda, id_expediente)
    WHERE estado = 'PENDIENTE'      -- índice filtrado: solo las pendientes
    WITH (FILLFACTOR = 90, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: Pago
-- Casos de uso: conciliación, verificar pagos por factura
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Pago_IdFactura'
               AND object_id = OBJECT_ID('dbo.Pago'))
CREATE NONCLUSTERED INDEX IX_Pago_IdFactura
    ON dbo.Pago (id_factura, fecha DESC)
    INCLUDE (monto, medio, referencia)
    WITH (FILLFACTOR = 85, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: LiquidacionTributo
-- Casos de uso: obtener totales de impuestos por declaración
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_LiquidacionTributo_IdDeclaracion'
               AND object_id = OBJECT_ID('dbo.LiquidacionTributo'))
CREATE NONCLUSTERED INDEX IX_LiquidacionTributo_IdDeclaracion
    ON dbo.LiquidacionTributo (id_declaracion)
    INCLUDE (base_imponible, arancel, iva, otras_tasas, total_tributos)
    WITH (FILLFACTOR = 90, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: AuditoriaCambio
-- Casos de uso: consultas de auditoría por entidad, usuario y fecha
-- ------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_AuditoriaCambio_Entidad_Fecha'
               AND object_id = OBJECT_ID('dbo.AuditoriaCambio'))
CREATE NONCLUSTERED INDEX IX_AuditoriaCambio_Entidad_Fecha
    ON dbo.AuditoriaCambio (entidad, fecha_hora DESC)
    INCLUDE (id_registro, operacion, usuario)
    WITH (FILLFACTOR = 90, ONLINE = ON);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_AuditoriaCambio_Usuario_Fecha'
               AND object_id = OBJECT_ID('dbo.AuditoriaCambio'))
CREATE NONCLUSTERED INDEX IX_AuditoriaCambio_Usuario_Fecha
    ON dbo.AuditoriaCambio (usuario, fecha_hora DESC)
    INCLUDE (entidad, operacion, detalle_json)
    WITH (FILLFACTOR = 90, ONLINE = ON);
GO


-- ------------------------------------------------------------
-- TABLA: Clientes
-- Casos de uso: validar clientes activos, buscar por RUC
-- ------------------------------------------------------------

-- Índice filtrado: solo clientes activos (los únicos que operan)
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Clientes_Activos'
               AND object_id = OBJECT_ID('dbo.Clientes'))
CREATE NONCLUSTERED INDEX IX_Clientes_Activos
    ON dbo.Clientes (activo, nombre_cliente)
    INCLUDE (ruc, email_facturacion, telefono)
    WHERE activo = 1
    WITH (FILLFACTOR = 90, ONLINE = ON);
GO

PRINT '==> Todos los índices creados correctamente.';
GO

-- ============================================================
-- SECCIÓN 3: VISTAS OPTIMIZADAS
-- Las vistas encapsulan las consultas complejas y permiten
-- que el optimizador reutilice planes de ejecución
-- ============================================================

-- ------------------------------------------------------------
-- Vista 1: Estado actual de expedientes (la pantalla principal
--          de operaciones — se consulta decenas de veces al día)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.vw_ExpedientesActivos
AS
SELECT
    e.id_expediente,
    e.codigo,
    e.estado,
    e.fecha_apertura,
    e.fecha_cierre,
    c.nombre_cliente,
    c.ruc,
    -- Último hito registrado
    ht.evento               AS ultimo_evento,
    ht.fecha_hora           AS fecha_ultimo_evento,
    -- Total de documentos cargados
    (SELECT COUNT(*) FROM dbo.DocumentoSoporte ds
     WHERE ds.id_expediente = e.id_expediente) AS total_documentos,
    -- Tiene declaración sí/no
    CASE WHEN EXISTS (
        SELECT 1 FROM dbo.Declaracion d
        WHERE d.id_expediente = e.id_expediente
    ) THEN 1 ELSE 0 END     AS tiene_declaracion
FROM dbo.Expediente e
JOIN dbo.Clientes c ON e.id_cliente = c.id_cliente
OUTER APPLY (
    -- Trae solo el hito más reciente sin subquery correlacionada costosa
    SELECT TOP 1 evento, fecha_hora
    FROM dbo.HitoTrazabilidad
    WHERE id_expediente = e.id_expediente
    ORDER BY fecha_hora DESC
) ht
WHERE e.estado <> 'CERRADO';   -- filtra solo casos activos
GO


-- ------------------------------------------------------------
-- Vista 2: Cartera por cobrar (facturación la consulta a diario)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.vw_CarteraPorCobrar
AS
SELECT
    f.id_factura,
    f.numero                AS numero_factura,
    f.fecha,
    f.total,
    f.moneda,
    c.nombre_cliente,
    c.ruc,
    c.email_facturacion,
    e.codigo                AS expediente,
    -- Días transcurridos desde la emisión
    DATEDIFF(DAY, f.fecha, CAST(GETDATE() AS DATE)) AS dias_pendiente,
    -- Total pagado hasta ahora
    ISNULL((SELECT SUM(p.monto) FROM dbo.Pago p
            WHERE p.id_factura = f.id_factura), 0)  AS monto_pagado,
    -- Saldo pendiente
    f.total - ISNULL((SELECT SUM(p.monto) FROM dbo.Pago p
                      WHERE p.id_factura = f.id_factura), 0) AS saldo_pendiente
FROM dbo.Factura f
JOIN dbo.Clientes   c ON f.id_cliente    = c.id_cliente
LEFT JOIN dbo.Expediente e ON f.id_expediente = e.id_expediente
WHERE f.estado = 'PENDIENTE';
GO


-- ------------------------------------------------------------
-- Vista 3: Línea de tiempo de trazabilidad por expediente
--          (ejecutivos de cuenta la consultan para dar seguimiento)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.vw_TrazabilidadExpediente
AS
SELECT
    e.codigo            AS expediente,
    c.nombre_cliente,
    ht.evento,
    ht.fecha_hora,
    ht.responsable,
    ht.observacion,
    -- SLA: horas entre este hito y el anterior del mismo expediente
    DATEDIFF(HOUR,
        LAG(ht.fecha_hora) OVER (
            PARTITION BY ht.id_expediente
            ORDER BY ht.fecha_hora
        ),
        ht.fecha_hora
    )                   AS horas_desde_hito_anterior,
    -- Alerta si supera 48 horas entre hitos
    CASE
        WHEN DATEDIFF(HOUR,
            LAG(ht.fecha_hora) OVER (
                PARTITION BY ht.id_expediente ORDER BY ht.fecha_hora
            ),
            ht.fecha_hora) > 48
        THEN 'ALERTA SLA'
        ELSE 'OK'
    END                 AS estado_sla
FROM dbo.HitoTrazabilidad ht
JOIN dbo.Expediente e ON ht.id_expediente = e.id_expediente
JOIN dbo.Clientes   c ON e.id_cliente     = c.id_cliente;
GO


-- ------------------------------------------------------------
-- Vista 4: Resumen de liquidaciones por expediente
--          (gerencia y facturación para reportes de tributos)
-- ------------------------------------------------------------
CREATE OR ALTER VIEW dbo.vw_ResumenLiquidaciones
AS
SELECT
    e.codigo                        AS expediente,
    c.nombre_cliente,
    d.numero                        AS declaracion,
    d.tipo,
    d.fecha                         AS fecha_declaracion,
    d.valor_aduana,
    lt.base_imponible,
    lt.arancel,
    lt.iva,
    ISNULL(lt.otras_tasas, 0)       AS otras_tasas,
    lt.total_tributos,
    -- Costo total = valor aduana + tributos
    d.valor_aduana + lt.total_tributos AS costo_total_operacion
FROM dbo.LiquidacionTributo lt
JOIN dbo.Declaracion  d ON lt.id_declaracion = d.id_declaracion
JOIN dbo.Expediente   e ON d.id_expediente   = e.id_expediente
JOIN dbo.Clientes     c ON e.id_cliente      = c.id_cliente;
GO

PRINT '==> Vistas optimizadas creadas.';
GO

-- ============================================================
-- SECCIÓN 4: REVISIÓN Y AJUSTE DE CONFIGURACIONES CRÍTICAS
-- ============================================================

-- ------------------------------------------------------------
-- 4A. Ver configuraciones actuales del servidor
-- ------------------------------------------------------------
SELECT
    name                AS configuracion,
    value               AS valor_actual,
    value_in_use        AS valor_en_uso,
    description
FROM sys.configurations
WHERE name IN (
    'max degree of parallelism',   -- MAXDOP
    'cost threshold for parallelism',
    'max server memory (MB)',
    'min server memory (MB)',
    'optimize for ad hoc workloads',
    'fill factor (%)',
    'recovery interval (min)',
    'remote query timeout (s)'
)
ORDER BY name;
GO

-- ------------------------------------------------------------
-- 4B. Configuraciones recomendadas para CosmoAgency
--
-- MAXDOP: En servidor con ≤8 cores, MAXDOP=4 es un buen balance
-- Cost threshold: subirlo a 50 evita paralelismo en consultas triviales
-- Optimize for ad hoc: ON ahorra memoria de plan cache
-- ------------------------------------------------------------
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

-- Evita que SQL Server use toda la RAM del servidor (deja 2GB para el SO)
-- AJUSTAR según RAM real del servidor; ejemplo para 8GB RAM total:
EXEC sp_configure 'max server memory (MB)', 6144;
RECONFIGURE WITH OVERRIDE;
GO

-- Límite de paralelismo: 4 hilos máximo por consulta
EXEC sp_configure 'max degree of parallelism', 4;
RECONFIGURE WITH OVERRIDE;
GO

-- Umbral de costo para paralelismo: solo usa paralelo si cuesta > 50
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE WITH OVERRIDE;
GO

-- Optimizar para cargas ad hoc: guarda solo el stub del plan la 1ra vez
EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- Volver a ocultar opciones avanzadas
EXEC sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

-- ------------------------------------------------------------
-- 4C. Verificar el modo de recuperación de la base de datos
--     Para entorno de producción debe ser FULL
-- ------------------------------------------------------------
SELECT
    name,
    recovery_model_desc,
    log_reuse_wait_desc,
    state_desc
FROM sys.databases
WHERE name = 'CosmoAgency';
GO

-- Configurar modo FULL si no lo está
ALTER DATABASE CosmoAgency SET RECOVERY FULL;
GO

-- ------------------------------------------------------------
-- 4D. Verificar AUTO_CLOSE y AUTO_SHRINK (deben estar OFF)
--     AUTO_CLOSE: cierra la BD cuando no hay conexiones → latencia
--     AUTO_SHRINK: fragmenta índices automáticamente → malo
-- ------------------------------------------------------------
ALTER DATABASE CosmoAgency SET AUTO_CLOSE  OFF;
ALTER DATABASE CosmoAgency SET AUTO_SHRINK OFF;
GO

-- Verificar configuración final de la BD
SELECT
    name,
    recovery_model_desc,
    is_auto_close_on,
    is_auto_shrink_on,
    is_auto_update_stats_on,
    is_auto_create_stats_on,
    compatibility_level
FROM sys.databases
WHERE name = 'CosmoAgency';
GO

PRINT '==> Configuraciones críticas revisadas y ajustadas.';
GO

-- ============================================================
-- SECCIÓN 5: MANTENIMIENTO PREVENTIVO
-- Stored procedures reutilizables para tareas de mantenimiento
-- ============================================================

-- ------------------------------------------------------------
-- SP 1: Mantenimiento inteligente de índices
--       Decide automáticamente REBUILD vs REORGANIZE vs SKIP
--       según el porcentaje de fragmentación real
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_MantenimientoIndices
    @umbral_reorganize  FLOAT = 10.0,   -- % mínimo para reorganizar
    @umbral_rebuild     FLOAT = 30.0,   -- % mínimo para reconstruir
    @min_paginas        INT   = 100,    -- ignorar índices pequeños
    @solo_reporte       BIT   = 0       -- 1=solo muestra, 0=ejecuta
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @tabla      NVARCHAR(256),
        @indice     NVARCHAR(256),
        @frag       FLOAT,
        @paginas    BIGINT,
        @sql        NVARCHAR(MAX),
        @accion     VARCHAR(20);

    -- Tabla temporal para el reporte
    CREATE TABLE #reporte_indices (
        tabla       NVARCHAR(256),
        indice      NVARCHAR(256),
        fragmentacion FLOAT,
        paginas     BIGINT,
        accion      VARCHAR(20),
        ejecutado   BIT DEFAULT 0,
        ts          DATETIME DEFAULT GETDATE()
    );

    DECLARE cur_indices CURSOR FAST_FORWARD FOR
        SELECT
            OBJECT_NAME(ips.object_id),
            i.name,
            ips.avg_fragmentation_in_percent,
            ips.page_count
        FROM sys.dm_db_index_physical_stats(
            DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        JOIN sys.indexes i
            ON ips.object_id = i.object_id
            AND ips.index_id = i.index_id
        WHERE ips.index_id > 0          -- excluye heaps
          AND ips.page_count >= @min_paginas
          AND i.name IS NOT NULL
        ORDER BY ips.avg_fragmentation_in_percent DESC;

    OPEN cur_indices;
    FETCH NEXT FROM cur_indices INTO @tabla, @indice, @frag, @paginas;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @frag >= @umbral_rebuild
        BEGIN
            SET @accion = 'REBUILD';
            SET @sql = 'ALTER INDEX [' + @indice + '] ON dbo.[' + @tabla + '] REBUILD WITH (ONLINE = ON, FILLFACTOR = 85)';
        END
        ELSE IF @frag >= @umbral_reorganize
        BEGIN
            SET @accion = 'REORGANIZE';
            SET @sql = 'ALTER INDEX [' + @indice + '] ON dbo.[' + @tabla + '] REORGANIZE';
        END
        ELSE
        BEGIN
            SET @accion = 'OK';
            SET @sql = NULL;
        END

        INSERT INTO #reporte_indices (tabla, indice, fragmentacion, paginas, accion, ejecutado)
        VALUES (@tabla, @indice, @frag, @paginas, @accion, 0);

        -- Ejecutar solo si no es modo reporte y hay acción
        IF @solo_reporte = 0 AND @sql IS NOT NULL
        BEGIN
            BEGIN TRY
                EXEC sp_executesql @sql;
                UPDATE #reporte_indices
                SET ejecutado = 1
                WHERE tabla = @tabla AND indice = @indice;
            END TRY
            BEGIN CATCH
                PRINT 'Error en: ' + @tabla + '.' + @indice + ' — ' + ERROR_MESSAGE();
            END CATCH
        END

        FETCH NEXT FROM cur_indices INTO @tabla, @indice, @frag, @paginas;
    END

    CLOSE cur_indices;
    DEALLOCATE cur_indices;

    -- Mostrar reporte final
    SELECT
        tabla, indice,
        ROUND(fragmentacion, 2) AS fragmentacion_pct,
        paginas, accion, ejecutado, ts
    FROM #reporte_indices
    ORDER BY fragmentacion DESC;

    DROP TABLE #reporte_indices;

    PRINT '==> Mantenimiento de índices completado: ' + CONVERT(VARCHAR, GETDATE(), 120);
END;
GO


-- ------------------------------------------------------------
-- SP 2: Actualización de estadísticas
--       Actualiza con FULLSCAN las tablas con más modificaciones
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarEstadisticas
    @umbral_modificaciones INT = 1000   -- actualizar si tuvo más de N cambios
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @tabla  NVARCHAR(256);
    DECLARE @sql    NVARCHAR(MAX);
    DECLARE @total  INT = 0;

    DECLARE cur_stats CURSOR FAST_FORWARD FOR
        SELECT DISTINCT OBJECT_NAME(s.object_id)
        FROM sys.stats s
        CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
        WHERE OBJECT_NAME(s.object_id) IS NOT NULL
          AND sp.modification_counter  >= @umbral_modificaciones
          AND OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1;

    OPEN cur_stats;
    FETCH NEXT FROM cur_stats INTO @tabla;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = 'UPDATE STATISTICS dbo.[' + @tabla + '] WITH FULLSCAN';
        BEGIN TRY
            EXEC sp_executesql @sql;
            PRINT 'Estadísticas actualizadas: ' + @tabla;
            SET @total = @total + 1;
        END TRY
        BEGIN CATCH
            PRINT 'Error actualizando ' + @tabla + ': ' + ERROR_MESSAGE();
        END CATCH

        FETCH NEXT FROM cur_stats INTO @tabla;
    END

    CLOSE cur_stats;
    DEALLOCATE cur_stats;

    PRINT '==> Total tablas actualizadas: ' + CAST(@total AS VARCHAR(10));
END;
GO


-- ------------------------------------------------------------
-- SP 3: Limpieza de auditoría antigua
--       Mantiene la tabla AuditoriaCambio manejable en tamaño.
--       Archiva registros viejos antes de purgarlos.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_LimpiezaAuditoria
    @dias_retener   INT = 365   -- mantener 1 año de auditoría
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @fecha_corte    DATETIME = DATEADD(DAY, -@dias_retener, GETDATE()),
        @registros_del  INT;

    -- Crear tabla de archivo si no existe
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AuditoriaCambio_Archivo')
    BEGIN
        SELECT * INTO dbo.AuditoriaCambio_Archivo
        FROM dbo.AuditoriaCambio
        WHERE 1 = 0;    -- estructura sin datos

        PRINT 'Tabla de archivo creada: AuditoriaCambio_Archivo';
    END

    -- Archivar primero
    INSERT INTO dbo.AuditoriaCambio_Archivo
    SELECT * FROM dbo.AuditoriaCambio
    WHERE fecha_hora < @fecha_corte;

    SET @registros_del = @@ROWCOUNT;
    PRINT 'Registros archivados: ' + CAST(@registros_del AS VARCHAR(10));

    -- Luego eliminar de la tabla activa
    DELETE FROM dbo.AuditoriaCambio
    WHERE fecha_hora < @fecha_corte;

    PRINT '==> Limpieza de auditoría completada. Corte: '
          + CONVERT(VARCHAR, @fecha_corte, 120);
END;
GO


-- ------------------------------------------------------------
-- SP 4: Verificación de integridad de la base de datos
--       Wrapper de DBCC CHECKDB con reporte de resultado
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.sp_VerificarIntegridad
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '==> Iniciando verificación de integridad: ' + CONVERT(VARCHAR, GETDATE(), 120);

    -- CHECKDB verifica páginas, índices, restricciones y metadatos
    DBCC CHECKDB ('CosmoAgency')
        WITH NO_INFOMSGS,   -- solo muestra errores, no mensajes informativos
             ALL_ERRORMSGS; -- muestra todos los errores si los hay

    PRINT '==> Verificación completada: ' + CONVERT(VARCHAR, GETDATE(), 120);
END;
GO

PRINT '==> Stored procedures de mantenimiento creados.';
GO


-- ============================================================
-- SECCIÓN 6: CONSULTAS DE VERIFICACIÓN
-- Confirmar que todo quedó bien implementado
-- ============================================================

-- Ver todos los índices creados en CosmoAgency
SELECT
    t.name          AS tabla,
    i.name          AS indice,
    i.type_desc     AS tipo,
    i.fill_factor   AS fill_factor,
    i.has_filter    AS es_filtrado,
    i.filter_definition AS condicion_filtro,
    -- Columnas del índice
    STRING_AGG(c.name, ', ')
        WITHIN GROUP (ORDER BY ic.key_ordinal) AS columnas_clave
FROM sys.indexes i
JOIN sys.tables  t  ON i.object_id  = t.object_id
JOIN sys.index_columns ic ON i.object_id = ic.object_id
                          AND i.index_id = ic.index_id
                          AND ic.is_included_column = 0
JOIN sys.columns c  ON ic.object_id = c.object_id
                    AND ic.column_id = c.column_id
WHERE t.is_ms_shipped = 0
  AND i.type > 0           -- excluye heaps
  AND i.name LIKE 'IX_%'   -- solo nuestros índices
GROUP BY t.name, i.name, i.type_desc, i.fill_factor, i.has_filter, i.filter_definition
ORDER BY t.name, i.name;
GO

-- Ver las vistas creadas
SELECT
    name        AS vista,
    create_date,
    modify_date
FROM sys.views
WHERE name LIKE 'vw_%'
ORDER BY name;
GO

-- Ejecutar SP de reporte de índices (modo solo lectura)
EXEC dbo.sp_MantenimientoIndices @solo_reporte = 1;
GO

PRINT '============================================';
PRINT ' CosmoAgency — Optimización implementada OK';
PRINT '============================================';