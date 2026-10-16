SELECT CompanyName FROM dbo.CompanyProfile;
SELECT o.name FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE (m.definition LIKE '%''JFC''%' OR m.definition LIKE '%''ENZO''%') AND o.name NOT LIKE '%[_]OLD[_]%' ORDER BY 1;
