USE master;
GO

create login repl_login with password = 'ClinisysStage$12';
       go;
       
use archiveDb;
    
create user repl_user for login repl_login;
       
USE master;
go;

EXEC sys.sp_adddistributor
     @distributor = N'C2E3D78FCF17',
     @password = N'ClinisysStage$12';
GO

EXEC sys.sp_adddistributiondb
     @database = N'distribution',
     @security_mode = 0,
     @login = N'repl_login',
     @password = N'ClinisysStage$12',
     @data_folder = N'/var/opt/mssql/data',
     @log_folder = N'/var/opt/mssql/data';
GO

EXEC sys.sp_adddistpublisher
     @publisher = N'C2E3D78FCF17',
     @distribution_db = N'distribution',
     @security_mode = 0,
     @login = N'repl_login',
     @password = N'ClinisysStage$12';
GO

EXEC sys.sp_replicationdboption
     @dbname = N'ArchiveDb',
     @optname = N'publish',
     @value = N'true';
GO

USE ArchiveDb;
GO

EXEC sys.sp_addpublication
     @publication = N'ArchiveDbPublication',
     @description = N'Transactional replication publication',
     @status = N'active',
     @allow_push = N'true',
     @allow_pull = N'true',
     @repl_freq = N'continuous',
     @independent_agent = N'true',
     @retention = 0,
     @allow_initialize_from_backup = N'false';
GO

EXEC sys.sp_addpublication_snapshot
     @publication = N'ArchiveDbPublication',
     @frequency_type = 1;
GO

DECLARE @TableName SYSNAME;

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.tables
WHERE is_ms_shipped = 0
ORDER BY name;

OPEN table_cursor;

FETCH NEXT FROM table_cursor INTO @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
        PRINT N'Adding article: ' + @TableName;

EXEC sys.sp_addarticle
             @publication = N'ArchiveDbPublication',
             @article = @TableName,
             @source_owner = N'dbo',
             @source_object = @TableName,
             @destination_table = @TableName,
             @type = N'logbased';

FETCH NEXT FROM table_cursor INTO @TableName;
END;

CLOSE table_cursor;
DEALLOCATE table_cursor;
GO

EXEC sys.sp_helparticle
     @publication = N'ArchiveDbPublication';

USE ArchiveDb;
GO

EXEC sys.sp_addsubscription
     @publication = N'ArchiveDbPublication',
     @subscriber = '3e7de6338edd',
     @destination_db = N'ArchiveDbRepl',
     @subscription_type = N'Push',
     @sync_type = N'automatic',
     @article = N'all',
     @update_mode = N'read only',
     @subscriber_type = 0;
GO


EXEC sys.sp_addpushsubscription_agent
     @publication = N'ArchiveDbPublication',
     @subscriber = N'3e7de6338edd',
     @subscriber_db = N'ArchiveDbRepl',
     @subscriber_security_mode = 0,
     @subscriber_login = N'repl_login',
     @subscriber_password = N'ClinisysStage$12',
     @frequency_type = 64;
GO

EXEC msdb.dbo.sp_start_job
     @job_name = N'C2E3D78FCF17-ArchiveDb-ArchiveDbPublication-1';
GO

EXEC msdb.dbo.sp_start_job
     @job_name = N'C2E3D78FCF17-ArchiveDb-ArchiveDbPublication-3E7DE6338EDD-3';
GO