@echo off
REM ===========================================
REM LispIM 开发环境停止脚本 (Windows)
REM ===========================================

echo ========================================
echo   LispIM Enterprise - 停止所有服务
echo ========================================
echo.

echo [1/2] 停止 Docker 服务...
docker-compose down

echo.
echo [2/2] 清理 SBCL 进程...
taskkill /F /IM sbcl.exe >nul 2>nul
taskkill /F /IM sbcl-bin.exe >nul 2>nul

echo.
echo ========================================
echo   所有服务已停止
echo ========================================

pause
