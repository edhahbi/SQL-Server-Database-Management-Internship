-- Full Backup 

DECLARE @FullBackupDirectory NVARCHAR(500) = N'/var/opt/mssql/backups/bak/';
DECLARE @LogBackupDirectory  NVARCHAR(500) = N'/var/opt/mssql/backups/trn/';

DECLARE @DatabaseName SYSNAME;
DECLARE @BackupFile   NVARCHAR(1000);
DECLARE @SQL          NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = 'ONLINE'
      AND recovery_model_desc IN ('FULL', 'BULK_LOGGED')
      AND name NOT IN ('ArchiveDb', 'distribution');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
    BEGIN        
        SET @BackupFile =
                @FullBackupDirectory
                    + @DatabaseName
                    + N'.bak';

        SET @SQL = N'
        BACKUP DATABASE ' + QUOTENAME(@DatabaseName) + N'
        TO DISK = @BackupFile
        WITH
            COMPRESSION,
            CHECKSUM,
            STATS = 10;
    ';

        BEGIN TRY
            PRINT 'Starting FULL backup: ' + @DatabaseName;

            EXEC sys.sp_executesql
                 @SQL,
                 N'@BackupFile NVARCHAR(1000)',
                 @BackupFile = @BackupFile;

            PRINT 'FULL backup completed: ' + @DatabaseName;
        END TRY
        BEGIN CATCH
            PRINT 'FULL BACKUP ERROR: ' + @DatabaseName + ' - ' + ERROR_MESSAGE();
        END CATCH;

        /* 2. TRANSACTION LOG BACKUP (immediately following the full backup) */
        SET @BackupFile =
                @LogBackupDirectory
                    + @DatabaseName
                    + N'_'
                    + CONVERT(CHAR(8), GETDATE(), 112)
                    + N'_'
                    + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '')
                    + N'.trn';

        SET @SQL = N'
        BACKUP LOG ' + QUOTENAME(@DatabaseName) + N'
        TO DISK = @BackupFile
        WITH
            COMPRESSION,
            CHECKSUM,
            STATS = 10;
    ';

        BEGIN TRY
            PRINT 'Starting LOG backup: ' + @DatabaseName;

            EXEC sys.sp_executesql
                 @SQL,
                 N'@BackupFile NVARCHAR(1000)',
                 @BackupFile = @BackupFile;

            PRINT 'LOG backup completed: ' + @DatabaseName;
        END TRY
        BEGIN CATCH
            PRINT 'LOG BACKUP ERROR: ' + @DatabaseName + ' - ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @DatabaseName;
    END;

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO


-- Transaction Log Backup

DECLARE @LogOnlyBackupDirectory NVARCHAR(500) = N'/var/opt/mssql/backups/trn/';

DECLARE @LogDatabaseName SYSNAME;
DECLARE @LogBackupFile   NVARCHAR(1000);
DECLARE @LogSQL          NVARCHAR(MAX);

DECLARE logonly_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = 'ONLINE'
      AND recovery_model_desc IN ('FULL', 'BULK_LOGGED')
      AND name NOT IN ('ArchiveDb', 'distribution');

OPEN logonly_cursor;
FETCH NEXT FROM logonly_cursor INTO @LogDatabaseName;

WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @LogBackupFile =
                @LogOnlyBackupDirectory
                    + @LogDatabaseName
                    + N'.trn';

        SET @LogSQL = N'
        BACKUP LOG ' + QUOTENAME(@LogDatabaseName) + N'
        TO DISK = @LogBackupFile
        WITH
            COMPRESSION,
            CHECKSUM,
            STATS = 10;
    ';

        BEGIN TRY
            PRINT 'Backing up transaction log: ' + @LogDatabaseName;

            EXEC sys.sp_executesql
                 @LogSQL,
                 N'@LogBackupFile NVARCHAR(1000)',
                 @LogBackupFile = @LogBackupFile;

            PRINT 'Completed: ' + @LogDatabaseName;
        END TRY
        BEGIN CATCH
            PRINT 'ERROR: ' + @LogDatabaseName + ' - ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM logonly_cursor INTO @LogDatabaseName;
    END;

CLOSE logonly_cursor;
DEALLOCATE logonly_cursor;
GO