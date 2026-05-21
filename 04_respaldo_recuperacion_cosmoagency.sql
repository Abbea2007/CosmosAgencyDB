-- ============================================================
-- COSMOAGENCY — RESPALDO Y RECUPERACIÓN
-- Archivo: 03_respaldo_recuperacion_cosmoagency.sql
-- SGBD   : SQL Server 2016+
-- ============================================================

USE master;
GO

-- Verificar el modo actual antes de cambiar
SELECT
    name,
    recovery_model_desc         AS modo_recuperacion,
    log_reuse_wait_desc         AS log_reutilizacion,
    state_desc                  AS estado
FROM sys.databases
WHERE name = 'CosmoAgency';
GO

-- Configurar modo FULL (requerido para logs transaccionales)
ALTER DATABASE CosmoAgency SET RECOVERY FULL;
GO

-- Verificar que el cambio quedó aplicado
SELECT
    name,
    recovery_model_desc         AS modo_recuperacion
FROM sys.databases
WHERE name = 'CosmoAgency';
GO

USE master;
GO

-- ============================================================
-- FULL BACKUP — Punto de recuperación base
-- Este respaldo captura el estado completo de CosmoAgency
-- incluyendo: tablas, índices, vistas, SPs, triggers,
-- usuarios, roles y todos los datos al momento de ejecución
-- ============================================================

BACKUP DATABASE CosmoAgency
TO DISK = 'C:\BackUp\CosmosAgency\full\CosmosAgency_Full.bak'
WITH
    FORMAT,                                     -- sobreescribe el archivo si existe
    INIT,                                       -- inicia un nuevo media set
    NAME        = 'CosmoAgency — Full Backup',
    DESCRIPTION = 'Respaldo completo semanal — Agencia Aduanera Cosmos S.A.',
    COMPRESSION,                                -- reduce tamaño del archivo ~60%
    CHECKSUM,                                   -- verifica integridad durante el backup
    STATS = 10;                                 -- muestra progreso cada 10%
GO

-- Verificar que el backup se generó correctamente
RESTORE HEADERONLY
FROM DISK = 'C:\BackUp\CosmosAgency\full\CosmosAgency_Full.bak';
GO

-- Ver el contenido lógico del backup (archivos MDF y LDF)
RESTORE FILELISTONLY
FROM DISK = 'C:\BackUp\CosmosAgency\full\CosmosAgency_Full.bak';
GO

USE CosmoAgency;
GO

-- ============================================================
-- TRANSACCIÓN 1: Nueva moneda registrada en el sistema
-- Simula: el área de facturación agrega el Euro como divisa
-- ============================================================
INSERT INTO dbo.Moneda (id_moneda, nombre)
VALUES ('4', 'Pesos Mexicanos');

-- Verificar
SELECT * FROM dbo.Moneda;
GO


-- Estado tras T1: 
-- Full Backup → [T1: Euro insertado]
--                          ↑
--                    hasta aquí llegará el Diferencial

USE master;
GO

-- ============================================================
-- DIFFERENTIAL BACKUP — Captura cambios desde el último Full
-- En este punto captura: T1 (inserción de Euro en Moneda)
-- ============================================================

BACKUP DATABASE CosmoAgency
TO DISK = 'C:\BackUp\CosmosAgency\diferencial\CosmoAgency_Diferencial.bak'
WITH
    DIFFERENTIAL,
    INIT,
    NAME        = 'CosmoAgency — Differential Backup',
    DESCRIPTION = 'Respaldo diferencial diario — Agencia Aduanera Cosmos S.A.',
    COMPRESSION,
    CHECKSUM,
    STATS = 10;
GO

-- Verificar el diferencial
RESTORE HEADERONLY
FROM DISK = 'C:\BackUp\CosmosAgency\diferencial\CosmoAgency_Diferencial.bak';
GO

USE CosmoAgency;
GO

-- ============================================================
-- TRANSACCIÓN 2: Nuevo detalle de factura — Inspección documental
-- Simula: facturación registra un servicio prestado
-- ============================================================
INSERT INTO dbo.DetalleFactura
VALUES (1003, 4, 3, 'Inspección Documental', 1, 12.00, 12.00);

SELECT * FROM DetalleFactura
-- ============================================================
-- TRANSACCIÓN 3: Nuevo detalle de factura — Aforo acompañado
-- Simula: facturación registra un segundo servicio del expediente
-- ============================================================
INSERT INTO dbo.DetalleFactura
VALUES (1004, 4, 5, 'Aforo Acompañado', 1, 25.00, 25.00);

-- Verificar estado actual
SELECT COUNT(*) AS total_detalles FROM dbo.DetalleFactura;
GO

