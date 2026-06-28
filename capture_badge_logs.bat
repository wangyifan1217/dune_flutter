@echo off
REM 先打开 APP 并操作（收消息/进会话），再运行本脚本
adb logcat -d -t 2000 > "%TEMP%\dunes_badge_log.txt"
findstr /i "Badge BadgeAPI Push DunesBadge DunesTpns ClassCast flutter" "%TEMP%\dunes_badge_log.txt"
echo.
echo 完整日志: %TEMP%\dunes_badge_log.txt
pause
