@echo off
REM ===========================================
REM LispIM 环境检查脚本
REM ===========================================

echo ========================================
echo   LispIM - 环境检查
echo ========================================
echo.

REM 检查 Docker
echo [检查] Docker...
where docker >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] Docker 已安装
    docker --version
) else (
    echo [未安装] Docker 未找到
    echo 请安装 Docker Desktop: https://www.docker.com/products/docker-desktop/
)
echo.

REM 检查 Docker Compose
echo [检查] Docker Compose...
where docker-compose >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] Docker Compose 已安装
    docker-compose --version
) else (
    echo [注意] Docker Compose 未找到
    echo Docker Desktop 通常包含 Docker Compose
)
echo.

REM 检查 SBCL
echo [检查] SBCL...
where sbcl >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [OK] SBCL 已安装
    sbcl --version | findstr "SBCL"
) else (
    echo [未安装] SBCL 未找到
    echo 请安装 SBCL: http://www.sbcl.org/
)
echo.

REM 检查端口占用
echo [检查] 端口占用...
echo PostgreSQL (5432):
netstat -ano | findstr :5432 || echo   未占用
echo Redis (6379):
netstat -ano | findstr :6379 || echo   未占用
echo LispIM (4321):
netstat -ano | findstr :4321 || echo   未占用
echo.

REM 检查 Docker 服务状态
echo [检查] Docker 服务状态...
docker-compose ps 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo Docker 服务未运行
)
echo.

echo ========================================
echo 检查完成
echo ========================================

pause
