Set-Location $PSScriptRoot\..

$env:PUB_CACHE = "D:\pubcache"
$env:CI = "true"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"

. .\scripts\resolve-dart-defines.ps1
$d = Get-DunesDartDefines
Write-Host "Running flutter run -d chrome --no-pub with defines:"
$d | ForEach-Object { Write-Host "  $_" }
flutter run -d chrome --no-pub @d
