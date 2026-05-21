-- ============================================================
-- COSMOAGENCY — SEGURIDAD Y GOBIERNO DE DATOS
-- Archivo: 02_seguridad_cosmoagency.sql
-- SGBD   : SQL Server (cualquier edición 2016+)
-- Fecha  : 2025
-- ============================================================

USE master;
GO

-- ============================================================
-- SECCIÓN 1: CREACIÓN DE LOGINS A NIVEL DE SERVIDOR
-- Los logins existen en el servidor SQL, independiente de la BD
-- ============================================================

-- Login del administrador de base de datos
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_admin_cosmos')
BEGIN
    CREATE LOGIN login_admin_cosmos
        WITH PASSWORD    = 'Admin@Cosmos2025!',
             CHECK_POLICY = ON,          -- aplica política de contraseñas de Windows
             CHECK_EXPIRATION = ON,      -- fuerza expiración periódica
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_admin_cosmos';
END
GO

-- Login de operaciones (digitadores / aforadores)
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_operaciones')
BEGIN
    CREATE LOGIN login_operaciones
        WITH PASSWORD    = 'Operac@2025#',
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = ON,
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_operaciones';
END
GO

-- Login de clasificación arancelaria
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_clasificacion')
BEGIN
    CREATE LOGIN login_clasificacion
        WITH PASSWORD    = 'Clasif@2025#',
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = ON,
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_clasificacion';
END
GO

-- Login de facturación / tesorería
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_facturacion')
BEGIN
    CREATE LOGIN login_facturacion
        WITH PASSWORD    = 'Factur@2025#',
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = ON,
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_facturacion';
END
GO

-- Login de ejecutivo de cuenta
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_ejecutivo')
BEGIN
    CREATE LOGIN login_ejecutivo
        WITH PASSWORD    = 'Ejecut@2025#',
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = ON,
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_ejecutivo';
END
GO

-- Login de auditoría interna
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_auditoria')
BEGIN
    CREATE LOGIN login_auditoria
        WITH PASSWORD    = 'Audit@2025#!',
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = ON,
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_auditoria';
END
GO

-- Login de gerencia / dirección
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_gerencia')
BEGIN
    CREATE LOGIN login_gerencia
        WITH PASSWORD    = 'Gerenc@2025#',
             CHECK_POLICY = ON,
             CHECK_EXPIRATION = ON,
             DEFAULT_DATABASE = CosmoAgency;
    PRINT 'LOGIN creado: login_gerencia';
END
GO


-- ============================================================
-- SECCIÓN 2: USUARIOS DENTRO DE LA BASE DE DATOS CosmoAgency
-- Un usuario de BD mapea a un login de servidor
-- ============================================================

USE CosmoAgency;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_admin_cosmos')
BEGIN
    CREATE USER usr_admin_cosmos FOR LOGIN login_admin_cosmos;
    PRINT 'USER creado: usr_admin_cosmos';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_operaciones')
BEGIN
    CREATE USER usr_operaciones FOR LOGIN login_operaciones;
    PRINT 'USER creado: usr_operaciones';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_clasificacion')
BEGIN
    CREATE USER usr_clasificacion FOR LOGIN login_clasificacion;
    PRINT 'USER creado: usr_clasificacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_facturacion')
BEGIN
    CREATE USER usr_facturacion FOR LOGIN login_facturacion;
    PRINT 'USER creado: usr_facturacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_ejecutivo')
BEGIN
    CREATE USER usr_ejecutivo FOR LOGIN login_ejecutivo;
    PRINT 'USER creado: usr_ejecutivo';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_auditoria')
BEGIN
    CREATE USER usr_auditoria FOR LOGIN login_auditoria;
    PRINT 'USER creado: usr_auditoria';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_gerencia')
BEGIN
    CREATE USER usr_gerencia FOR LOGIN login_gerencia;
    PRINT 'USER creado: usr_gerencia';
END
GO


