SELECT j.name job, j.enabled, js.step_id, js.step_name, js.subsystem, js.database_name, REPLACE(REPLACE(js.command,CHAR(13),' '),CHAR(10),' ') command,
 s.name sched, s.enabled sched_enabled, s.freq_type, s.freq_interval, s.freq_subday_type, s.freq_subday_interval, s.active_start_time
FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps js ON js.job_id=j.job_id
LEFT JOIN msdb.dbo.sysjobschedules jsc ON jsc.job_id=j.job_id LEFT JOIN msdb.dbo.sysschedules s ON s.schedule_id=jsc.schedule_id
ORDER BY j.name, js.step_id;
SELECT j.name, MAX(h.run_date) last_run_date, SUM(CASE WHEN h.run_status=0 THEN 1 ELSE 0 END) failed_steps_hist, COUNT(*) hist_rows
FROM msdb.dbo.sysjobs j LEFT JOIN msdb.dbo.sysjobhistory h ON h.job_id=j.job_id AND h.step_id=0 GROUP BY j.name;
