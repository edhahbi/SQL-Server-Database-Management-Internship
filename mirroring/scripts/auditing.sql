USE master;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.server_audits
    WHERE name = N'CentralDatabaseAudit'
)
    BEGIN
        CREATE SERVER AUDIT [CentralDatabaseAudit]
            TO FILE
            (
            FILEPATH = N'/var/opt/mssql/audit/',
            MAXSIZE = 1 GB,
            MAX_ROLLOVER_FILES = 20,
            RESERVE_DISK_SPACE = OFF
            )
            WITH
            (
            QUEUE_DELAY = 1000,
            ON_FAILURE = CONTINUE
            );
    END;
GO


IF EXISTS (
    SELECT 1
    FROM sys.server_audits
    WHERE name = N'CentralDatabaseAudit'
      AND is_state_enabled = 0
)
    BEGIN
        ALTER SERVER AUDIT [CentralDatabaseAudit]
            WITH (STATE = ON);
    END;
GO

DECLARE @DatabaseName SYSNAME;
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = 'ONLINE'
      AND is_read_only = 0;

OPEN db_cursor;

FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY

            SET @SQL = N'
USE ' + QUOTENAME(@DatabaseName) + N';

IF NOT EXISTS
(
    SELECT 1
    FROM sys.database_audit_specifications
    WHERE name = N''AuditSpec_' + REPLACE(@DatabaseName, '''', '''''') + N'''
)
BEGIN

    CREATE DATABASE AUDIT SPECIFICATION
        [AuditSpec_' + REPLACE(@DatabaseName, '''', '''''') + N']
    FOR SERVER AUDIT [CentralDatabaseAudit]

    ADD (DATABASE_OBJECT_CHANGE_GROUP),

    ADD (SCHEMA_OBJECT_CHANGE_GROUP),

    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),

    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),

    ADD (DATABASE_PERMISSION_CHANGE_GROUP),

    ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP),

    ADD (SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP),

    ADD (SELECT ON DATABASE::[' + REPLACE(@DatabaseName, ']', ']]') + N'] BY PUBLIC),

    ADD (INSERT ON DATABASE::[' + REPLACE(@DatabaseName, ']', ']]') + N'] BY PUBLIC),

    ADD (UPDATE ON DATABASE::[' + REPLACE(@DatabaseName, ']', ']]') + N'] BY PUBLIC),

    ADD (DELETE ON DATABASE::[' + REPLACE(@DatabaseName, ']', ']]') + N'] BY PUBLIC),

    ADD (EXECUTE ON DATABASE::[' + REPLACE(@DatabaseName, ']', ']]') + N'] BY PUBLIC);

END;

ALTER DATABASE AUDIT SPECIFICATION
    [AuditSpec_' + REPLACE(@DatabaseName, '''', '''''') + N']
WITH (STATE = ON);
';

            PRINT 'Configuring audit for database: ' + @DatabaseName;

            EXEC sys.sp_executesql @SQL;

        END TRY
        BEGIN CATCH

            PRINT 'ERROR in database: ' + @DatabaseName;
            PRINT ERROR_MESSAGE();

        END CATCH;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- inspection 

SELECT *
FROM sys.fn_get_audit_file(
        '/var/opt/mssql/audit/*.sqlaudit',
        DEFAULT,
        DEFAULT
     )
WHERE database_name = 'ArchiveDb'
ORDER BY event_time DESC;