-- ============================================================
-- SECCIÓN 3: CREACIÓN DE ROLES PERSONALIZADOS
-- Los roles agrupan permisos; los usuarios se asignan a roles
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_operaciones' AND type = 'R')
BEGIN
    CREATE ROLE rol_operaciones;
    PRINT 'ROL creado: rol_operaciones';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_clasificacion' AND type = 'R')
BEGIN
    CREATE ROLE rol_clasificacion;
    PRINT 'ROL creado: rol_clasificacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_facturacion' AND type = 'R')
BEGIN
    CREATE ROLE rol_facturacion;
    PRINT 'ROL creado: rol_facturacion';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_ejecutivo' AND type = 'R')
BEGIN
    CREATE ROLE rol_ejecutivo;
    PRINT 'ROL creado: rol_ejecutivo';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_auditoria' AND type = 'R')
BEGIN
    CREATE ROLE rol_auditoria;
    PRINT 'ROL creado: rol_auditoria';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_gerencia' AND type = 'R')
BEGIN
    CREATE ROLE rol_gerencia;
    PRINT 'ROL creado: rol_gerencia';
END
GO


-- ============================================================
-- SECCIÓN 4: ASIGNACIÓN DE PERMISOS POR ROL Y TABLA
-- Principio de mínimo privilegio: cada rol solo tiene lo que
-- necesita para cumplir su función operativa
-- ============================================================

-- ----------------------------------------------------------
-- ROL: rol_operaciones
-- Quién: Digitadores y aforadores
-- Necesita: gestionar expedientes, declaraciones, documentos,
--           hitos y consultar catálogos
-- ----------------------------------------------------------

-- Clientes: pueden ver y actualizar, no crear ni eliminar
GRANT SELECT, UPDATE ON dbo.Clientes          TO rol_operaciones;

-- Expedientes: ciclo de vida completo
GRANT SELECT, INSERT, UPDATE ON dbo.Expediente        TO rol_operaciones;

-- Declaraciones
GRANT SELECT, INSERT, UPDATE ON dbo.Declaracion       TO rol_operaciones;

-- Ítems de declaración
GRANT SELECT, INSERT, UPDATE ON dbo.ItemDeclaracion   TO rol_operaciones;

-- Documentos de soporte
GRANT SELECT, INSERT, UPDATE ON dbo.DocumentoSoporte  TO rol_operaciones;

-- Hitos de trazabilidad: solo insertan eventos, no los modifican
GRANT SELECT, INSERT         ON dbo.HitoTrazabilidad  TO rol_operaciones;

-- Liquidación de tributos: pueden verla, no crearla (la crea facturación)
GRANT SELECT, INSERT         ON dbo.LiquidacionTributo TO rol_operaciones;

-- Facturas: solo consulta para verificar estado del expediente
GRANT SELECT                 ON dbo.Factura            TO rol_operaciones;
GRANT SELECT                 ON dbo.DetalleFactura      TO rol_operaciones;

-- Catálogos: solo lectura
GRANT SELECT ON dbo.CodigoArancelario TO rol_operaciones;
GRANT SELECT ON dbo.Pais              TO rol_operaciones;
GRANT SELECT ON dbo.Moneda            TO rol_operaciones;
GRANT SELECT ON dbo.UnidadMedida      TO rol_operaciones;
GRANT SELECT ON dbo.Servicio          TO rol_operaciones;
GRANT SELECT ON dbo.Sucursal          TO rol_operaciones;
GRANT SELECT ON dbo.Departamento      TO rol_operaciones;
GRANT SELECT ON dbo.Municipio         TO rol_operaciones;
GO

-- ----------------------------------------------------------
-- ROL: rol_clasificacion
-- Quién: Analistas de clasificación arancelaria
-- Necesita: mantener catálogo HS y consultar ítems
-- ----------------------------------------------------------

GRANT SELECT, INSERT, UPDATE ON dbo.CodigoArancelario  TO rol_clasificacion;
GRANT SELECT, INSERT         ON dbo.UnidadMedida        TO rol_clasificacion;
GRANT SELECT, UPDATE         ON dbo.ItemDeclaracion     TO rol_clasificacion;

