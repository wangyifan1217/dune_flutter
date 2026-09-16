Set-Location $PSScriptRoot\..

# 导入 Visual Studio C++ 工具链环境变量（如果 cl.exe 不在 PATH 中）
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    if (Test-Path 'D:\Microsoft\VC\Auxiliary\Build\vcvars64.bat') {
        cmd.exe /c "`"D:\Microsoft\VC\Auxiliary\Build\vcvars64.bat`" && set" | ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
            }
        }
    }
}

$env:PUB_CACHE = "D:\pubcache"
$env:CI = "true"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"

. .\scripts\resolve-dart-defines.ps1
$d = Get-DunesDartDefines
Write-Host "Running flutter run -d windows --debug --no-pub with defines:"
$d | ForEach-Object { Write-Host "  $_" }
flutter run -d windows --debug --no-pub @d
