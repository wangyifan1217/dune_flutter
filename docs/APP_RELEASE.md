# APP 端发版流程（iOS / Android / Windows）

适用仓库：D:\workspace\new_dune_web\flutter

当前项目版本在 pubspec.yaml 中维护。版本格式为 MAJOR.MINOR.PATCH+BUILD，例如 1.7.8+178。每次正式发版都应递增 BUILD；iOS、Android 使用同一应用版本，Windows 安装包脚本中的版本与构建号也要同步。

## 1. 发版前检查

在 Flutter 项目目录执行：

    cd D:\workspace\new_dune_web\flutter
    git status --short --branch
    git diff --check
    git log -1 --oneline

确认目标提交包含要发布的代码、版本号和必要配置。不要把 Android keystore、key.properties、Apple 证书、Provisioning Profile、TPNS 密钥等提交到 Git。

版本更新：

- 修改 pubspec.yaml 的 version，例如 1.7.8+178 改为下一正式版本。
- Android 使用 BUILD 作为 versionCode，发到应用商店的 versionCode 必须高于已发布版本。
- Windows 同步修改 windows/installer/dunes_setup.iss 的 MyAppVersion 和 MyAppBuild。
- 不要更改 Windows 安装脚本里的 AppId，否则安装器会把升级包识别成另一款应用。

## 2. iOS：通过 GitHub Actions

iOS 包由 GitHub Actions 的 macOS runner 构建和签名，本机 Windows 不需要安装 Xcode。

### 2.1 Ad Hoc 测试包