-- Consulta de referencia
GRANT SELECT ON dbo.Declaracion   TO rol_clasificacion;
GRANT SELECT ON dbo.Expediente    TO rol_clasificacion;
GRANT SELECT ON dbo.Clientes      TO rol_clasificacion;
GRANT SELECT ON dbo.Pais          TO rol_clasificacion;
GRANT SELECT ON dbo.Moneda        TO rol_clasificacion;
GO

-- ----------------------------------------------------------
-- ROL: rol_facturacion
-- Quién: Facturadora / tesorería
-- Necesita: emitir facturas, registrar pagos, gestionar servicios
-- ----------------------------------------------------------

-- Clientes: ver para facturar
GRANT SELECT, UPDATE ON dbo.Clientes           TO rol_facturacion;

-- Expedientes: solo lectura para asociar facturas
GRANT SELECT         ON dbo.Expediente         TO rol_facturacion;
GRANT SELECT         ON dbo.Declaracion        TO rol_facturacion;

-- Financiero: control total de su área
GRANT SELECT, INSERT, UPDATE ON dbo.Factura          TO rol_facturacion;
GRANT SELECT, INSERT         ON dbo.DetalleFactura    TO rol_facturacion;
GRANT SELECT, INSERT         ON dbo.Pago              TO rol_facturacion;
GRANT SELECT, INSERT         ON dbo.LiquidacionTributo TO rol_facturacion;

-- Catálogos necesarios para facturar
GRANT SELECT, INSERT, UPDATE ON dbo.Servicio  TO rol_facturacion;
GRANT SELECT, INSERT         ON dbo.Moneda    TO rol_facturacion;
GRANT SELECT                 ON dbo.Sucursal  TO rol_facturacion;
GO

-- ----------------------------------------------------------
-- ROL: rol_ejecutivo
-- Quién: Ejecutivos de cuenta (seguimiento al cliente)
-- Necesita: solo lectura del estado del expediente
-- ----------------------------------------------------------

GRANT SELECT ON dbo.Clientes          TO rol_ejecutivo;
GRANT SELECT ON dbo.Expediente        TO rol_ejecutivo;
GRANT SELECT ON dbo.Declaracion       TO rol_ejecutivo;
GRANT SELECT ON dbo.ItemDeclaracion   TO rol_ejecutivo;
GRANT SELECT ON dbo.DocumentoSoporte  TO rol_ejecutivo;
GRANT SELECT ON dbo.HitoTrazabilidad  TO rol_ejecutivo;
GRANT SELECT ON dbo.LiquidacionTributo TO rol_ejecutivo;
GRANT SELECT ON dbo.Factura           TO rol_ejecutivo;
GRANT SELECT ON dbo.DetalleFactura    TO rol_ejecutivo;
GRANT SELECT ON dbo.Pago              TO rol_ejecutivo;
GRANT SELECT ON dbo.CodigoArancelario TO rol_ejecutivo;
GRANT SELECT ON dbo.Pais              TO rol_ejecutivo;
GRANT SELECT ON dbo.Moneda            TO rol_ejecutivo;
GRANT SELECT ON dbo.UnidadMedida      TO rol_ejecutivo;
GRANT SELECT ON dbo.Servicio          TO rol_ejecutivo;
GRANT SELECT ON dbo.Sucursal          TO rol_ejecutivo;
GRANT SELECT ON dbo.Departamento      TO rol_ejecutivo;
GRANT SELECT ON dbo.Municipio         TO rol_ejecutivo;
GRANT SELECT ON dbo.Usuario           TO rol_ejecutivo;
GRANT SELECT ON dbo.Rol               TO rol_ejecutivo;
GRANT SELECT ON dbo.UsuarioRol        TO rol_ejecutivo;
GO

-- ----------------------------------------------------------
-- ROL: rol_auditoria
-- Quién: Auditoría interna / control interno
-- Necesita: lectura total incluyendo la bitácora, NUNCA escribe
-- ----------------------------------------------------------