-- Estado tras T3:
-- Full → [T1] → Diferencial → [T2] → [T3]
--                                         ↑
--                                  hasta aquí llegará el Log

USE master;
GO

-- ============================================================
-- LOG BACKUP — Captura T1, T2 y T3
-- Se ejecuta cada 15 minutos en producción
-- ============================================================

BACKUP LOG CosmoAgency
TO DISK = 'C:\BackUp\CosmosAgency\log\CosmoAgency_Log1.trn'
WITH
    INIT,
    NAME        = 'CosmoAgency — Log Backup 1',
    DESCRIPTION = 'Respaldo de log transaccional — cada 15 minutos',
    COMPRESSION,
    CHECKSUM,
    STATS = 10;
GO

-- Verificar el log backup
RESTORE HEADERONLY
FROM DISK = 'C:\BackUp\CosmosAgency\log\CosmoAgency_Log1.trn'
WITH;
GO

USE CosmoAgency;
GO

-- ============================================================
-- TRANSACCIÓN 4: Cálculo de tributos — CRÍTICA
-- Esta transacción ocurre DESPUÉS del último Log Backup
-- Simula: una liquidación de tributos registrada minutos
-- antes de que ocurra el desastre — la más importante de perder
-- ============================================================
INSERT INTO dbo.DetalleFactura
VALUES (1005, 5, 10, 'Cálculo de Tributos', 1, 15.00, 15.00);

-- Verificar
SELECT COUNT(*) AS total_detalles FROM dbo.DetalleFactura;
GO

-- Estado final antes del desastre:
-- Full → [T1] → Diferencial → [T2, T3] → Log1 → [T4: NO respaldada]
--                                                       ↑
--                                              DESASTRE AQUÍ

USE master;
GO



-- ============================================================
-- SIMULACIÓN DE DESASTRE
-- Se elimina la base de datos completa para simular:
-- - Corrupción total del disco de datos
-- - Ataque de ransomware
-- - Error humano crítico (DROP accidental)
-- ============================================================

-- Cerrar todas las conexiones activas antes del DROP
ALTER DATABASE CosmoAgency SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

DROP DATABASE CosmoAgency;
GO

USE master;
GO

-- PASO A1: Restaurar el Full con NORECOVERY
-- (NORECOVERY = la BD queda en modo restauración, lista para recibir más backups)
RESTORE DATABASE CosmoAgency
FROM DISK = 'C:\BackUp\CosmosAgency\full\CosmosAgency_Full.bak'
WITH
    MOVE 'AgenciaAduaneraV.1'
        TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\CosmoAgency.mdf',
    MOVE 'AgenciaAduaneraV.1_log'
        TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\CosmoAgency_log.ldf',
    NORECOVERY,
    REPLACE,
    STATS = 10;
GO

-- PASO A2: Poner la BD en línea (RECOVERY = ya no se aplican más backups)
RESTORE DATABASE CosmoAgency WITH RECOVERY;
GO

-- VERIFICACIÓN Escenario A
USE CosmoAgency;
GO
SELECT 'Moneda'        AS tabla, COUNT(*) AS registros FROM dbo.Moneda
UNION ALL
SELECT 'DetalleFactura', COUNT(*) FROM dbo.DetalleFactura;
-- Resultado esperado: Moneda sin Pesos mexicanos, DetalleFactura sin T2/T3/T4
GO

USE master;
GO

-- Limpiar BD del escenario anterior si existe
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'CosmoAgency')
BEGIN
    ALTER DATABASE CosmoAgency SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE CosmoAgency;
END
GO

-- PASO B1: Restaurar Full con NORECOVERY
RESTORE DATABASE CosmoAgency
FROM DISK = 'C:\BackUp\CosmosAgency\full\CosmosAgency_Full.bak'
WITH
    MOVE 'AgenciaAduaneraV.1'
        TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\CosmoAgency.mdf',
    MOVE 'AgenciaAduaneraV.1_log'
        TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\CosmoAgency_log.ldf',
    NORECOVERY,
    REPLACE,
    STATS = 10;
GO

-- PASO B2: Aplicar el Diferencial y dejar la BD en línea
RESTORE DATABASE CosmoAgency
FROM DISK = 'C:\BackUp\CosmosAgency\diferencial\CosmoAgency_Diferencial.bak'
WITH
    RECOVERY,       -- pone la BD en línea directamente
    STATS = 10;
GO

-- VERIFICACIÓN Escenario B
USE CosmoAgency;
GO
SELECT 'Moneda'        AS tabla, COUNT(*) AS registros FROM dbo.Moneda
UNION ALL
SELECT 'DetalleFactura', COUNT(*) FROM dbo.DetalleFactura;
-- Resultado esperado: Moneda CON EUR (T1 recuperada), DetalleFactura sin T2/T3/T4
GO

