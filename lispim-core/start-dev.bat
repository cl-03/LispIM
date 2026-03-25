@echo off
REM ===========================================
REM LispIM 开发环境启动脚本 (Windows)
REM ===========================================

echo ========================================
echo   LispIM Enterprise - 开发环境启动
echo ========================================
echo.

REM 设置编码
chcp 65001 >nul

REM 检查 Docker 是否安装
where docker >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [错误] 未检测到 Docker，请先安装 Docker Desktop
    echo 下载地址：https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

echo [1/5] 启动 Docker 服务...
docker-compose up -d

if %ERRORLEVEL% NEQ 0 (
    echo [错误] Docker 服务启动失败
    pause
    exit /b 1
)

echo [2/5] 等待服务启动...
timeout /t 10 /nobreak >nul

echo [3/5] 检查服务状态...
docker ps --filter "name=lispim-" --format "table {{.Names}}\t{{.Status}}"

echo.
echo [4/5] 启动 LispIM 服务器...
echo.
echo 正在加载 SBCL 和 LispIM 系统...
echo 这可能需要几分钟时间...
echo.

REM 启动 SBCL 服务器
start "LispIM Server" sbcl --non-interactive ^
    --load "lispim-backend-app.lisp" ^
    --eval "(lispim-backend-app:main)"

echo [5/5] 等待服务器启动...
timeout /t 15 /nobreak >nul

echo.
echo ========================================
echo   服务已启动！
echo ========================================
echo.
echo LispIM 服务器：http://localhost:4321
echo.
echo 开发工具:
echo   - MailHog (邮件测试):    http://localhost:8025
echo   - MinIO Console (存储):  http://localhost:9001
echo   - Adminer (数据库):      http://localhost:8080
echo   - Redis Commander:       http://localhost:8081
echo.
echo 按 Ctrl+C 停止查看日志，窗口保持运行
echo 关闭此窗口不会停止服务
echo.
echo 停止所有服务命令：docker-compose down
echo ========================================
echo.

REM 打开浏览器
start http://localhost:4321
start http://localhost:8025

REM 保持窗口打开
pause
