# 沙丘 App — Chrome 调试启动
# 解决 flutter pub get / flutter run 长时间无输出卡死的问题
$ErrorActionPreference = 'SilentlyContinue'

Write-Host ">>> 1/4 结束卡住的 Dart/Flutter 进程..."
Get-Process -Name dart, dartvm, flutter -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

Write-Host ">>> 2/4 清理 Flutter SDK 锁文件..."
Remove-Item -Force -ErrorAction SilentlyContinue @(
  "$env:FLUTTER_ROOT\bin\cache\flutter.bat.lock"
  "$env:FLUTTER_ROOT\bin\cache\lockfile"
  "C:\flutter\bin\cache\flutter.bat.lock"
  "C:\flutter\bin\cache\lockfile"
)
Remove-Item -Force -ErrorAction SilentlyContinue @(
  "$PSScriptRoot\.dart_tool\hooks_runner\objective_c\*\*.lock"
  "$PSScriptRoot\.dart_tool\hooks_runner\shared\objective_c\.lock"
)

Write-Host ">>> 3/4 设置环境变量（避免启动卡死 / 避免 pub 镜像握手失败）..."
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:GIT_TERMINAL_PROMPT = '0'
Remove-Item Env:PUB_HOSTED_URL -ErrorAction SilentlyContinue
Remove-Item Env:FLUTTER_STORAGE_BASE_URL -ErrorAction SilentlyContinue

Set-Location $PSScriptRoot

if (-not (Test-Path "$PSScriptRoot\pubspec.lock")) {
  Write-Host "错误: 缺少 pubspec.lock" -ForegroundColor Red
  exit 1
}

Write-Host ">>> 4/4 离线校验依赖并启动 Chrome..."
dart pub get --offline --enforce-lockfile
if ($LASTEXITCODE -ne 0) {
  Write-Host "离线依赖校验失败，请检查网络后执行: flutter pub get" -ForegroundColor Yellow
  exit $LASTEXITCODE
}

Write-Host "    首次编译约 30–60 秒，出现 Launching... 后请等待 Chrome 打开..."
flutter run -d chrome --no-pub
