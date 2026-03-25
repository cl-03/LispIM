@echo off
REM LispIM Server Startup Script for Windows
REM Configuration

set DATABASE_URL=postgresql://lispim:Clsper03@127.0.0.1:5432/lispim
set REDIS_URL=redis://127.0.0.1:6379/0
set LOG_LEVEL=info

echo ========================================
echo   LispIM Enterprise Server v0.1.0
echo ========================================

cd /d D:\Claude\LispIM\lispim-core

echo Loading LispIM server...
"D:\SBCL\sbcl.exe" --non-interactive ^
    --load "src/server.lisp" ^
    --eval "(lispim-core:start-server)" ^
    --eval "(loop while lispim-core:*server-running* do (sleep 1))"
