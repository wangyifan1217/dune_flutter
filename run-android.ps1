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
$dartDefines = @()
$localProps = Join-Path $PSScriptRoot "android\local.properties"
if (Test-Path $localProps) {
  foreach ($line in Get-Content $localProps) {
    if ($line -match '^\s*tpns\.accessId=(.+)$') {
      $dartDefines += "--dart-define=TPNS_ACCESS_ID=$($matches[1].Trim())"
    }
    if ($line -match '^\s*tpns\.accessKey=(.+)$') {
      $dartDefines += "--dart-define=TPNS_ACCESS_KEY=$($matches[1].Trim())"
    }
    if ($line -match '^\s*tpns\.miAppId=(.+)$') {
      $dartDefines += "--dart-define=TPNS_MI_APP_ID=$($matches[1].Trim())"
    }
    if ($line -match '^\s*tpns\.miAppKey=(.+)$') {
      $dartDefines += "--dart-define=TPNS_MI_APP_KEY=$($matches[1].Trim())"
    }
    if ($line -match '^\s*tpns\.cluster=(.+)$') {
      $dartDefines += "--dart-define=TPNS_CLUSTER=$($matches[1].Trim())"
    }
    if ($line -match '^\s*dunes\.apiHost=(.+)$') {
      $dartDefines += "--dart-define=DUNES_API_HOST=$($matches[1].Trim())"
    }
    if ($line -match '^\s*nova\.baseUrl=(.+)$') {
      $dartDefines += "--dart-define=NOVA_BASE_URL=$($matches[1].Trim())"
    }
  }
}
Write-Host "PUB_CACHE = $env:PUB_CACHE" -ForegroundColor DarkGray
Write-Host "Launching: device=$Device mode=$mode" -ForegroundColor Cyan

flutter run -d $Device $mode @dartDefines
