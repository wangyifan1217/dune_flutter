<#
  启动安卓调试（PowerShell）
  用法：
    .\run-android.ps1                # 自动选择第一台安卓真机/模拟器
    .\run-android.ps1 253408e4       # 指定设备 id
    .\run-android.ps1 -Release       # 以 release 模式运行

  说明：本机 pub cache 默认路径含中文，会导致 jni 等插件的原生(CMake/Ninja)构建失败，
  这里强制把 PUB_CACHE 指到纯英文路径 D:\pubcache 规避该问题。
#>
param(
  [string]$Device = "",
  [switch]$Release
)

$ErrorActionPreference = "Stop"

# 关键：英文 pub cache 路径，避免原生构建因中文路径失败
$env:PUB_CACHE = "D:\pubcache"

# 切到脚本所在目录（Flutter 工程根，含 pubspec.yaml）
Set-Location -Path $PSScriptRoot

# 未指定设备时，自动挑选一台非 web 的设备
if (-not $Device) {
  $json = flutter devices --machine | Out-String
  try {
    $devices = $json | ConvertFrom-Json
    $picked = $devices | Where-Object { $_.targetPlatform -like "android*" } | Select-Object -First 1
    if (-not $picked) {
      $picked = $devices | Where-Object { $_.id -ne "chrome" -and $_.id -ne "web-server" } | Select-Object -First 1
    }
    if ($picked) { $Device = $picked.id }
  } catch {}
}

if (-not $Device) {
  Write-Host "未找到可用设备，请先连接安卓设备或启动模拟器。" -ForegroundColor Red
  flutter devices
  exit 1
}

$mode = if ($Release) { "--release" } else { "--debug" }
Write-Host "PUB_CACHE = $env:PUB_CACHE" -ForegroundColor DarkGray
Write-Host "启动调试：设备=$Device 模式=$mode" -ForegroundColor Cyan

flutter run -d $Device $mode
