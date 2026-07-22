@echo off
REM Nova Build 桌面版启动（双击即可）
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
pause
