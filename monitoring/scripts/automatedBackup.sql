USE master;
GO

-- FULL BACKUP

CREATE OR ALTER PROCEDURE dbo.BackupAllUserDatabases_Full
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @DatabaseName SYSNAME,
        @BackupPath NVARCHAR(1000),
        @FileName NVARCHAR(1000);

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
            SET @BackupPath = N'/var/opt/mssql/backups/automated/full';

            SET @FileName =
                    @BackupPath
                        + @DatabaseName
                        + N'_FULL_'
                        + CONVERT(CHAR(8), GETDATE(), 112)
                        + N'_'
                        + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '')
                        + N'.bak';

            BEGIN TRY
                PRINT 'Starting FULL backup of ' + @DatabaseName;

                BACKUP DATABASE @DatabaseName
                    TO DISK = @FileName
                    WITH
                    INIT,
                    COMPRESSION,
                    CHECKSUM,
                    STATS = 10;

                PRINT 'Completed FULL backup of ' + @DatabaseName;
            END TRY
            BEGIN CATCH
                PRINT 'ERROR backing up ' + @DatabaseName;
                PRINT ERROR_MESSAGE();
            END CATCH;

            FETCH NEXT FROM db_cursor INTO @DatabaseName;
        END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
END;
GO


--   DIFFERENTIAL BACKUP

CREATE OR ALTER PROCEDURE dbo.BackupAllUserDatabases_Differential
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @DatabaseName SYSNAME,
        @BackupPath NVARCHAR(1000),
        @FileName NVARCHAR(1000);

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
            SET @BackupPath = N'/var/opt/mssql/backups/automated/diff';

            SET @FileName =
                    @BackupPath
                        + @DatabaseName
                        + N'_DIFF_'
                        + CONVERT(CHAR(8), GETDATE(), 112)
                        + N'_'
                        + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '')
                        + N'.bak';

            BEGIN TRY
                PRINT 'Starting DIFFERENTIAL backup of ' + @DatabaseName;

                BACKUP DATABASE @DatabaseName
                    TO DISK = @FileName
                    WITH
                    DIFFERENTIAL,
                    INIT,
                    COMPRESSION,
                    CHECKSUM,
                    STATS = 10;

                PRINT 'Completed DIFFERENTIAL backup of ' + @DatabaseName;
            END TRY
            BEGIN CATCH
                PRINT 'ERROR backing up ' + @DatabaseName;
                PRINT ERROR_MESSAGE();
            END CATCH;

            FETCH NEXT FROM db_cursor INTO @DatabaseName;
        END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
END;
GO


--   TRANSACTION LOG BACKUP

CREATE OR ALTER PROCEDURE dbo.BackupAllUserDatabases_Log
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @DatabaseName SYSNAME,
        @RecoveryModel NVARCHAR(60),
        @BackupPath NVARCHAR(1000),
        @FileName NVARCHAR(1000);

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            name,
            recovery_model_desc
        FROM sys.databases
        WHERE database_id > 4
          AND state_desc = 'ONLINE'
          AND recovery_model_desc IN ('FULL', 'BULK_LOGGED');

    OPEN db_cursor;

    FETCH NEXT FROM db_cursor
        INTO @DatabaseName, @RecoveryModel;

    WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @BackupPath = N'/var/opt/mssql/backups/automated/trn';

            SET @FileName =
                    @BackupPath
                        + @DatabaseName
                        + N'_LOG_'
                        + CONVERT(CHAR(8), GETDATE(), 112)
                        + N'_'
                        + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '')
                        + N'.trn';

            BEGIN TRY
                PRINT 'Starting LOG backup of ' + @DatabaseName;

                BACKUP LOG @DatabaseName
                    TO DISK = @FileName
                    WITH
                    INIT,
                    COMPRESSION,
                    CHECKSUM,
                    STATS = 10;

                PRINT 'Completed LOG backup of ' + @DatabaseName;
            END TRY
            BEGIN CATCH
                PRINT 'ERROR backing up ' + @DatabaseName;
                PRINT ERROR_MESSAGE();
            END CATCH;

            FETCH NEXT FROM db_cursor
                INTO @DatabaseName, @RecoveryModel;
        END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;
END;
GO

-- weekly full backup job
           
USE msdb;
GO

EXEC dbo.sp_add_job
    @job_name = N'Backup - All User Databases - FULL';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Backup - All User Databases - FULL',
    @step_name = N'Full Backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'EXEC master.dbo.BackupAllUserDatabases_Full;';
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Weekly - Sunday - 01:00',
    @freq_type = 8,
    @freq_interval = 1,
    @freq_recurrence_factor = 1,
    @active_start_time = 010000;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'Backup - All User Databases - FULL',
    @schedule_name = N'Weekly - Sunday - 01:00';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Backup - All User Databases - FULL';
GO

exec msdb.dbo.sp_start_job
     @job_name = N'Backup - All User Databases - FULL';
GO
-- differential daily backup job 
EXEC dbo.sp_add_job
    @job_name = N'Backup - All User Databases - DIFFERENTIAL';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Backup - All User Databases - DIFFERENTIAL',
    @step_name = N'Differential Backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'EXEC master.dbo.BackupAllUserDatabases_Differential;';
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Daily - 02:00',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 020000;
GO


EXEC dbo.sp_attach_schedule
    @job_name = N'Backup - All User Databases - DIFFERENTIAL',
    @schedule_name = N'Daily - 02:00';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Backup - All User Databases - DIFFERENTIAL';
GO

exec msdb.dbo.sp_start_job
     @job_name = N'Backup - All User Databases - DIFFERENTIAL';
GO
-- hourly transactional log backup job

EXEC dbo.sp_add_job
    @job_name = N'Backup - All User Databases - LOG';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'Backup - All User Databases - LOG',
    @step_name = N'Transaction Log Backup',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'EXEC master.dbo.BackupAllUserDatabases_Log;';
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'Hourly - Transaction Logs',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 8,
    @freq_subday_interval = 1,
    @active_start_time = 000000,
    @active_end_time = 235959;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'Backup - All User Databases - LOG',
    @schedule_name = N'Hourly - Transaction Logs';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'Backup - All User Databases - LOG';
GO

exec msdb.dbo.sp_start_job
     @job_name = N'Backup - All User Databases - FULL';
GO

exec msdb.dbo.sp_help_job;