USE master;
GO

-- Limpiar BD del escenario anterior
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'CosmoAgency')
BEGIN
    ALTER DATABASE CosmoAgency SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE CosmoAgency;
END
GO

-- PASO C1: Restaurar Full con NORECOVERY
RESTORE DATABASE CosmoAgency
FROM DISK = 'C:\BackUp\CosmosAgency\full\CosmosAgency_Full.bak'
WITH
    MOVE 'AgenciaAduaneraV.1'
        TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\CosmoAgency.mdf',
    MOVE 'AgenciaAduaneraV.1_log'
        TO 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\CosmoAgency_log.ldf',
    NORECOVERY,
    REPLACE,
    STATS = 10;
GO

-- PASO C2: Aplicar Diferencial con NORECOVERY
-- (la BD sigue en modo restauración, espera el log)
RESTORE DATABASE CosmoAgency
FROM DISK = 'C:\BackUp\CosmosAgency\diferencial\CosmoAgency_Diferencial.bak'
WITH
    NORECOVERY,
    STATS = 10;
GO

-- PASO C3: Aplicar Log Backup y dejar la BD en línea
RESTORE LOG CosmoAgency
FROM DISK = 'C:\BackUp\CosmosAgency\log\CosmoAgency_Log1.trn'
WITH
    RECOVERY,       -- pone la BD en línea, ya no se aplican más backups
    STATS = 10;
GO

-- VERIFICACIÓN Escenario C
USE CosmoAgency;
GO
SELECT 'Moneda'         AS tabla, COUNT(*) AS registros FROM dbo.Moneda
UNION ALL
SELECT 'DetalleFactura', COUNT(*) FROM dbo.DetalleFactura;
-- Resultado esperado: Moneda CON EUR, DetalleFactura CON T2 y T3 (1002 filas)
-- T4 (id 1003) no aparece porque ocurrió después del Log Backup
GO

-- ============================================================
-- AUTOMATIZACIÓN: SQL Agent Jobs para los 3 niveles de respaldo
-- Estos jobs reemplazan la ejecución manual y garantizan que
-- la política se cumpla incluso sin intervención humana
-- ============================================================

USE msdb;
GO

-- ------------------------------------------------------------
-- JOB 1: Full Backup — Domingos 18:00
-- ------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'CosmoAgency_FullBackup')
    EXEC msdb.dbo.sp_delete_job @job_name = 'CosmoAgency_FullBackup';
GO

EXEC msdb.dbo.sp_add_job
    @job_name       = 'CosmoAgency_FullBackup',
    @description    = 'Respaldo completo semanal de CosmoAgency — domingos 18:00',
    @enabled        = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = 'CosmoAgency_FullBackup',
    @step_name      = 'Ejecutar Full Backup',
    @command        = N'
DECLARE @ruta NVARCHAR(500);
SET @ruta = ''C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\AgenciaAduanera\Full\CosmoAgency_Full_''
            + CONVERT(VARCHAR(8), GETDATE(), 112) + ''.bak'';

BACKUP DATABASE CosmoAgency
TO DISK = @ruta
WITH FORMAT, INIT,
     NAME        = ''CosmoAgency Full Backup Semanal'',
     COMPRESSION, CHECKSUM, STATS = 10;
',
    @on_success_action = 1,     -- 1 = ir al paso siguiente
    @on_fail_action    = 2;     -- 2 = salir reportando fallo
GO

-- Programar: cada domingo a las 18:00
EXEC msdb.dbo.sp_add_schedule
    @schedule_name      = 'Semanal_Domingo_18h',
    @freq_type          = 8,        -- semanal
    @freq_interval      = 1,        -- domingo (bit 0 = domingo)
    @freq_recurrence_factor = 1,    -- cada 1 semana
    @active_start_time  = 180000;   -- 18:00:00
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name       = 'CosmoAgency_FullBackup',
    @schedule_name  = 'Semanal_Domingo_18h';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = 'CosmoAgency_FullBackup';
GO


-- ------------------------------------------------------------
-- JOB 2: Differential Backup — Lunes a Sábado 18:00
-- ------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'CosmoAgency_DiffBackup')
    EXEC msdb.dbo.sp_delete_job @job_name = 'CosmoAgency_DiffBackup';
GO

EXEC msdb.dbo.sp_add_job
    @job_name       = 'CosmoAgency_DiffBackup',
    @description    = 'Respaldo diferencial diario de CosmoAgency — lunes a sábado 18:00',
    @enabled        = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name   = 'CosmoAgency_DiffBackup',
    @step_name  = 'Ejecutar Differential Backup',
    @command    = N'
