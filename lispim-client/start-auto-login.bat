@echo off
REM start-auto-login.bat - Start LispIM Client with Auto Login (Windows)
REM
REM Usage: start-auto-login.bat [username] [password] [host] [port]

setlocal enabledelayedexpansion

cd /d "%~dp0"

REM Default values
set USERNAME=%1
if "%USERNAME%"=="" set USERNAME=admin
set PASSWORD=%2
if "%PASSWORD%"=="" set PASSWORD=password
set HOST=%3
if "%HOST%"=="" set HOST=localhost
set PORT=%4
if "%PORT%"=="" set PORT=3000

echo ========================================
echo   LispIM Auto-Login Client (Windows)
echo ========================================
echo.
echo Server: %HOST%:%PORT%
echo User: %USERNAME%
echo.

sbcl --non-interactive ^
     --load quicklisp.lisp ^
     --eval "(quicklisp:setup)" ^
     --load auto-login-client.lisp ^
     --eval "(setf *username* \"%USERNAME%\")" ^
     --eval "(setf *password* \"%PASSWORD%\")" ^
     --eval "(setf *server-host* \"%HOST%\")" ^
     --eval "(setf *server-port* %PORT%)" ^
     --eval "(auto-connect-and-login)"
