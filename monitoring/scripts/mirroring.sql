-- certifacte generation 

create master key
    encryption by password = 'ClinisysStage$12';

create certificate PrimaryCert 
    with subject = 'Mirroring Certificate [PRIMARY]';
       
backup certificate PrimaryCert
    to file = '/var/opt/mssql/certs/PrimaryCert.cer';

create certificate MirrorCert
    from file = '/var/opt/mssql/certs/MirrorCert.cer';

create login MirrorLogin 
    from certificate MirrorCert;

create endpoint mirroring_endpoint
    state = started 
    as tcp (
        listener_port = 5022
        )
    for database_mirroring 
        (
        authentication = CERTIFICATE PrimaryCert,
        encryption = required algorithm aes ,
        role = partner 
        );
go;

grant connect on endpoint::mirroring_endpoint
    to MirrorLogin;

DECLARE @local  SYSNAME = CONVERT(SYSNAME, SERVERPROPERTY('ServerName'));
DECLARE @remote SYSNAME = N'F86ABC8870C9';   -- confirm from the secondary's own SELECT

PRINT 'local replica = ' + @local;

DECLARE @sql NVARCHAR(MAX) = N'
CREATE AVAILABILITY GROUP [AG_Clinisys]
    WITH (CLUSTER_TYPE = NONE, DB_FAILOVER = ON)
    FOR REPLICA ON
        ' + QUOTENAME(@local, '''') + N' WITH (
            ENDPOINT_URL = ''tcp://sqlserver:5022'',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC,
            SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)),
        ' + QUOTENAME(@remote, '''') + N' WITH (
            ENDPOINT_URL = ''tcp://sqlserver_mirroring:5022'',
            AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
            FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC,
            SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));';

EXEC sp_executesql @sql;

SET NOCOUNT ON;

DECLARE @Db  SYSNAME,
    @Sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT d.name
    FROM sys.databases d
             LEFT JOIN sys.availability_databases_cluster adc
                       ON adc.database_name = d.name
    WHERE d.database_id > 4
      AND d.state_desc   = 'ONLINE'
      AND d.is_read_only = 0
      AND d.source_database_id IS NULL          -- exclude snapshots
      AND adc.database_name IS NULL             -- not already in an AG
      AND d.name NOT IN ('ArchiveDb', 'distribution');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @Db;

WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            PRINT 'Preparing ' + QUOTENAME(@Db);

            SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@Db) + N' SET RECOVERY FULL;';
            EXEC sp_executesql @Sql;

            SET @Sql = N'BACKUP DATABASE ' + QUOTENAME(@Db)
                + N' TO DISK = ''/var/opt/mssql/backups/' + @Db + N'_init.bak''
                     WITH INIT, COMPRESSION;';
            EXEC sp_executesql @Sql;

            SET @Sql = N'ALTER AVAILABILITY GROUP [AG_Clinisys] ADD DATABASE '
                + QUOTENAME(@Db) + N';';
            EXEC sp_executesql @Sql;

            PRINT 'OK: ' + @Db + ' added to AG_Clinisys.';
        END TRY
        BEGIN CATCH
            PRINT 'ERROR: ' + @Db + ' - ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @Db;
    END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- inspection 

SELECT DB_NAME(drs.database_id)      AS base,
       ar.replica_server_name,
       drs.synchronization_state_desc,   -- SYNCHRONIZED / SYNCHRONIZING / NOT SYNCHRONIZING
       drs.synchronization_health_desc,
       drs.is_suspended,
       drs.log_send_queue_size,          -- KB waiting to leave the primary
       drs.redo_queue_size,              -- KB received but not yet replayed
       drs.last_hardened_time
FROM sys.dm_hadr_database_replica_states drs
         JOIN sys.availability_replicas ar ON ar.replica_id = drs.replica_id;

