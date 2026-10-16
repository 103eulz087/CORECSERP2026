SELECT o.name, o.type_desc, s.execution_count runs, s.last_execution_time last_run, s.cached_time, CAST(s.total_elapsed_time/1000.0/NULLIF(s.execution_count,0) AS DECIMAL(18,1)) avg_ms
FROM sys.dm_exec_procedure_stats s JOIN sys.objects o ON o.object_id=s.object_id
WHERE s.database_id=DB_ID() ORDER BY s.execution_count DESC;
SELECT o.name, o.type_desc, s.execution_count runs, s.last_execution_time last_run
FROM sys.dm_exec_trigger_stats s JOIN sys.objects o ON o.object_id=s.object_id WHERE s.database_id=DB_ID() ORDER BY runs DESC;
SELECT o.name, o.type_desc, s.execution_count runs, s.last_execution_time last_run
FROM sys.dm_exec_function_stats s JOIN sys.objects o ON o.object_id=s.object_id WHERE s.database_id=DB_ID() ORDER BY runs DESC;
SELECT t.name trg, OBJECT_NAME(t.parent_id) tbl, t.is_disabled, t.is_instead_of_trigger, o.create_date, o.modify_date,
 STUFF((SELECT ','+te.type_desc FROM sys.trigger_events te WHERE te.object_id=t.object_id FOR XML PATH('')),1,1,'') evts
FROM sys.triggers t JOIN sys.objects o ON o.object_id=t.object_id WHERE t.parent_class=1 ORDER BY tbl;
SELECT name, create_date, modify_date FROM sys.triggers WHERE parent_class=0;
