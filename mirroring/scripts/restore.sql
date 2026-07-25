/* =====================================================================
   SIMPLE RESTORE: latest full backup + matching transaction logs
   Uses msdb backup history (msdb.dbo.backupset / backupmediafamily)
   instead of parsing backup file headers, and restores files to their
   ORIGINAL paths (no MOVE) since backup and restore run on the same
   SQL Server instance.

   Requirements for this to work:
   - Restoring on the SAME instance that took the backups (msdb history
     is local to the instance)
   - Original data/log file paths are still valid targets
   ===================================================================== */

SET NOCOUNT ON;

DECLARE @FinishRecovery BIT = 0;   -- 0 = leave WITH NORECOVERY, 1 = RECOVERY after last log

------------------------------------------------------------------------
-- PHASE 1: restore the latest full backup for every database that
-- has one in history and doesn't already exist
------------------------------------------------------------------------

DECLARE @DBName SYSNAME, @BackupFile NVARCHAR(1000), @CheckpointLSN NUMERIC(25,0), @SQL NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#RestoredDBs') IS NOT NULL DROP TABLE #RestoredDBs;
CREATE TABLE #RestoredDBs (DBName SYSNAME PRIMARY KEY, CheckpointLSN NUMERIC(25,0));

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset WHERE type = 'D';

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
    BEGIN
        IF DB_ID(@DBName) IS NOT NULL
            BEGIN
                PRINT 'SKIPPING ' + @DBName + ': already exists.';
                FETCH NEXT FROM db_cursor INTO @DBName;
                CONTINUE;
            END;

        SELECT TOP 1
            @BackupFile = mf.physical_device_name,
            @CheckpointLSN = bs.checkpoint_lsn
        FROM msdb.dbo.backupset bs
                 JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
        WHERE bs.database_name = @DBName AND bs.type = 'D'
        ORDER BY bs.backup_finish_date DESC;

        PRINT 'Restoring ' + @DBName + ' from ' + @BackupFile;

        BEGIN TRY
            SET @SQL = N'RESTORE DATABASE ' + QUOTENAME(@DBName) + N'
                     FROM DISK = @BackupFile WITH NORECOVERY, STATS = 10;';

            EXEC sys.sp_executesql @SQL, N'@BackupFile NVARCHAR(1000)', @BackupFile = @BackupFile;

            INSERT INTO #RestoredDBs VALUES (@DBName, @CheckpointLSN);

            PRINT 'SUCCESS: ' + @DBName + ' restored WITH NORECOVERY.';
        END TRY
        BEGIN CATCH
            PRINT 'ERROR restoring ' + @DBName + ': ' + ERROR_MESSAGE();
        END CATCH;

        FETCH NEXT FROM db_cursor INTO @DBName;
    END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

------------------------------------------------------------------------
-- PHASE 2: apply every log backup that chains off the restored full
-- backup, in order
------------------------------------------------------------------------

DECLARE @LogFile NVARCHAR(1000), @LogSQL NVARCHAR(MAX);

DECLARE restored_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DBName, CheckpointLSN FROM #RestoredDBs;

OPEN restored_cursor;
FETCH NEXT FROM restored_cursor INTO @DBName, @CheckpointLSN;

WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT 'Applying logs for ' + @DBName;

        DECLARE log_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT mf.physical_device_name,
                   CASE WHEN bs.backup_set_id = MAX(bs.backup_set_id) OVER () THEN 1 ELSE 0 END
            FROM msdb.dbo.backupset bs
                     JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = bs.media_set_id
            WHERE bs.database_name = @DBName
              AND bs.type = 'L'
              AND bs.database_backup_lsn = @CheckpointLSN
            ORDER BY bs.backup_start_date ASC;

        OPEN log_cursor;

        DECLARE @IsLast BIT;
        FETCH NEXT FROM log_cursor INTO @LogFile, @IsLast;

        WHILE @@FETCH_STATUS = 0
            BEGIN
                BEGIN TRY
                    SET @LogSQL = N'RESTORE LOG ' + QUOTENAME(@DBName) + N'
                            FROM DISK = @LogFile WITH '
                        + CASE WHEN @IsLast = 1 AND @FinishRecovery = 1 THEN N'RECOVERY' ELSE N'NORECOVERY' END
                        + N', STATS = 10;';

                    EXEC sys.sp_executesql @LogSQL, N'@LogFile NVARCHAR(1000)', @LogFile = @LogFile;

                    PRINT 'Applied: ' + @LogFile;
                END TRY
                BEGIN CATCH
                    PRINT 'ERROR applying ' + @LogFile + ' to ' + @DBName + ': ' + ERROR_MESSAGE();
                END CATCH;

                FETCH NEXT FROM log_cursor INTO @LogFile, @IsLast;
            END;

        CLOSE log_cursor;
        DEALLOCATE log_cursor;

        FETCH NEXT FROM restored_cursor INTO @DBName, @CheckpointLSN;
    END;

CLOSE restored_cursor;
DEALLOCATE restored_cursor;

DROP TABLE #RestoredDBs;
GO