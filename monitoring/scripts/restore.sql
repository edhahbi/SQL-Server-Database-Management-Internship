/* =====================================================================
   Restore ALL .bak files found in a folder
   - Creates one database per backup file
   - Skips databases that already exist
   - Auto-numbers physical file names on collision
   - Restores databases WITH NORECOVERY
   ===================================================================== */

SET NOCOUNT ON;

------------------------------------------------------------------------
-- 1. CONFIGURE THESE PATHS
------------------------------------------------------------------------

DECLARE @BackupFolder NVARCHAR(4000) =
    N'/var/opt/mssql/backups/bak/';

DECLARE @DataFolder NVARCHAR(4000) =
    N'/var/opt/mssql/data/';

DECLARE @LogFolder NVARCHAR(4000) =
    N'/var/opt/mssql/data/';

------------------------------------------------------------------------
-- 2. ENUMERATE .BAK FILES
------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#Files') IS NOT NULL
    DROP TABLE #Files;

CREATE TABLE #Files
(
    FileName NVARCHAR(4000),
    Depth INT,
    IsFile INT
);

INSERT INTO #Files
(
    FileName,
    Depth,
    IsFile
)
    EXEC master.sys.xp_dirtree
         @BackupFolder,
         1,
         1;

DELETE FROM #Files
WHERE IsFile = 0
   OR FileName NOT LIKE '%.bak';

------------------------------------------------------------------------
-- 3. TRACK USED FILE PATHS
------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#UsedFiles') IS NOT NULL
    DROP TABLE #UsedFiles;

CREATE TABLE #UsedFiles
(
    PhysicalPath NVARCHAR(260) PRIMARY KEY
);

INSERT INTO #UsedFiles
(
    PhysicalPath
)
SELECT DISTINCT
    physical_name
FROM sys.master_files;

------------------------------------------------------------------------
-- 4. VARIABLES
------------------------------------------------------------------------

DECLARE
    @File NVARCHAR(4000),
    @FullPath NVARCHAR(4000),
    @DBName NVARCHAR(256),
    @SQL NVARCHAR(MAX);

------------------------------------------------------------------------
-- 5. RESTORE EACH DATABASE WITH NORECOVERY
------------------------------------------------------------------------

DECLARE file_cursor CURSOR FOR
    SELECT FileName
    FROM #Files;

OPEN file_cursor;

FETCH NEXT FROM file_cursor
    INTO @File;