GRANT SELECT ON dbo.Clientes           TO rol_auditoria;
GRANT SELECT ON dbo.Expediente         TO rol_auditoria;
GRANT SELECT ON dbo.Declaracion        TO rol_auditoria;
GRANT SELECT ON dbo.ItemDeclaracion    TO rol_auditoria;
GRANT SELECT ON dbo.DocumentoSoporte   TO rol_auditoria;
GRANT SELECT ON dbo.HitoTrazabilidad   TO rol_auditoria;
GRANT SELECT ON dbo.LiquidacionTributo TO rol_auditoria;
GRANT SELECT ON dbo.Factura            TO rol_auditoria;
GRANT SELECT ON dbo.DetalleFactura     TO rol_auditoria;
GRANT SELECT ON dbo.Pago               TO rol_auditoria;
GRANT SELECT ON dbo.CodigoArancelario  TO rol_auditoria;
GRANT SELECT ON dbo.Pais               TO rol_auditoria;
GRANT SELECT ON dbo.Moneda             TO rol_auditoria;
GRANT SELECT ON dbo.UnidadMedida       TO rol_auditoria;
GRANT SELECT ON dbo.Servicio           TO rol_auditoria;
GRANT SELECT ON dbo.Sucursal           TO rol_auditoria;
GRANT SELECT ON dbo.Departamento       TO rol_auditoria;
GRANT SELECT ON dbo.Municipio          TO rol_auditoria;
GRANT SELECT ON dbo.Usuario            TO rol_auditoria;
GRANT SELECT ON dbo.Rol                TO rol_auditoria;
GRANT SELECT ON dbo.UsuarioRol         TO rol_auditoria;
GRANT SELECT ON dbo.AuditoriaCambio    TO rol_auditoria;
GO

-- ----------------------------------------------------------
-- ROL: rol_gerencia
-- Quién: Dirección general
-- Necesita: lectura amplia para KPIs y reportes estratégicos
-- ----------------------------------------------------------

GRANT SELECT ON dbo.Clientes           TO rol_gerencia;
GRANT SELECT ON dbo.Expediente         TO rol_gerencia;
GRANT SELECT ON dbo.Declaracion        TO rol_gerencia;
GRANT SELECT ON dbo.ItemDeclaracion    TO rol_gerencia;
GRANT SELECT ON dbo.HitoTrazabilidad   TO rol_gerencia;
GRANT SELECT ON dbo.LiquidacionTributo TO rol_gerencia;
GRANT SELECT ON dbo.Factura            TO rol_gerencia;
GRANT SELECT ON dbo.DetalleFactura     TO rol_gerencia;
GRANT SELECT ON dbo.Pago               TO rol_gerencia;
GRANT SELECT ON dbo.Servicio           TO rol_gerencia;
GRANT SELECT ON dbo.Sucursal           TO rol_gerencia;
GRANT SELECT ON dbo.CodigoArancelario  TO rol_gerencia;
GRANT SELECT ON dbo.Moneda             TO rol_gerencia;
GRANT SELECT ON dbo.AuditoriaCambio    TO rol_gerencia;
GO

-- ----------------------------------------------------------
-- ADMIN: permisos completos vía rol predefinido de SQL Server
-- ----------------------------------------------------------
ALTER ROLE db_owner ADD MEMBER usr_admin_cosmos;
GO


-- ============================================================
-- SECCIÓN 5: ASIGNACIÓN DE USUARIOS A ROLES
-- ============================================================

ALTER ROLE rol_operaciones  ADD MEMBER usr_operaciones;
ALTER ROLE rol_clasificacion ADD MEMBER usr_clasificacion;
ALTER ROLE rol_facturacion  ADD MEMBER usr_facturacion;
ALTER ROLE rol_ejecutivo    ADD MEMBER usr_ejecutivo;
ALTER ROLE rol_auditoria    ADD MEMBER usr_auditoria;
ALTER ROLE rol_gerencia     ADD MEMBER usr_gerencia;
GO

PRINT '==> Asignación de usuarios a roles completada.';
GO


-- ============================================================
-- SECCIÓN 6: AUDITORÍA BÁSICA DE ACCESOS
-- Trigger DDL a nivel de BD para capturar cambios de esquema
-- ============================================================

