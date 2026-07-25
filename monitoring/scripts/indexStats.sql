SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,

    -- Reads
    ISNULL(us.user_seeks, 0)   AS UserSeeks,
    ISNULL(us.user_scans, 0)   AS UserScans,
    ISNULL(us.user_lookups, 0) AS UserLookups,

    -- Writes
    ISNULL(us.user_updates, 0) AS UserUpdates,

    -- Last usage
    us.last_user_seek,
    us.last_user_scan,
    us.last_user_lookup,
    us.last_user_update

FROM sys.indexes AS i
         LEFT JOIN sys.dm_db_index_usage_stats AS us
                   ON us.object_id = i.object_id
                       AND us.index_id = i.index_id
                       AND us.database_id = DB_ID()
