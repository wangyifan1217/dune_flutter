@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "APP_NAME=沙丘"
set "INSTALL_DIR=%LOCALAPPDATA%\Programs\DunesDesktop"
set "ZIP_NAME=dunes-windows-package.zip"
set "EXE_NAME=dunes_app.exe"

echo.
echo  [%APP_NAME%] 正在安装，请稍候...
echo.

if not exist "%~dp0%ZIP_NAME%" (
  echo  [错误] 找不到安装包 %ZIP_NAME%
  pause
  exit /b 1
)

if exist "%INSTALL_DIR%" (
  rmdir /s /q "%INSTALL_DIR%" 2>nul
)
mkdir "%INSTALL_DIR%" 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Expand-Archive -LiteralPath '%~dp0%ZIP_NAME%' -DestinationPath '%INSTALL_DIR%' -Force"

if errorlevel 1 (
  echo  [错误] 解压失败
  pause
  exit /b 1
)

rem 若 zip 内还有一层目录，摊平到 INSTALL_DIR
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root='%INSTALL_DIR%'; $exe=Join-Path $root '%EXE_NAME%'; if (-not (Test-Path $exe)) { $sub=Get-ChildItem $root -Directory | Select-Object -First 1; if ($sub) { Get-ChildItem $sub.FullName -Force | Move-Item -Destination $root -Force; Remove-Item $sub.FullName -Recurse -Force -ErrorAction SilentlyContinue } }"

if not exist "%INSTALL_DIR%\%EXE_NAME%" (
  echo  [错误] 安装后未找到 %EXE_NAME%
  pause
  exit /b 1
)

rem 桌面快捷方式
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws=New-Object -ComObject WScript.Shell; $lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) '%APP_NAME%.lnk'; $s=$ws.CreateShortcut($lnk); $s.TargetPath='%INSTALL_DIR%\%EXE_NAME%'; $s.WorkingDirectory='%INSTALL_DIR%'; $s.Description='%APP_NAME%'; $s.Save()"

rem 开始菜单快捷方式
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dir=Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'; New-Item -ItemType Directory -Force -Path $dir | Out-Null; $ws=New-Object -ComObject WScript.Shell; $lnk=Join-Path $dir '%APP_NAME%.lnk'; $s=$ws.CreateShortcut($lnk); $s.TargetPath='%INSTALL_DIR%\%EXE_NAME%'; $s.WorkingDirectory='%INSTALL_DIR%'; $s.Save()"

echo.
echo  [完成] 已安装到:
echo  %INSTALL_DIR%
echo.
start "" "%INSTALL_DIR%\%EXE_NAME%"
exit /b 0
