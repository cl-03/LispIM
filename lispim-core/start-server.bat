@echo off
chcp 65001 > nul
title LispIM Backend Server

echo ================================
echo   LispIM Enterprise Server v0.1.0
echo ================================
echo.
echo Press Ctrl+C to stop the server
echo.

cd /d "%~dp0"

REM 启动 SBCL 加载服务器
"D:\SBCL\sbcl.exe" --core "D:\SBCL\sbcl.core" --load "run-server.lisp"
