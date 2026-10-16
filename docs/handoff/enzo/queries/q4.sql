SELECT o.name, o.type, CONVERT(varchar(10),o.create_date,120) created, CONVERT(varchar(16),o.modify_date,120) modified, LEN(m.definition) len,
 CONVERT(varchar(64),HASHBYTES('SHA2_256', REPLACE(REPLACE(REPLACE(REPLACE(CAST(m.definition AS nvarchar(max)),CHAR(13),''),CHAR(10),''),CHAR(9),''),' ','')),2) h
FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE o.is_ms_shipped=0 ORDER BY o.name;
