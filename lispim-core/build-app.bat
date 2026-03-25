@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

echo ================================
echo   Building LispIM_backend
echo ================================
echo.

set APP_NAME=LispIM_backend
set BUILD_DIR=build
set SBCL=D:\SBCL\sbcl.exe
set SBCL_CORE=D:\SBCL\sbcl.core

cd /d "%~dp0"

REM 创建构建目录
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

REM 清理旧的编译文件
echo Cleaning old build artifacts...
del /q *.fasl 2>nul
del /q src\*.fasl 2>nul
del /q "%BUILD_DIR%\%APP_NAME%".* 2>nul

echo Compiling executable...
echo.

REM 使用 SBCL 编译可执行文件
"%SBCL%" --non-interactive ^
  --core "%SBCL_CORE%" ^
  --load build-app.lisp ^
  --quit

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ================================
    echo   Build Successful!
    echo ================================
    echo.
    echo Executable location: %BUILD_DIR%\%APP_NAME%.exe
    echo.

    REM 创建启动脚本
    echo Creating launcher script...

    echo @echo off > "%BUILD_DIR%\start-server.bat"
    echo chcp 65001 > nul >> "%BUILD_DIR%\start-server.bat"
    echo cd /d "%%~dp0" >> "%BUILD_DIR%\start-server.bat"
    echo start "%APP_NAME%" "%APP_NAME%.exe" >> "%BUILD_DIR%\start-server.bat"
    echo echo Server starting... >> "%BUILD_DIR%\start-server.bat"
    echo timeout /t 2 /nobreak > nul >> "%BUILD_DIR%\start-server.bat"

    echo.
    echo Launcher script created: %BUILD_DIR%\start-server.bat
    echo.
    echo You can now:
    echo   1. Double-click %BUILD_DIR%\start-server.bat to start the server
    echo   2. Or run %BUILD_DIR%\%APP_NAME%.exe directly
    echo.
) else (
    echo.
    echo ================================
    echo   Build FAILED!
    echo ================================
    echo.
    exit /b 1
)