DECLARE @ruta NVARCHAR(500);
SET @ruta = ''C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\AgenciaAduanera\Diferencial\CosmoAgency_Diff_''
            + CONVERT(VARCHAR(8), GETDATE(), 112) + ''.bak'';

BACKUP DATABASE CosmoAgency
TO DISK = @ruta
WITH DIFFERENTIAL, INIT,
     NAME        = ''CosmoAgency Differential Backup Diario'',
     COMPRESSION, CHECKSUM, STATS = 10;
',
    @on_success_action = 1,
    @on_fail_action    = 2;
GO

-- Programar: lunes a sábado (bits 2+4+8+16+32+64 = 126) a las 18:00
EXEC msdb.dbo.sp_add_schedule
    @schedule_name          = 'LunesASabado_18h',
    @freq_type              = 8,
    @freq_interval          = 126,      -- lun(2)+mar(4)+mié(8)+jue(16)+vie(32)+sáb(64)
    @freq_recurrence_factor = 1,
    @active_start_time      = 180000;
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name       = 'CosmoAgency_DiffBackup',
    @schedule_name  = 'LunesASabado_18h';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = 'CosmoAgency_DiffBackup';
GO


-- ------------------------------------------------------------
-- JOB 3: Log Backup — Cada 15 minutos, todos los días
-- ------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'CosmoAgency_LogBackup')
    EXEC msdb.dbo.sp_delete_job @job_name = 'CosmoAgency_LogBackup';
GO

EXEC msdb.dbo.sp_add_job
    @job_name       = 'CosmoAgency_LogBackup',
    @description    = 'Respaldo de log transaccional cada 15 minutos',
    @enabled        = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name   = 'CosmoAgency_LogBackup',
    @step_name  = 'Ejecutar Log Backup',
    @command    = N'
DECLARE @ruta NVARCHAR(500);
SET @ruta = ''C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\AgenciaAduanera\Log\CosmoAgency_Log_''
            + CONVERT(VARCHAR(8), GETDATE(), 112)
            + ''_'' + REPLACE(CONVERT(VARCHAR(8), GETDATE(), 108),'':'','''') + ''.trn'';

BACKUP LOG CosmoAgency
TO DISK = @ruta
WITH INIT,
     NAME        = ''CosmoAgency Log Backup'',
     COMPRESSION, CHECKSUM, STATS = 10;
',
    @on_success_action = 1,
    @on_fail_action    = 2;
GO

-- Programar: todos los días, cada 15 minutos
EXEC msdb.dbo.sp_add_schedule
    @schedule_name          = 'Cada15Min_TodoElDia',
    @freq_type              = 4,        -- diario
    @freq_interval          = 1,        -- cada 1 día
    @freq_subday_type       = 4,        -- repetir por minutos
    @freq_subday_interval   = 15,       -- cada 15 minutos
    @active_start_time      = 0;        -- desde medianoche
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name       = 'CosmoAgency_LogBackup',
    @schedule_name  = 'Cada15Min_TodoElDia';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = 'CosmoAgency_LogBackup';
GO


-- ------------------------------------------------------------
-- JOB 4: Retención — Purga de backups con más de 30 días
-- Elimina archivos .bak y .trn viejos para liberar espacio
-- Se ejecuta cada domingo a las 20:00 (tras el Full)
-- ------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = 'CosmoAgency_Retencion')
    EXEC msdb.dbo.sp_delete_job @job_name = 'CosmoAgency_Retencion';
GO

EXEC msdb.dbo.sp_add_job
    @job_name       = 'CosmoAgency_Retencion',
    @description    = 'Política de retención: elimina backups con más de 30 días',
    @enabled        = 1;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name   = 'CosmoAgency_Retencion',
    @step_name  = 'Purgar backups antiguos',
    @subsystem  = 'TSQL',
    @command    = N'
-- Eliminar Full Backups con más de 30 días
EXEC msdb.dbo.sp_delete_backuphistory
    @oldest_date = DATEADD(DAY, -30, GETDATE());

-- Nota: para eliminar archivos físicos del disco
-- se requiere xp_cmdshell o un script PowerShell externo.
-- Documentar esta tarea para el DBA responsable.
PRINT ''Historial de backups purgado: '' + CONVERT(VARCHAR, GETDATE(), 120);
';
GO

EXEC msdb.dbo.sp_add_schedule
    @schedule_name      = 'Domingo_20h_Retencion',
    @freq_type          = 8,
    @freq_interval      = 1,
    @freq_recurrence_factor = 1,
    @active_start_time  = 200000;   -- 20:00:00
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name       = 'CosmoAgency_Retencion',
    @schedule_name  = 'Domingo_20h_Retencion';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name = 'CosmoAgency_Retencion';
GO

PRINT '==> Jobs de respaldo automatizados creados correctamente.';
GO