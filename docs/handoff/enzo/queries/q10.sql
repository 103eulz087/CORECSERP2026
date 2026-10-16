SELECT t.name trg, OBJECT_NAME(t.parent_id) tbl, t.is_disabled, CONVERT(varchar(16),o.modify_date,120) modified,
 STUFF((SELECT ','+te.type_desc FROM sys.trigger_events te WHERE te.object_id=t.object_id FOR XML PATH('')),1,1,'') evts
FROM sys.triggers t JOIN sys.objects o ON o.object_id=t.object_id WHERE t.parent_class=1 ORDER BY tbl;