-- Trigger que registra intentos de modificación de estructura
CREATE OR ALTER TRIGGER trg_auditoria_ddl_cosmos
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE,
    CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE,
    CREATE_VIEW, ALTER_VIEW, DROP_VIEW,
    GRANT_DATABASE, REVOKE_DATABASE, DENY_DATABASE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @datos XML = EVENTDATA();

    -- Nota que ya NO llamamos a id_auditoria en el INSERT ni en el VALUES
    INSERT INTO dbo.AuditoriaCambio
        (entidad, operacion, fecha, id_usuario, detalle)
    VALUES (
        -- 1. entidad
        ISNULL(@datos.value('(/EVENT_INSTANCE/ObjectName)[1]',  'NVARCHAR(60)'),  'ESQUEMA'),
        
        -- 2. operacion (Cortado a 10 caracteres para que quepa en tu columna)
        LEFT(@datos.value('(/EVENT_INSTANCE/EventType)[1]',     'NVARCHAR(100)'), 10),
        
        -- 3. fecha
        GETDATE(),
        
        -- 4. id_usuario
        ISNULL(@datos.value('(/EVENT_INSTANCE/LoginName)[1]',   'NVARCHAR(40)'), 'UNKNOWN'),
        
        -- 5. detalle
        LEFT(@datos.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)'), 1000)
    );
END;
GO

SELECT name AS Columna_Identity
FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.AuditoriaCambio')
  AND is_identity = 1;

  EXEC sp_help 'dbo.AuditoriaCambio';
  DISABLE TRIGGER trg_auditoria_ddl_cosmos ON DATABASE;
  -- 1. Crear una tabla idéntica pero con la propiedad IDENTITY(1,1)
CREATE TABLE dbo.AuditoriaCambio_Nueva (
    id_auditoria INT IDENTITY(1,1) NOT NULL,
    entidad NVARCHAR(60) NULL,
    operacion NVARCHAR(10) NULL,
    fecha DATETIME NULL,
    id_usuario NVARCHAR(40) NULL,
    detalle NVARCHAR(1000) NULL,
    CONSTRAINT PK_AuditoriaCambio_Nueva PRIMARY KEY (id_auditoria)
);
GO
-- 2. SI YA TIENES DATOS: Migrar los datos de la vieja a la nueva
-- (SQL Server le asignará un número automático a los registros viejos)
INSERT INTO dbo.AuditoriaCambio_Nueva (entidad, operacion, fecha, id_usuario, detalle)
SELECT entidad, operacion, fecha, id_usuario, detalle 
FROM dbo.AuditoriaCambio;
GO

DROP TABLE dbo.AuditoriaCambio;
GO

EXEC sp_rename 'dbo.AuditoriaCambio_Nueva', 'AuditoriaCambio';
GO

DROP TRIGGER trg_auditoria_ddl_cosmos ON DATABASE;
GO

-- ============================================================
-- SECCIÓN 7: TRIGGERS DML DE AUDITORÍA EN TABLAS SENSIBLES
-- Registran INSERT, UPDATE y DELETE en datos críticos del negocio
-- ============================================================

-- ----------------------------------------------------------
-- Trigger de auditoría en Expediente
-- ----------------------------------------------------------
CREATE OR ALTER TRIGGER trg_audit_expediente
ON dbo.Expediente
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @op CHAR(1);

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @op = 'I';
    ELSE
        SET @op = 'D';

    -- Audita cada fila afectada
    INSERT INTO dbo.(entidad, operacion, fecha, id_usuario, detalle)
    SELECT
        'Expediente',
        CAST(ISNULL(i.id_expediente, d.id_expediente) AS VARCHAR(40)),
        @op,
        GETDATE(),
        SYSTEM_USER,
        '{"estado_nuevo":"' + ISNULL(i.estado,'') +
        '","estado_ant":"'  + ISNULL(d.estado,'') +
        '","cliente":"'     + CAST(ISNULL(i.id_cliente, d.id_cliente) AS VARCHAR(10)) + '"}'
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_expediente = d.id_expediente;
END;
GO

