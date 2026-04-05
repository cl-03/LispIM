@echo off
REM ========================================
REM LispIM Enterprise Startup Script (Windows)
REM ========================================

setlocal enabledelayedexpansion

echo ========================================
echo   LispIM Enterprise Startup Script
echo ========================================
echo.

REM Configuration
set DATABASE_URL=postgresql://lispim:Clsper03@localhost:5432/lispim
set REDIS_URL=redis://localhost:6379/0
set LISPIM_HOST=0.0.0.0
set LISPIM_PORT=3000
set LOG_LEVEL=info

set SCRIPT_DIR=%~dp0
set PROJECT_DIR=%SCRIPT_DIR:~0,-1%
set LISPIM_CORE_DIR=%PROJECT_DIR%\lispim-core

echo Configuration:
echo   Database: %DATABASE_URL%
echo   Redis: %REDIS_URL%
echo   Host: %LISPIM_HOST%
echo   Port: %LISPIM_PORT%
echo.

REM Check dependencies
echo Checking dependencies...

REM Check SBCL
where sbcl >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] SBCL is not installed
    echo Please install SBCL from: http://www.sbcl.org/platform.html
    echo Or use: choco install sbcl
    pause
    exit /b 1
)
echo   [OK] SBCL: %SBCL_HOME%

REM Check PostgreSQL
where psql >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] PostgreSQL is not installed
    echo Please install PostgreSQL from: https://www.postgresql.org/download/windows/
    echo Or use: choco install postgresql
    pause
    exit /b 1
)
echo   [OK] PostgreSQL installed

REM Check Redis
where redis-cli >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Redis CLI not found. Starting anyway...
) else (
    echo   [OK] Redis installed
)

echo.

REM Main menu
echo Select action:
echo   1. Start Backend Server
echo   2. Start Web Frontend
echo   3. Start All Services
echo   4. Initialize Database
echo   5. Install Lisp Dependencies
echo   6. Stop Server
echo   7. Exit
echo.
set /p action="Enter choice (1-7): "

if "%action%"=="1" goto start_backend
if "%action%"=="2" goto start_frontend
if "%action%"=="3" goto start_all
if "%action%"=="4" goto init_db
if "%action%"=="5" goto install_deps
if "%action%"=="6" goto stop_server
if "%action%"=="7" goto exit
if "%action%"=="" goto exit

echo Invalid choice
pause
exit /b 1

:start_backend
echo.
echo Starting LispIM Backend...
cd /d "%LISPIM_CORE_DIR%"

set SBCL_HOME=%SBCL_HOME%
sbcl --non-interactive ^
     --load src/server.lisp ^
     --eval "(lispim-core:start-server)" ^
     --eval "(loop while lispim-core:*server-running* do (sleep 1))"
goto exit

:start_frontend
echo.
echo Starting Web Frontend...
cd /d "%PROJECT_DIR%\web-client"

where npm >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js/npm is not installed
    echo Please install Node.js from: https://nodejs.org/
    pause
    exit /b 1
)

npm run dev
goto exit

:start_all
echo.
echo Starting all services...
echo.

REM Start backend in new window
echo Starting backend in new window...
start "LispIM Backend" cmd /k "%~f0" 1

REM Wait for backend to start
echo Waiting for backend to start (10 seconds)...
timeout /t 10 /nobreak

REM Start frontend
echo Starting frontend...
start "LispIM Web Frontend" cmd /k "%~f0" 2

echo.
echo All services started!
echo   Backend: http://localhost:3000
echo   Frontend: http://localhost:5173 (Vite dev server)
echo.
pause
goto exit

:init_db
echo.
echo Initializing Database...

set /p pguser="Enter PostgreSQL username [postgres]: " || set pguser=postgres
set /p pgpassword="Enter PostgreSQL password: "

REM Create database
echo Creating database...
psql -U %pguser% -c "CREATE DATABASE lispim;" 2>nul
if %errorlevel% neq 0 (
    echo Database may already exist, continuing...
)

REM Create user
echo Creating user...
psql -U %pguser% -c "CREATE USER lispim WITH PASSWORD 'Clsper03';" 2>nul
if %errorlevel% neq 0 (
    echo User may already exist, continuing...
)

REM Grant privileges
echo Granting privileges...
psql -U %pguser% -c "GRANT ALL PRIVILEGES ON DATABASE lispim TO lispim;"

REM Run migrations
echo Running migrations...
cd /d "%LISPIM_CORE_DIR%"
for %%f in (migrations\*.up.sql) do (
    echo Applying migration: %%f
    psql -U lispim -d lispim -f "%%f"
)

echo.
echo Database initialized successfully!
pause
goto exit

:install_deps
echo.
echo Installing Lisp dependencies...
cd /d "%LISPIM_CORE_DIR%"

REM Check Quicklisp
if not exist "%USERPROFILE%\quicklisp\setup.lisp" (
    echo Installing Quicklisp...
    curl -O https://beta.quicklisp.org/quicklisp.lisp
    sbcl --non-interactive ^
        --load quicklisp.lisp ^
        --eval "(quicklisp-quickstart:install)" ^
        --eval "(ql:add-to-init-file)" ^
        --quit
    del quicklisp.lisp
)

echo Loading Lisp dependencies...
sbcl --non-interactive ^
     --load lispim-core.asd ^
     --eval "(ql:quickload :lispim-core)" ^
     --quit

echo.
echo Dependencies installed successfully!
pause
goto exit

:stop_server
echo.
echo Stopping LispIM server...

taskkill /F /FI "WINDOWTITLE eq LispIM Backend" 2>nul
taskkill /F /FI "IMAGENAME eq sbcl.exe" 2>nul

if %errorlevel% equ 0 (
    echo Server stopped successfully
) else (
    echo No running server found
)

pause
goto exit

:exit
endlocal
exit /b 0
