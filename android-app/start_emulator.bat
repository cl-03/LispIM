@echo off
chcp 65001 > nul
title Android Emulator Starter
echo ================================
echo   Android Emulator Starter
echo ================================
echo.
echo Starting Pixel_6_Pro_API_34 emulator...
echo.

cd /d "%~dp0"

REM Kill any existing emulator processes
taskkill /F /IM emulator.exe > nul 2>&1
taskkill /F /IM qemu-system-x86_64.exe > nul 2>&1

REM Restart ADB
"D:\Claude\Android\platform-tools\adb.exe" kill-server
timeout /t 2 /nobreak > nul
"D:\Claude\Android\platform-tools\adb.exe" start-server

REM Start emulator with compatible settings
start "Android Emulator" "D:\Claude\Android\emulator\emulator.exe" -avd Pixel_6_Pro_API_34 -gpu off -no-snapshot-load -accel off -no-boot-anim

echo.
echo Emulator is starting...
echo Wait for it to fully boot before using.
echo.
echo To check device status:
echo   adb devices
echo.
echo To install APK:
echo   adb install -r app-debug.apk
echo.
echo To launch LispIM app:
echo   adb shell am start -n com.lispim.client/.MainActivity
echo.
