<#
  Launch Android debugging (PowerShell)
  Usage:
    .\run-android.ps1                # auto-pick first Android device/emulator
    .\run-android.ps1 253408e4       # target a specific device id
    .\run-android.ps1 -Release       # run in release mode

  Note: the default pub cache path contains non-ASCII chars (Chinese username),
  which breaks native (CMake/Ninja) builds of plugins like jni. We force
  PUB_CACHE to a pure-ASCII path (D:\pubcache) to avoid that.
#>
param(
  [string]$Device = "",
  [switch]$Release
)

$ErrorActionPreference = "Stop"

# Key: ASCII-only pub cache path, avoids native build failures on non-ASCII paths
$env:PUB_CACHE = "D:\pubcache"

# jpush_flutter 3.4.6 still references jcenter(), which Gradle 9+ removed.
$jpushGradle = Join-Path $env:PUB_CACHE "hosted\pub.dev\jpush_flutter-3.4.6\android\build.gradle"
if (Test-Path $jpushGradle) {
  $content = Get-Content $jpushGradle -Raw
  if ($content -match 'jcenter\(\)') {
    $content = $content -replace '\s*jcenter\(\)\r?\n', ''
    Set-Content -Path $jpushGradle -Value $content -NoNewline
    Write-Host "Patched jpush_flutter build.gradle (removed jcenter)" -ForegroundColor DarkGray
  }
}

# Move to the script dir (Flutter project root, contains pubspec.yaml)
Set-Location -Path $PSScriptRoot

# When no device is given, auto-pick a non-web device
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
  Write-Host "No usable device found. Connect an Android device or start an emulator first." -ForegroundColor Red
  flutter devices
  exit 1
}

$mode = if ($Release) { "--release" } else { "--debug" }
Write-Host "PUB_CACHE = $env:PUB_CACHE" -ForegroundColor DarkGray
Write-Host "Launching: device=$Device mode=$mode" -ForegroundColor Cyan

flutter run -d $Device $mode
