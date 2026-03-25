$env:PGPASSWORD = 'postgres'
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -f 'D:\Claude\LispIM\lispim-core\migrations\001-initial-schema.up.sql'
