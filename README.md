# Nova Build Desktop

Cross-platform desktop shell for [Nova Build](https://github.com/xai-org/nova-build), built with **Tauri 2** and **React**. It connects to the official `nova` CLI over **ACP** (`nova agent stdio`) and provides a Codex-style workspace UI on **macOS** and **Windows**.

## Architecture

```text
React UI (chat + explorer)
        │
        ▼
Tauri commands / events
        │
        ▼
ACP client (Rust, JSON-RPC over stdio)
        │
        ▼
nova agent stdio   ← official Nova Build binary
```

## Prerequisites

1. **Node.js 20+**
2. **Rust** (via [rustup](https://rustup.rs/))
3. **Platform tools**
   - macOS: Xcode Command Line Tools
   - Windows: [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) + WebView2
4. **Nova Build CLI** installed and authenticated:

```powershell
# Windows
irm https://x.ai/cli/install.ps1 | iex
nova --version
```

```bash
# macOS / Linux
curl -fsSL https://x.ai/cli/install.sh | bash
nova --version
```

Optional: set `XAI_API_KEY` if you use API-key auth.

## Development

```bash
npm install
npm run tauri dev
```

## Build installers

```bash
npm run tauri build
```

Artifacts are written under `src-tauri/target/release/bundle/`.

### macOS via GitHub Actions

Manual workflow: [`.github/workflows/macos-dmg.yml`](.github/workflows/macos-dmg.yml)（与 Flutter 项目同一套 Apple secrets）。

在仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret | 说明 |
|--------|------|
| `MACOS_CERTIFICATE_BASE64` | Developer ID Application 的 `.p12` base64 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `MACOS_SIGNING_IDENTITY` | 如 `Developer ID Application: Your Company (TEAMID)` |
| `APPSTORE_ISSUER_ID` | App Store Connect API Issuer ID（可与 iOS 共用） |
| `APPSTORE_KEY_ID` | API Key ID |
| `APPSTORE_API_PRIVATE_KEY` | `.p8` 原文或 base64 |

Actions 页手动运行 **macOS DMG (Developer ID)**，产物为 arm64 / x64 两个 DMG artifact。

流水线会按架构从官方源下载 Grok CLI 并打入 `.app`（与 Windows 内置 `grok.exe` 同思路），用户无需再执行 `curl … | bash`。

## How it works

1. Open a workspace folder in the app.
2. The backend spawns `nova agent stdio` in that directory.
3. Rust implements an ACP **client**:
   - sends `initialize`, `session/new`, `session/prompt`
   - handles `session/update` streaming events
   - serves `fs/read_text_file` and `fs/write_text_file`
4. The React UI renders chat output and a lightweight file tree.

## Settings

Stored in the Tauri store plugin:

- `novaCommand` — default `nova` / `nova.exe`
- `novaArgs` — default `agent stdio`
- `autoApprovePermissions` — MVP auto-allow for tool permissions

## Roadmap

- [ ] Permission modal instead of auto-approve
- [ ] Inline diff viewer for file edits
- [ ] Terminal panel (ACP `terminal/*`)
- [ ] Session list / resume
- [x] macOS code signing + notarization (GitHub Actions)
- [ ] Windows installer polish

## License

Application code in this repo: MIT (add your own LICENSE if needed).

Nova Build upstream is Apache-2.0 — retain upstream notices if you redistribute derived agent components.

## Trademark

This project is an independent desktop client. It is not affiliated with xAI / SpaceXAI. Do not use Nova branding in public releases without complying with Apache-2.0 attribution rules and trademark law.
