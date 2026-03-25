# Check PostgreSQL database encoding

$psql = "D:\PostgreSQL\18\bin\psql.exe"

Write-Host "Checking database encoding..."
& $psql -h 127.0.0.1 -U postgres -d postgres -t -c "SELECT datname, pg_encoding_to_char(encoding) FROM pg_database;"
