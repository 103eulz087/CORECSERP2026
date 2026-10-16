SELECT t.name tbl, c.column_id, c.name col, TYPE_NAME(c.user_type_id) typ, c.max_length, c.precision, c.scale, c.is_nullable, c.is_identity
FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id ORDER BY t.name, c.column_id;
SELECT tt.name tt, c.column_id, c.name col, TYPE_NAME(c.user_type_id) typ, c.max_length, c.precision, c.scale, c.is_nullable
FROM sys.table_types tt JOIN sys.columns c ON c.object_id=tt.type_table_object_id ORDER BY tt.name, c.column_id;
SELECT t.name tbl, SUM(p.rows) rows_ FROM sys.tables t JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1) GROUP BY t.name ORDER BY t.name;
