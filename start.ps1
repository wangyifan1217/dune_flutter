# Nova Build 桌面版启动脚本（Windows PowerShell）
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$env:Path = "$env:USERPROFILE\.cargo\bin;$env:USERPROFILE\.grok\bin;" + $env:Path

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  Write-Host "未找到 npm，请先安装 Node.js"
  exit 1
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  Write-Host "未找到 cargo，请先安装 Rust（rustup）"
  exit 1
}

if (-not (Test-Path "node_modules")) {
  Write-Host "正在安装依赖…"
  npm install
}

Write-Host "正在启动 Nova Build 桌面版…"
npm run tauri dev
