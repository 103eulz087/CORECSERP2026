SET NOCOUNT ON;
SELECT st.text, qs.execution_count, qs.last_execution_time INTO #q
FROM sys.dm_exec_query_stats qs CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.dbid = DB_ID() OR (st.dbid IS NULL AND st.objectid IS NULL);
SELECT o.name, o.type, SUM(q.execution_count) runs, MAX(q.last_execution_time) last_run, COUNT(*) stmts
FROM sys.objects o JOIN #q q ON q.text LIKE '%' + o.name + '%'
WHERE o.type IN ('V','IF','TF','FN') AND o.is_ms_shipped = 0
GROUP BY o.name, o.type ORDER BY runs DESC;
SELECT COUNT(*) cached_stmts FROM #q;
