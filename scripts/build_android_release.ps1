param(
  [string]$ApiHost = "124.221.216.24",
  [string]$PublishBaseUrl = "",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist\android"
$apkName = "dunes_app-release.apk"
$apkOut = Join-Path $dist $apkName

Push-Location $root
try {
  if (-not $SkipBuild) {
    Write-Host "==> flutter pub get"
    flutter pub get
    Write-Host "==> flutter build apk --release --dart-define=DUNES_API_HOST=$ApiHost"
    flutter build apk --release --dart-define=DUNES_API_HOST=$ApiHost
  }

  $built = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
  if (-not (Test-Path $built)) {
    throw "APK not found: $built"
  }

  New-Item -ItemType Directory -Force -Path $dist | Out-Null
  Copy-Item -Force $built $apkOut

  $versionLine = (Get-Content (Join-Path $root "pubspec.yaml") | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1)
  $version = if ($versionLine -match 'version:\s*(.+)') { $Matches[1].Trim() } else { "1.0.0+1" }

  if ([string]::IsNullOrWhiteSpace($PublishBaseUrl)) {
    $PublishBaseUrl = "http://${ApiHost}:6174/app"
  }
  $PublishBaseUrl = $PublishBaseUrl.TrimEnd('/')
  $apkUrl = "$PublishBaseUrl/$apkName"
  $pageUrl = "$PublishBaseUrl/download.html"

  $html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <title>沙丘 App 下载</title>
  <style>
    :root {
      --bg: #f4f7fb;
      --card: #fff;
      --text: #1f2937;
      --muted: #6b7280;
      --primary: #1a6fdb;
      --primary-deep: #0d4a9e;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
      background: linear-gradient(180deg, #e8f1ff 0%, var(--bg) 42%);
      color: var(--text);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px 16px;
    }
    .card {
      width: min(420px, 100%);
      background: var(--card);
      border-radius: 20px;
      box-shadow: 0 18px 50px rgba(15, 23, 42, 0.12);
      padding: 28px 24px 24px;
      text-align: center;
    }
    .logo {
      width: 72px;
      height: 72px;
      border-radius: 18px;
      background: linear-gradient(135deg, var(--primary), var(--primary-deep));
      color: #fff;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 28px;
      font-weight: 700;
      margin-bottom: 14px;
    }
    h1 {
      margin: 0 0 6px;
      font-size: 24px;
    }
    .sub {
      margin: 0 0 20px;
      color: var(--muted);
      font-size: 14px;
      line-height: 1.6;
    }
    .qr-wrap {
      display: inline-block;
      padding: 14px;
      border-radius: 16px;
      background: #fff;
      border: 1px solid #e5e7eb;
      margin-bottom: 16px;
    }
    .qr-wrap img {
      display: block;
      width: 220px;
      height: 220px;
    }
    .hint {
      font-size: 13px;
      color: var(--muted);
      margin-bottom: 18px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      min-width: 220px;
      padding: 12px 18px;
      border: 0;
      border-radius: 12px;
      background: linear-gradient(135deg, var(--primary), var(--primary-deep));
      color: #fff;
      font-size: 16px;
      font-weight: 600;
      text-decoration: none;
      box-shadow: 0 10px 24px rgba(26, 111, 219, 0.28);
    }
    .meta {
      margin-top: 18px;
      font-size: 12px;
      color: var(--muted);
      word-break: break-all;
      line-height: 1.6;
    }
    code {
      background: #f3f4f6;
      padding: 2px 6px;
      border-radius: 6px;
    }
  </style>
</head>
<body>
  <main class="card">
    <div class="logo">丘</div>
    <h1>沙丘 App</h1>
    <p class="sub">统一审批 · 即时通讯 · 云枢助手<br />Android 安装包下载</p>
    <div class="qr-wrap">
      <img id="qr" alt="扫码下载 APK" width="220" height="220" />
    </div>
    <p class="hint">使用手机浏览器扫码，或点击下方按钮直接下载</p>
    <a class="btn" id="download" href="$apkName">下载 Android 安装包</a>
    <div class="meta">
      版本 <code>$version</code><br />
      下载页 <code>$pageUrl</code>
    </div>
  </main>
  <script>
    (function () {
      var apkUrl = new URL('$apkName', window.location.href).href;
      document.getElementById('download').href = apkUrl;
      document.getElementById('qr').src =
        'https://api.qrserver.com/v1/create-qr-code/?size=220x220&margin=8&data=' +
        encodeURIComponent(apkUrl);
    })();
  </script>
</body>
</html>
"@

  $htmlPath = Join-Path $dist "download.html"
  [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))

  $adminApp = Join-Path (Split-Path -Parent $root) "admin-web\public\app"
  if (Test-Path (Split-Path -Parent $root | Join-Path -ChildPath "admin-web")) {
    New-Item -ItemType Directory -Force -Path $adminApp | Out-Null
    Copy-Item -Force $apkOut (Join-Path $adminApp $apkName)
    Copy-Item -Force $htmlPath (Join-Path $adminApp "download.html")
    Write-Host "==> copied to admin-web/public/app/"
  }

  Write-Host ""
  Write-Host "Build complete."
  Write-Host "  APK:  $apkOut"
  Write-Host "  Page: $htmlPath"
  Write-Host "  Scan: $pageUrl"
  Write-Host "  APK URL: $apkUrl"
}
finally {
  Pop-Location
}
