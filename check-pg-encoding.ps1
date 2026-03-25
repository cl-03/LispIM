;; check-pg-encoding.ps1
# PowerShell script to check PostgreSQL encoding

$env:PGPASSWORD = "Clsper03"

Write-Host "========================================="
Write-Host "  PostgreSQL Encoding Check"
Write-Host "========================================="
Write-Host ""

# Find psql.exe
$psqlPaths = @(
    "C:\PostgreSQL\*\bin\psql.exe",
    "C:\Program Files\PostgreSQL\*\bin\psql.exe",
    "C:\Program Files (x86)\PostgreSQL\*\bin\psql.exe"
)

$psql = $null
foreach ($path in $psqlPaths) {
    $psql = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($psql) { break }
}

if (-not $psql) {
    # Try using psql from PATH
    $psql = "psql"
    Write-Host "Trying psql from PATH..."
} else {
    Write-Host "Found psql at: $psql"
}

Write-Host ""
Write-Host "Checking database encoding..."
& $psql -h 127.0.0.1 -U lispim -d lispim -t -c "SELECT pg_encoding_to_char(encoding) as encoding FROM pg_database WHERE datname = 'lispim';" 2>&1

Write-Host ""
Write-Host "Checking server encoding..."
& $psql -h 127.0.0.1 -U lispim -d lispim -t -c "SHOW server_encoding;" 2>&1

Write-Host ""
Write-Host "Checking client encoding..."
& $psql -h 127.0.0.1 -U lispim -d lispim -t -c "SHOW client_encoding;" 2>&1

Write-Host ""
Write-Host "Checking LC_COLLATE..."
& $psql -h 127.0.0.1 -U lispim -d lispim -t -c "SHOW lc_collate;" 2>&1

Write-Host ""
Write-Host "Checking LC_CTYPE..."
& $psql -h 127.0.0.1 -U lispim -d lispim -t -c "SHOW lc_ctype;" 2>&1

Write-Host ""
Write-Host "Checking PostgreSQL version..."
& $psql -h 127.0.0.1 -U lispim -d lispim -t -c "SELECT version();" 2>&1
