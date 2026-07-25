-- certificate generation 
print @@servername;

create master key
    encryption by password = 'ClinisysStage$12';

create certificate MirrorCert 
    with subject = 'Mirroring Certificate [SLAVE]';

backup certificate MirrorCert
    to file = '/var/opt/mssql/certs/MirrorCert.cer';

create certificate PrimaryCert
    from file = '/var/opt/mssql/certs/PrimaryCert.cer';

create login MirrorLogin
    from certificate PrimaryCert;

create endpoint mirroring
    state = started
    as tcp (
        listener_port = 5022
        )
    for database_mirroring
        (
        authentication = CERTIFICATE MirrorCert,
        encryption = required algorithm aes ,
        role = partner
        );
go;

grant connect on endpoint::mirroring
    to MirrorLogin;

SET NOCOUNT ON;

DECLARE @MirrorPartner NVARCHAR(256) = N'TCP://sqlserver:5022';
DECLARE @Db SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = 'RESTORING'
      AND is_read_only = 0
      AND name not in ('ArchiveDbRepl');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @Db;

WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            PRINT 'Configuring mirroring for ' + QUOTENAME(@Db);

            SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@Db) + N' SET PARTNER = N''' + @MirrorPartner + N''';';
            EXEC sp_executesql @Sql;

            SET @Sql = N'ALTER DATABASE ' + QUOTENAME(@Db) + N' SET SAFETY FULL;';
            EXEC sp_executesql @Sql;

            PRINT 'OK: ' + @Db + ' set to synchronous mirroring.';
        END TRY
        BEGIN CATCH
            PRINT 'ERROR: ' + @Db + ' - ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @Db;
    END

CLOSE db_cursor;
DEALLOCATE db_cursor;

