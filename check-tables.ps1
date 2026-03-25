# 检查表是否存在
$env:PGPASSWORD = ''
& 'D:\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d lispim -c "\dt"