WHILE @@FETCH_STATUS = 0
    BEGIN

        SET @FullPath =
                @BackupFolder + @File;

        SET @DBName =
                LEFT(@File, LEN(@File) - 4);

        IF DB_ID(@DBName) IS NOT NULL
            BEGIN

                PRINT '--------------------------------------------------';
                PRINT 'SKIPPING: ' + @DBName + ' already exists.';
                PRINT '--------------------------------------------------';

                FETCH NEXT FROM file_cursor
                    INTO @File;

                CONTINUE;

            END;

        PRINT '--------------------------------------------------';
        PRINT 'Restoring: ' + @FullPath;
        PRINT 'Database: ' + @DBName;
        PRINT '--------------------------------------------------';

        BEGIN TRY

            DECLARE @MoveClauses NVARCHAR(MAX) = N'';

            IF OBJECT_ID('tempdb..#FileList') IS NOT NULL
                DROP TABLE #FileList;

            CREATE TABLE #FileList
            (
                LogicalName NVARCHAR(128),
                PhysicalName NVARCHAR(260),
                Type CHAR(1),
                FileGroupName NVARCHAR(128) NULL,
                Size NUMERIC(20, 0) NULL,
                MaxSize NUMERIC(20, 0) NULL,
                FileID BIGINT NULL,
                CreateLSN NUMERIC(25, 0) NULL,
                DropLSN NUMERIC(25, 0) NULL,
                UniqueID UNIQUEIDENTIFIER NULL,
                ReadOnlyLSN NUMERIC(25, 0) NULL,
                ReadWriteLSN NUMERIC(25, 0) NULL,
                BackupSizeInBytes BIGINT NULL,
                SourceBlockSize INT NULL,
                FileGroupID INT NULL,
                LogGroupGUID UNIQUEIDENTIFIER NULL,
                DifferentialBaseLSN NUMERIC(25, 0) NULL,
                DifferentialBaseGUID UNIQUEIDENTIFIER NULL,
                IsReadOnly BIT NULL,
                IsPresent BIT NULL,
                TDEThumbprint VARBINARY(32) NULL,
                SnapshotURL NVARCHAR(360) NULL
            );

            INSERT INTO #FileList
                EXEC
                    (
                    'RESTORE FILELISTONLY
                     FROM DISK = N'''
                    + @FullPath
                    + ''''
                    );

            ----------------------------------------------------------------
            -- BUILD MOVE CLAUSES
            ----------------------------------------------------------------

            DECLARE
                @LogicalName NVARCHAR(128),
                @Type CHAR(1),
                @Folder NVARCHAR(4000),
                @Ext NVARCHAR(10),
                @BaseName NVARCHAR(400),
                @Candidate NVARCHAR(260),
                @Suffix INT;

            DECLARE flist_cursor CURSOR LOCAL FOR
                SELECT
                    LogicalName,
                    Type
                FROM #FileList;

            OPEN flist_cursor;

            FETCH NEXT FROM flist_cursor
                INTO @LogicalName, @Type;

            WHILE @@FETCH_STATUS = 0
                BEGIN

                    SET @Folder =
                            CASE
                                WHEN @Type = 'L'
                                    THEN @LogFolder
                                ELSE @DataFolder
                                END;

                    SET @Ext =
                            CASE
                                WHEN @Type = 'L'
                                    THEN '.ldf'
                                ELSE '.mdf'
                                END;

                    SET @BaseName =
                            REPLACE(
                                    REPLACE(
                                            @LogicalName,
                                            ' ',
                                            '_'
                                    ),
                                    '''',
                                    ''
                            );

                    SET @Suffix = 1;

                    SET @Candidate =
                            @Folder
                                + @BaseName
                                + @Ext;

                    WHILE EXISTS
                        (
                            SELECT 1
                            FROM #UsedFiles
                            WHERE PhysicalPath = @Candidate
                        )
                        BEGIN

                            SET @Suffix = @Suffix + 1;

                            SET @Candidate =
                                    @Folder
                                        + @BaseName
                                        + '_'
                                        + CAST(@Suffix AS NVARCHAR(10))
                                        + @Ext;

                        END;

                    INSERT INTO #UsedFiles
                    (
                        PhysicalPath
                    )
                    VALUES
                        (
                            @Candidate
                        );

                    SET @MoveClauses =
                            @MoveClauses
                                + N', MOVE N'''
                                + @LogicalName
                                + N''' TO N'''
                                + @Candidate
                                + N'''';

                    FETCH NEXT FROM flist_cursor
                        INTO @LogicalName, @Type;

                END;

            CLOSE flist_cursor;
            DEALLOCATE flist_cursor;

            ----------------------------------------------------------------
            -- RESTORE WITH NORECOVERY
            ----------------------------------------------------------------

            SET @SQL =
                    N'RESTORE DATABASE ['
                        + @DBName
                        + N'] FROM DISK = N'''
                        + @FullPath
                        + N'''
            WITH '
                        + STUFF(@MoveClauses, 1, 1, '')
                        + N',REPLACE, STATS = 10;';

            PRINT @SQL;

            EXEC sp_executesql @SQL;

            PRINT
                'SUCCESS: '
                    + @DBName
                    + ' restored.';

        END TRY

        BEGIN CATCH

            PRINT
                'ERROR restoring '
                    + @File
                    + ': '
                    + ERROR_MESSAGE();

        END CATCH;

        FETCH NEXT FROM file_cursor
            INTO @File;

    END;

CLOSE file_cursor;
DEALLOCATE file_cursor;

------------------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------------------

DROP TABLE #Files;

IF OBJECT_ID('tempdb..#FileList') IS NOT NULL
    DROP TABLE #FileList;

DROP TABLE #UsedFiles;
