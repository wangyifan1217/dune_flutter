#!/usr/bin/env bash
# Nova Build 桌面版启动脚本（macOS / Linux / Git Bash / WSL）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export PATH="${HOME}/.cargo/bin:${HOME}/.grok/bin:${PATH}"

if ! command -v npm >/dev/null 2>&1; then
  echo "未找到 npm，请先安装 Node.js"
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "未找到 cargo，请先安装 Rust（rustup）"
  exit 1
fi

if [[ ! -d node_modules ]]; then
  echo "正在安装依赖…"
  npm install
fi

echo "正在启动 Nova Build 桌面版…"
npm run tauri dev
