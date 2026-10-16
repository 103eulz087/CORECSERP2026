SELECT o.name proc_, STUFF((SELECT ', '+p.name+' '+TYPE_NAME(p.user_type_id)+CASE WHEN p.has_default_value=1 OR p.is_output=1 THEN '' ELSE '' END+CASE WHEN p.is_output=1 THEN ' OUT' ELSE '' END
 FROM sys.parameters p WHERE p.object_id=o.object_id ORDER BY p.parameter_id FOR XML PATH('')),1,2,'') params
FROM sys.procedures o ORDER BY o.name;