DROP TRIGGER trg_audit_expediente
GO

-- ----------------------------------------------------------
-- Trigger de auditoría en Declaracion
-- ----------------------------------------------------------
CREATE OR ALTER TRIGGER trg_audit_declaracion
ON dbo.Declaracion
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @op CHAR(1);

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @op = 'I';
    ELSE
        SET @op = 'D';

    INSERT INTO dbo.AuditoriaCambio (id_auditoria, entidad, operacion, fecha, id_usuario, detalle)
    SELECT
        'Declaracion',
        CAST(ISNULL(i.id_declaracion, d.id_declaracion) AS VARCHAR(40)),
        @op,
        GETDATE(),
        SYSTEM_USER,
        '{"numero":"'       + ISNULL(i.numero, ISNULL(d.numero,'')) +
        '","valor_aduana":"'+ CAST(ISNULL(i.valor_aduana, d.valor_aduana) AS VARCHAR(20))'"}'
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_declaracion = d.id_declaracion;
END;
GO

-- ----------------------------------------------------------
-- Trigger de auditoría en Factura
-- ----------------------------------------------------------
CREATE OR ALTER TRIGGER trg_audit_factura
ON dbo.Factura
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @op CHAR(1);

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @op = 'I';
    ELSE
        SET @op = 'D';

    INSERT INTO dbo.AuditoriaCambio (id_auditoria, entidad, operacion, fecha, id_usuario, detalle)
    SELECT
        'Factura',
        CAST(ISNULL(i.id_factura, d.id_factura) AS VARCHAR(40)),
        @op,
        GETDATE(),
        SYSTEM_USER,
        '{"numero":"'  + ISNULL(i.numero_factura, ISNULL(d.numero_factura,'')) +
        '","estado_nuevo":"' + ISNULL(i.estado,'') +
        '","estado_ant":"'   + ISNULL(d.estado,'') +
        '","total":"'  + CAST(ISNULL(i.total, d.total) AS VARCHAR(20)) + '"}'
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_factura = d.id_factura;
END;
GO

-- ----------------------------------------------------------
-- Trigger de auditoría en LiquidacionTributo
-- ----------------------------------------------------------
CREATE OR ALTER TRIGGER trg_audit_liquidacion
ON dbo.LiquidacionTributo
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @op CHAR(1);

    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @op = 'U';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @op = 'I';
    ELSE
        SET @op = 'D';

    INSERT INTO dbo.AuditoriaCambio (id_auditoria, entidad, operacion, fecha, id_usuario, detalle)
    SELECT
        'LiquidacionTributo',
        CAST(ISNULL(i.id_liquidacion, d.id_liquidacion) AS VARCHAR(40)),
        @op,
        GETDATE(),
        SYSTEM_USER,
        '{"total_ant":"'  + CAST(ISNULL(d.total_tributos, 0) AS VARCHAR(20)) +
        '","total_nuevo":"'+ CAST(ISNULL(i.total_tributos, 0) AS VARCHAR(20)) + '"}'
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.id_liquidacion = d.id_liquidacion;
END;
GO

PRINT '==> Triggers DML de auditoría creados.';
GO


-- ============================================================
-- SECCIÓN 8: POLÍTICAS DE SEGURIDAD
-- ============================================================

-- Política 1: Denegar explícitamente DELETE en tablas financieras
-- Nadie (salvo admin) puede borrar registros financieros; se anulan, no se borran
DENY DELETE ON dbo.Factura           TO rol_facturacion;
DENY DELETE ON dbo.Pago              TO rol_facturacion;
DENY DELETE ON dbo.LiquidacionTributo TO rol_facturacion;
DENY DELETE ON dbo.DetalleFactura    TO rol_facturacion;

EXEC sp_helptext 'trg_auditoria_ddl_cosmos';

