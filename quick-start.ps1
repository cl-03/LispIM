# LispIM 快速部署脚本 (Windows PowerShell)
# 一键启动 LispIM 开发环境

param(
    [switch]$Init,
    [switch]$Start,
    [switch]$Stop,
    [switch]$Dev,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Colors
$Green = [ConsoleColor]::Green
$Yellow = [ConsoleColor]::Yellow
$Red = [ConsoleColor]::Red

function Write-Info { Write-Host $args -ForegroundColor $Green }
function Write-Warn { Write-Host $args -ForegroundColor $Yellow }
function Write-Error { Write-Host $args -ForegroundColor $Red }

function Show-Banner {
    Write-Host @"
========================================
  LispIM Enterprise Quick Start
========================================
"@
}

function Check-Dependencies {
    Write-Warn "Checking dependencies..."

    # Check SBCL
    if (!(Get-Command sbcl -ErrorAction SilentlyContinue)) {
        Write-Error "SBCL is not installed"
        Write-Host "Please install SBCL:"
        Write-Host "  - Using Chocolatey: choco install sbcl"
        Write-Host "  - Or download from: http://www.sbcl.org/platform.html"
        return $false
    }
    Write-Info "  [OK] SBCL installed"

    # Check PostgreSQL
    if (!(Get-Command psql -ErrorAction SilentlyContinue)) {
        Write-Error "PostgreSQL is not installed"
        Write-Host "Please install PostgreSQL:"
        Write-Host "  - Using Chocolatey: choco install postgresql"
        Write-Host "  - Or download from: https://www.postgresql.org/download/windows/"
        return $false
    }
    Write-Info "  [OK] PostgreSQL installed"

    # Check Redis
    if (!(Get-Command redis-cli -ErrorAction SilentlyContinue)) {
        Write-Warn "  [WARN] Redis CLI not found"
    } else {
        Write-Info "  [OK] Redis installed"
    }

    # Check Node.js
    if (!(Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warn "  [WARN] Node.js/npm not found (required for web frontend)"
    } else {
        Write-Info "  [OK] Node.js installed"
    }

    return $true
}

function Initialize-Database {
    Write-Warn "Initializing database..."

    $pgUser = Read-Host "Enter PostgreSQL username (default: postgres)"
    if ([string]::IsNullOrWhiteSpace($pgUser)) { $pgUser = "postgres" }
    $pgPassword = Read-Host "Enter PostgreSQL password" -AsSecureString
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pgPassword)
    )

    # Set PGPASSWORD environment variable
    $env:PGPASSWORD = $plainPassword

    # Create database
    Write-Host "  Creating database 'lispim'..."
    psql -U $pgUser -h localhost -c "CREATE DATABASE lispim;" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "  Database may already exist"
    }

    # Create user
    Write-Host "  Creating user 'lispim'..."
    psql -U $pgUser -h localhost -c "CREATE USER lispim WITH PASSWORD 'Clsper03';" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "  User may already exist"
    }

    # Grant privileges
    Write-Host "  Granting privileges..."
    psql -U $pgUser -h localhost -c "GRANT ALL PRIVILEGES ON DATABASE lispim TO lispim;"

    # Run migrations
    Write-Host "  Running migrations..."
    $migrationsPath = Join-Path $PSScriptRoot "lispim-core\migrations"
    $migrationFiles = Get-ChildItem -Path $migrationsPath -Filter "*.up.sql" | Sort-Object Name

    foreach ($file in $migrationFiles) {
        Write-Host "    Applying: $($file.Name)"
        psql -U lispim -d lispim -h localhost -f $file.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Error "  Failed to apply migration: $($file.Name)"
            return $false
        }
    }

    Write-Info "  Database initialized successfully!"
    return $true
}

