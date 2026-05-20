USE CosmoAgency;
GO

/* ============================================================
   1. Información general de la base de datos
   ============================================================ */

SELECT 
    name AS NombreBaseDatos,
    create_date AS FechaCreacion,
    compatibility_level AS NivelCompatibilidad,
    recovery_model_desc AS ModeloRecuperacion,
    state_desc AS Estado
FROM sys.databases
WHERE name = DB_NAME();
GO


/* ============================================================
   2. Listado de tablas de usuario
   ============================================================ */

SELECT 
    s.name AS Esquema,
    t.name AS Tabla,
    t.create_date AS FechaCreacion,
    t.modify_date AS UltimaModificacion
FROM sys.tables t
INNER JOIN sys.schemas s 
    ON t.schema_id = s.schema_id
ORDER BY t.name;
GO


/* ============================================================
   3. Cantidad aproximada de registros por tabla
   ============================================================ */

SELECT 
    t.name AS Tabla,
    SUM(p.rows) AS CantidadRegistros
FROM sys.tables t
INNER JOIN sys.partitions p 
    ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY CantidadRegistros DESC;
GO


/* ============================================================
   4. Columnas, tipos de datos y nulabilidad
   ============================================================ */

SELECT 
    t.name AS Tabla,
    c.name AS Columna,
    ty.name AS TipoDato,
    c.max_length AS Longitud,
    c.precision AS PrecisionNumerica,
    c.scale AS EscalaNumerica,
    c.is_nullable AS PermiteNulos
FROM sys.tables t
INNER JOIN sys.columns c 
    ON t.object_id = c.object_id
INNER JOIN sys.types ty 
    ON c.user_type_id = ty.user_type_id
ORDER BY t.name, c.column_id;
GO


/* ============================================================
   5. Claves primarias existentes
   ============================================================ */

SELECT 
    t.name AS Tabla,
    kc.name AS NombrePK,
    c.name AS ColumnaPK
FROM sys.key_constraints kc
INNER JOIN sys.tables t 
    ON kc.parent_object_id = t.object_id
INNER JOIN sys.index_columns ic 
    ON kc.parent_object_id = ic.object_id 
   AND kc.unique_index_id = ic.index_id
INNER JOIN sys.columns c 
    ON ic.object_id = c.object_id 
   AND ic.column_id = c.column_id
WHERE kc.type = 'PK'
ORDER BY t.name, c.column_id;
GO


/* ============================================================
   6. Relaciones por claves foráneas
   ============================================================ */

SELECT 
    fk.name AS NombreFK,
    tp.name AS TablaOrigen,
    cp.name AS ColumnaOrigen,
    tr.name AS TablaReferenciada,
    cr.name AS ColumnaReferenciada
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc 
    ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.tables tp 
    ON fkc.parent_object_id = tp.object_id
INNER JOIN sys.columns cp 
    ON fkc.parent_object_id = cp.object_id 
   AND fkc.parent_column_id = cp.column_id
INNER JOIN sys.tables tr 
    ON fkc.referenced_object_id = tr.object_id
INNER JOIN sys.columns cr 
    ON fkc.referenced_object_id = cr.object_id 
   AND fkc.referenced_column_id = cr.column_id
ORDER BY tp.name, fk.name;
GO


/* ============================================================
   7. Índices existentes
   ============================================================ */

SELECT 
    t.name AS Tabla,
    i.name AS Indice,
    i.type_desc AS TipoIndice,
    i.is_unique AS EsUnico,
    c.name AS Columna
FROM sys.indexes i
INNER JOIN sys.tables t 
    ON i.object_id = t.object_id
INNER JOIN sys.index_columns ic 
    ON i.object_id = ic.object_id 
   AND i.index_id = ic.index_id
INNER JOIN sys.columns c 
    ON ic.object_id = c.object_id 
   AND ic.column_id = c.column_id
WHERE i.name IS NOT NULL
ORDER BY t.name, i.name, ic.key_ordinal;
GO


/* ============================================================
   8. Tablas sin clave primaria
   ============================================================ */

SELECT 
    t.name AS TablaSinClavePrimaria
FROM sys.tables t
WHERE NOT EXISTS (
    SELECT 1
    FROM sys.key_constraints kc
    WHERE kc.parent_object_id = t.object_id
      AND kc.type = 'PK'
)
ORDER BY t.name;
GO


/* ============================================================
   9. Tablas sin claves foráneas entrantes ni salientes
   ============================================================ */

SELECT 
    t.name AS TablaSinRelacionDetectada
FROM sys.tables t
WHERE NOT EXISTS (
    SELECT 1 
    FROM sys.foreign_keys fk 
    WHERE fk.parent_object_id = t.object_id
       OR fk.referenced_object_id = t.object_id
)
ORDER BY t.name;
GO