-- Política 2: Denegar DELETE en tabla de auditoría para todos
DENY DELETE ON dbo.AuditoriaCambio TO rol_operaciones;
DENY DELETE ON dbo.AuditoriaCambio TO rol_clasificacion;
DENY DELETE ON dbo.AuditoriaCambio TO rol_facturacion;
DENY DELETE ON dbo.AuditoriaCambio TO rol_ejecutivo;
DENY DELETE ON dbo.AuditoriaCambio TO rol_auditoria;
DENY DELETE ON dbo.AuditoriaCambio TO rol_gerencia;

-- Política 3: Denegar UPDATE en AuditoriaCambio — los registros son inmutables
DENY UPDATE ON dbo.AuditoriaCambio TO rol_operaciones;
DENY UPDATE ON dbo.AuditoriaCambio TO rol_clasificacion;
DENY UPDATE ON dbo.AuditoriaCambio TO rol_facturacion;
DENY UPDATE ON dbo.AuditoriaCambio TO rol_ejecutivo;
DENY UPDATE ON dbo.AuditoriaCambio TO rol_auditoria;
DENY UPDATE ON dbo.AuditoriaCambio TO rol_gerencia;

-- Política 4: Denegar DROP y ALTER a usuarios no admin (a nivel servidor)
-- Esto lo refuerza el trigger DDL de la sección 6
DENY ALTER  ON SCHEMA::dbo TO rol_operaciones;
DENY ALTER  ON SCHEMA::dbo TO rol_facturacion;
DENY ALTER  ON SCHEMA::dbo TO rol_clasificacion;
DENY ALTER  ON SCHEMA::dbo TO rol_ejecutivo;
DENY ALTER  ON SCHEMA::dbo TO rol_auditoria;
DENY ALTER  ON SCHEMA::dbo TO rol_gerencia;
GO

PRINT '==> Políticas de seguridad aplicadas.';
GO
SELECT * FROM AuditoriaCambio

-- ============================================================
-- SECCIÓN 9: VERIFICACIÓN — consultas para confirmar que todo
-- quedó correctamente configurado
-- ============================================================

-- Ver todos los logins del servidor
SELECT name, type_desc, is_disabled, create_date
FROM sys.server_principals
WHERE name LIKE 'login_%cosmos%'
   OR name LIKE 'login_%operaciones%'
   OR name LIKE 'login_%clasificacion%'
   OR name LIKE 'login_%facturacion%'
   OR name LIKE 'login_%ejecutivo%'
   OR name LIKE 'login_%auditoria%'
   OR name LIKE 'login_%gerencia%'
ORDER BY name;

-- Ver usuarios de la base de datos
SELECT name, type_desc, create_date
FROM sys.database_principals
WHERE type IN ('S','U')
  AND name LIKE 'usr_%'
ORDER BY name;

-- Ver roles personalizados creados
SELECT name, type_desc
FROM sys.database_principals
WHERE type = 'R'
  AND is_fixed_role = 0
  AND name LIKE 'rol_%'
ORDER BY name;

-- Ver miembros de cada rol
SELECT
    r.name  AS rol,
    m.name  AS miembro
FROM sys.database_role_members rm
JOIN sys.database_principals   r ON rm.role_principal_id   = r.principal_id
JOIN sys.database_principals   m ON rm.member_principal_id = m.principal_id
WHERE r.name LIKE 'rol_%'
ORDER BY r.name, m.name;

-- Ver permisos asignados por rol y tabla
SELECT
    pr.name         AS principal,
    o.name          AS tabla,
    p.permission_name,
    p.state_desc    AS estado
FROM sys.database_permissions p
JOIN sys.database_principals  pr ON p.grantee_principal_id = pr.principal_id
JOIN sys.objects               o  ON p.major_id             = o.object_id
WHERE pr.name LIKE 'rol_%'
ORDER BY pr.name, o.name, p.permission_name;

-- Ver registros de auditoría más recientes
SELECT TOP 20
    id_aud, entidad, id_registro, operacion,
    fecha_hora, usuario, detalle_json
FROM dbo.AuditoriaCambio
ORDER BY fecha_hora DESC;
GO

PRINT '============================================';
PRINT ' CosmoAgency — Seguridad implementada OK';
PRINT '============================================';