function Install-LispDeps {
    Write-Warn "Installing Lisp dependencies..."

    # Check Quicklisp
    $quicklispPath = Join-Path $env:USERPROFILE "quicklisp\setup.lisp"
    if (!(Test-Path $quicklispPath)) {
        Write-Host "  Installing Quicklisp..."
        $quicklispLisp = Join-Path $PSScriptRoot "quicklisp.lisp"
        Invoke-WebRequest -Uri "https://beta.quicklisp.org/quicklisp.lisp" -OutFile $quicklispLisp

        sbcl --non-interactive `
             --load $quicklispLisp `
             --eval "(quicklisp-quickstart:install)" `
             --eval "(ql:add-to-init-file)" `
             --quit

        Remove-Item $quicklispLisp
    }
    Write-Info "  Quicklisp installed"

    # Load Lisp dependencies
    Write-Host "  Loading Lisp dependencies..."
    $lispimCoreAsd = Join-Path $PSScriptRoot "lispim-core\lispim-core.asd"

    sbcl --non-interactive `
         --load $lispimCoreAsd `
         --eval "(ql:quickload :lispim-core)" `
         --quit

    Write-Info "  Lisp dependencies installed!"
}

function Start-Backend {
    Write-Warn "Starting LispIM Backend..."

    # Set environment variables
    $env:DATABASE_URL = "postgresql://lispim:Clsper03@localhost:5432/lispim"
    $env:REDIS_URL = "redis://localhost:6379/0"
    $env:LISPIM_HOST = "0.0.0.0"
    $env:LISPIM_PORT = "3000"
    $env:LOG_LEVEL = "info"

    $lispimCoreSrc = Join-Path $PSScriptRoot "lispim-core\src\server.lisp"

    Set-Location (Join-Path $PSScriptRoot "lispim-core")

    sbcl --non-interactive `
         --load $lispimCoreSrc `
         --eval "(lispim-core:start-server)" `
         --eval "(loop while lispim-core:*server-running* do (sleep 1))"
}

function Start-Frontend {
    Write-Warn "Starting Web Frontend..."

    Set-Location (Join-Path $PSScriptRoot "web-client")

    if (!(Test-Path "node_modules")) {
        Write-Host "  Installing npm dependencies..."
        npm install
    }

    npm run dev
}

function Stop-Server {
    Write-Warn "Stopping LispIM server..."

    Get-Process | Where-Object { $_.ProcessName -eq "sbcl" } | Stop-Process -Force
    Write-Info "  Server stopped"
}

function Show-Help {
    Write-Host @"

Usage: .\quick-start.ps1 [options]

Options:
  -Init     Initialize database and install dependencies
  -Start    Start backend server
  -Stop     Stop backend server
  -Dev      Start in development mode (REPL)
  -Help     Show this help message

Examples:
  .\quick-start.ps1 -Init     # First time setup
  .\quick-start.ps1 -Start    # Start server
  .\quick-start.ps1 -Stop     # Stop server

"@
}

# Main
Show-Banner

if ($Help) {
    Show-Help
    exit 0
}

if ($Init) {
    if (!(Check-Dependencies)) { exit 1 }
    Initialize-Database
    Install-LispDeps
    exit 0
}

if ($Start) {
    Start-Backend
    exit 0
}

if ($Stop) {
    Stop-Server
    exit 0
}

if ($Dev) {
    Write-Warn "Starting development mode (REPL)..."
    Set-Location (Join-Path $PSScriptRoot "lispim-core")
    sbcl --load lispim-core.asd
    exit 0
}

# Default: Show interactive menu
Write-Host @"

Select action:
  1. Initialize Database & Install Dependencies
  2. Start Backend Server
  3. Start Web Frontend
  4. Stop Server
  5. Exit

"@

$action = Read-Host "Enter choice (1-5)"

switch ($action) {
    "1" {
        if (!(Check-Dependencies)) { exit 1 }
        Initialize-Database
        Install-LispDeps
    }
    "2" { Start-Backend }
    "3" { Start-Frontend }
    "4" { Stop-Server }
    "5" { exit 0 }
    default { Write-Error "Invalid choice" }
}
