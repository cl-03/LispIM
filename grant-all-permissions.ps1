# 授予 lispim 用户所有表的权限
$env:PGPASSWORD = ''
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lispim;"
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lispim;"
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -c "ALTER SCHEMA public OWNER TO lispim;"
# 更改所有表的所有者
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -c "REASSIGN OWNED BY postgres TO lispim;"
