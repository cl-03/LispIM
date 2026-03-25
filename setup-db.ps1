# 使用 trust 认证连接
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d postgres -c "ALTER DATABASE lispim OWNER TO lispim;"
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d postgres -c "GRANT ALL ON SCHEMA public TO lispim;"
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -c "GRANT ALL ON SCHEMA public TO lispim;"
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U lispim -d lispim -f 'D:\Claude\LispIM\lispim-core\migrations\001-initial-schema.up.sql'
