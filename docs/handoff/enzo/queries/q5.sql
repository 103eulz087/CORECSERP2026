SELECT OBJECT_NAME(d.referencing_id) src, d.referenced_entity_name ref, ISNULL(o.type,'??') reftype, ISNULL(d.referenced_database_name,'') refdb
FROM sys.sql_expression_dependencies d LEFT JOIN sys.objects o ON o.object_id=d.referenced_id
WHERE d.referencing_class=1 AND OBJECT_NAME(d.referencing_id) IS NOT NULL
GROUP BY OBJECT_NAME(d.referencing_id), d.referenced_entity_name, o.type, d.referenced_database_name ORDER BY 1,2;