工作流：Flutter iOS Build
文件：.github/workflows/main.yml
触发方式：向 master 分支 push，或在 GitHub Actions 页面手动运行。
产物：Actions run 中名为 DunesAdHocIpa 的 artifact，文件位于 build/ios/ipa/*.ipa。

步骤：

1. 将 iOS 代码和版本号提交并 push 到 master。
2. 打开 GitHub 仓库的 Actions，选择 Flutter iOS Build，等待工作流完成。
3. 打开成功的 run，在 Artifacts 区下载 DunesAdHocIpa。
4. 将 IPA 发给已包含在 Ad Hoc Provisioning Profile 中的测试设备；新设备需先更新设备清单和 profile，再重新构建。

Ad Hoc IPA 是设备限定的内部测试包，不是 TestFlight 包，也不能直接作为 App Store 正式发布包。

### 2.2 TestFlight / App Store 包

工作流：iOS App Store Upload
文件：.github/workflows/ios-appstore.yml
触发方式：GitHub → Actions → iOS App Store Upload → Run workflow。
工作流会构建 App Store 签名的 IPA 并上传到 App Store Connect TestFlight，同时保留名为 DunesAppStoreIpa 的 Actions artifact。

运行前检查 GitHub 仓库 Settings → Secrets and variables → Actions 中已配置工作流所需的 secret。当前工作流引用的名称包括：

- IOS_P12_BASE64、IOS_P12_PASSWORD
- IOS_PROVISION_PROFILE_APPSTORE_BASE64、IOS_TEAM_ID
- APPSTORE_API_PRIVATE_KEY、APPSTORE_ISSUER_ID、APPSTORE_KEY_ID
- TPNS_ACCESS_ID、TPNS_ACCESS_KEY

仅配置 secret 名称与值，不要把证书、私钥或密钥写进仓库、workflow 日志或本文。运行完成后，在 App Store Connect 等待 Apple 处理构建，再分配给 TestFlight 测试人员。正式上架仍需在 App Store Connect 完成版本信息、审核提交和发布操作。

### 2.3 iOS 发版检查

- 确认工作流使用目标分支和正确的版本号。
- 确认本次选用 Ad Hoc 还是 App Store 签名，不能把两类 profile 混用。
- 确认 Actions 全部步骤成功，IPA artifact 存在且大小合理。
- TestFlight 上传成功后，在 App Store Connect 确认构建号、版本和处理状态。

## 3. Android：本机生成 APK / AAB

当前 Flutter 仓库没有 Android GitHub Actions 工作流，Android 正式包在 Windows 构建机上生成。构建机需安装 Flutter、Android SDK、JDK 17 及 Android SDK build-tools。

### 3.1 签名与配置

Android release 使用 android/key.properties 和对应的正式 keystore。该文件及 keystore 已加入忽略规则，不要提交到 Git，也不要通过聊天传递。

当前 Gradle 配置在找不到 android/key.properties 时会退回 debug 签名。因此开始发版前必须确认正式签名文件存在：

    cd D:\workspace\new_dune_web\flutter
    if (!(Test-Path .\android\key.properties)) { throw "缺少 Android release 签名配置，停止发版" }
    if (!(Test-Path .\android\local.properties)) { throw "缺少 Android 本机 SDK/推送配置，停止发版" }

检查配置是否可用时不要在终端、截图或日志中输出密码和密钥。正式 keystore 必须使用与历史发布版本相同的签名身份，否则用户无法覆盖升级。

### 3.2 构建安装 APK

在 PowerShell 中执行：

    Set-Location D:\workspace\new_dune_web\flutter
    $env:PUB_CACHE = "D:\pubcache"
    . .\scripts\resolve-dart-defines.ps1
    $dartDefines = Get-DunesDartDefines -FlutterRoot $PWD
    flutter pub get
    flutter build apk --release @dartDefines

APK 路径：

    build\app\outputs\flutter-apk\app-release.apk

将 APK 用于公司内部分发或设备安装。复制前确认它由正式 keystore 签名，并在测试设备安装、登录和检查推送等本次相关功能。

### 3.3 构建应用商店 AAB

执行：

    flutter build appbundle --release @dartDefines

AAB 路径：

    build\app\outputs\bundle\release\app-release.aab

AAB 用于 Google Play 等应用商店后台上传。上传前核对 applicationId、versionName、versionCode，并验证签名。APK 和 AAB 必须使用正式签名配置。

可使用 Android SDK 的 apksigner 检查 APK 签名：

    apksigner verify --print-certs .\build\app\outputs\flutter-apk\app-release.apk

检查证书指纹是否与公司保管的正式发布证书一致。不要只根据构建成功判断签名正确。

AAB 可用 JDK 自带工具检查签名与证书信息：

    jarsigner -verify -verbose -certs .\build\app\outputs\bundle\release\app-release.aab
    keytool -printcert -jarfile .\build\app\outputs\bundle\release\app-release.aab

核对证书指纹与公司保管的正式发布证书一致。

## 4. Windows：构建桌面程序并生成 EXE 安装包

Windows 包在安装了 Flutter Windows desktop 工具链、Visual Studio C++ Desktop workload 和 Inno Setup 6 的 Windows 构建机上制作。

### 4.1 构建 Flutter Windows Release

确认 pubspec.yaml 与 Inno Setup 脚本中的版本号、构建号一致，然后执行：

    Set-Location D:\workspace\new_dune_web\flutter
    $env:PUB_CACHE = "D:\pubcache"
    . .\scripts\resolve-dart-defines.ps1
    $dartDefines = Get-DunesDartDefines -FlutterRoot $PWD
    flutter pub get
    flutter build windows --release @dartDefines

Flutter 输出目录：

    build\windows\x64\runner\Release

### 4.2 打包 EXE 安装器

使用仓库内的 Windows 安装脚本：

    windows\installer\dunes_setup.iss

默认 Inno Setup 6 编译器路径如下；如安装位置不同，调整 ISCC 变量：

    $ISCC = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (!(Test-Path $ISCC)) { throw "找不到 Inno Setup 6 编译器" }
    & $ISCC ".\windows\installer\dunes_setup.iss"
    if ($LASTEXITCODE -ne 0) { throw "Windows 安装包构建失败" }

安装器输出到：

    build\installer\DunesSetup-<MyAppVersion>-<MyAppBuild>.exe

例如当前脚本版本为 1.7.8 和 178 时，文件名为 DunesSetup-1.7.8-178.exe。正式发版前先在未安装开发环境的 Windows 10/11 机器上安装、启动，并验证覆盖安装旧版本可用。保持 AppId 不变。

构建完成后复制到交付目录，目标文件已存在时不要覆盖，先更新版本或构建号：

    $version = "1.7.8"
    $build = "178"
    $source = ".\build\installer\DunesSetup-$version-$build.exe"
    $targetDir = ".\dist\windows"
    $target = Join-Path $targetDir "DunesSetup-$version-$build.exe"
    if (Test-Path $target) { throw "目标安装包已存在，请递增版本或构建号" }
    New-Item -ItemType Directory -Force $targetDir | Out-Null
    Copy-Item $source $target
    Get-FileHash $target -Algorithm SHA256

将版本示例替换为 pubspec.yaml 与 dunes_setup.iss 中本次实际的版本。dist/windows 属于交付产物目录，不要把签名文件或本地配置一起打包进 Git。

## 5. 发布与交付确认

- iOS Ad Hoc：确认测试设备已登记，下载 DunesAdHocIpa。
- iOS TestFlight：确认 App Store Connect 已接收构建，再安排内部测试。
- Android：根据发布渠道交付正式签名 APK，或将正式签名 AAB 上传到应用商店。
- Windows：交付 DunesSetup-版本-构建号.exe，并同时提供 SHA-256。
- 记录 Git commit、应用版本、构建号、包类型、构建结果和交付位置。
- 安装包只通过公司批准的应用商店、内部文件服务或设备管理渠道分发，不通过 Git 提交二进制包。

## 6. 常见问题

- Android 安装时提示签名冲突：检查是否使用了历史正式 keystore；不能用 debug keystore 覆盖已安装的正式版本。
- Android 商店拒绝版本：检查 versionCode 是否高于已上传版本，并确认 applicationId 正确。
- iOS 找不到可安装设备：确认 Ad Hoc profile 包含设备 UDID；App Store profile 应通过 TestFlight 分发。
- Windows 安装器没有包含最新改动：先确认 Flutter Release 构建成功，再重新用 Inno Setup 编译 .iss。
- 缺少签名文件、GitHub secret、推送配置或构建工具时，停止发版并从授权凭据渠道补齐；不要用空值或开发密钥顶替正式配置。
