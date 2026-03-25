@echo off
chcp 65001 > nul
title LispIM Backend Server

echo ================================
echo   LispIM Enterprise Server
echo   Desktop Application
echo ================================
echo.
echo Starting server...
echo.

cd /d "%~dp0"

REM 设置环境变量
set SBCL_HOME=D:\SBCL\contrib
set QUICKLISP_HOME=%USERPROFILE%\quicklisp

REM 启动 SBCL 加载服务器
start "LispIM Backend" /B "D:\SBCL\sbcl.exe" --core "D:\SBCL\sbcl.core" --load "run-server.lisp"

echo Server is starting in background...
echo.
echo Status:
echo   - Check system tray for SBCL window
echo   - Visit http://localhost:8443/healthz
echo.
echo To stop the server, close the SBCL window
echo or press Ctrl+C in the SBCL console.
echo.
timeout /t 3 /nobreak > nul
exit
