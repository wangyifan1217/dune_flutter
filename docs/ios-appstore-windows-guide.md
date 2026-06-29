# 沙丘X · iOS 上架指南（Windows 全程无 Mac）

本文档面向 **Windows 开发机**，通过 **GitHub Actions 云端 Mac** 完成 App Store / TestFlight 打包与上传。内测分发（蒲公英 Ad Hoc）与正式上架并行，互不影响。

---

## 一、环境与账号前置

| 项 | 值 / 说明 |
|---|---|
| App 商店名称 | **沙丘X** |
| 桌面显示名 | **沙丘X**（`Info.plist` / `AndroidManifest`） |
| iOS Bundle ID | `nova.dunes.dunes-app` |
| Android applicationId | `nova.dunes.dunes_app` |
| Apple Team ID | `U8443M3MV7` |
| GitHub 仓库 | `https://github.com/wangyifan1217/dune_flutter` |
| 生产 API | `http://124.221.216.24:6090/api/v1`（`dunes_defaults.dart`） |

需要准备：

- [ ] 付费 **Apple Developer** 账号
- [ ] **App Store Connect** 已创建 App「沙丘X」
- [ ] **Distribution P12** 证书（Ad Hoc 与 App Store 可共用）
- [ ] **GitHub Actions** 账单正常（`macos-26` 需付费分钟，见文末）

---

## 二、两条 CI 流水线（不要搞混）

| Workflow | 文件 | 触发方式 | 产物 | 用途 |
|----------|------|----------|------|------|
| **Flutter iOS Build** | `.github/workflows/main.yml` | push `master` 或手动 | `DunesAdHocIpa` | **蒲公英内测**（Ad Hoc） |
| **iOS App Store Upload** | `.github/workflows/ios-appstore.yml` | **仅手动 Run workflow** | 上传 TestFlight + `DunesAppStoreIpa` | **App Store 上架** |

> Ad Hoc 包 **不能** 上传 App Store。上架必须跑 **iOS App Store Upload**。

手动触发上架：

1. GitHub → **Actions**
2. 左侧 **All workflows** → **iOS App Store Upload**
3. 或直接打开：`https://github.com/wangyifan1217/dune_flutter/actions/workflows/ios-appstore.yml`
4. **Run workflow** → 分支 `master` → **Run workflow**

---

## 三、Apple Developer：证书与描述文件

### 3.1 描述文件（两套，名称不同）

| 类型 | 名称（必须一致） | 用途 | GitHub Secret |
|------|------------------|------|---------------|
| Ad Hoc | `Nova-Dunes-AdHoc` | 蒲公英内测 | `IOS_PROVISION_PROFILE_BASE64` |
| App Store | `Nova-Dunes-AppStore` | TestFlight / 上架 | `IOS_PROVISION_PROFILE_APPSTORE_BASE64` |

创建 App Store 描述文件：

1. [developer.apple.com](https://developer.apple.com) → **Certificates, Identifiers & Profiles**
2. **Profiles** → **+** → **App Store Connect**
3. App ID：`nova.dunes.dunes-app`
4. 证书：**Apple Distribution**（与 Ad Hoc 同一 P12 即可）
5. 名称填：**`Nova-Dunes-AppStore`**（不是「沙丘X」，那是给用户看的 App 名）
6. 下载 `.mobileprovision`

### 3.2 Windows 转 Base64（PowerShell）

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\路径\NovaDunesAppStore.mobileprovision")) `
  | Set-Content -Encoding ASCII "C:\路径\NovaDunesAppStore.mobileprovision.base64.txt"
```

将 `.base64.txt` **整文件内容**（单行）粘贴到 GitHub Secret，不要换行。

---

## 四、App Store Connect API 密钥

用于 CI 自动上传 IPA（Windows 无法用 Transporter）。

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **用户和访问** → **集成** → **App Store Connect API**
2. **生成 API 密钥**（权限：**App 管理** 或 **Developer**）
3. 记录页面顶部 **Issuer ID**（UUID 格式）
4. 记录密钥 **Key ID**
5. 下载 **`.p8` 文件**（只下载一次，丢失需重建）

| GitHub Secret | 内容 |
|---------------|------|
| `APPSTORE_ISSUER_ID` | Issuer ID |
| `APPSTORE_KEY_ID` | Key ID |
| `APPSTORE_API_PRIVATE_KEY` | `.p8` 文件全文（含 BEGIN/END 行） |

---

## 五、GitHub Secrets 完整清单

在仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret | 说明 | 上架必填 |
|--------|------|----------|
| `IOS_P12_BASE64` | Distribution 证书 | ✅ |
| `IOS_P12_PASSWORD` | P12 密码 | ✅ |
| `IOS_TEAM_ID` | `U8443M3MV7` | ✅ |
| `IOS_PROVISION_PROFILE_BASE64` | Ad Hoc 描述文件 | 内测用 |
| `IOS_PROVISION_PROFILE_APPSTORE_BASE64` | App Store 描述文件 | ✅ |
| `TPNS_ACCESS_ID` | iOS TPNS AccessID | ✅ |
| `TPNS_ACCESS_KEY` | iOS TPNS AccessKey | ✅ |
| `APPSTORE_ISSUER_ID` | Connect API | ✅ |
| `APPSTORE_KEY_ID` | Connect API | ✅ |
| `APPSTORE_API_PRIVATE_KEY` | Connect API `.p8` | ✅ |

---

## 六、Xcode 26 / macOS 26 要求（重要）

自 **2026 年起**，上传 App Store Connect 要求使用 **iOS 26 SDK（Xcode 26+）** 构建。

若上传报错：

```text
This app was built with the iOS 18.5 SDK. All iOS apps must be built with the iOS 26 SDK or later...
```

说明 CI 跑在了旧镜像上。`ios-appstore.yml` 已配置：

- `runs-on: macos-26`
- 构建前 **Select Xcode 26**

**仅 App Store workflow 需要 macos-26**；蒲公英 Ad Hoc 仍可用 `macos-latest`。

---

## 七、Connect 商店资料（浏览器填写）

### 7.1 创建 App（若未完成）

- 名称：**沙丘X**
- Bundle ID：`nova.dunes.dunes-app`
- SKU：如 `dunes-ios-2026`（内部编号，用户不可见）

### 7.2 副标题

```
企业审批与即时通讯
```

### 7.3 描述（可直接粘贴）

```
沙丘X 是一款面向企业的统一办公协作应用，将即时通讯、审批流转与智能助手整合在同一平台，帮助团队高效沟通、及时处理待办。

【即时通讯】
支持单聊、群聊与 @ 提醒，消息实时同步，方便日常协作与项目沟通。

【统一审批】
集中处理各类业务与行政审批，随时查看待办、已办与发起记录，流程进度一目了然。

【沙丘助手 NOVA】
内置 AI 助手，可辅助问答、写汇报、整理会议纪要等，提升日常办公效率。

【工作台】
个人中心整合通知、待办与常用入口，重要事项不再遗漏。

【更多能力】
支持消息推送、全局搜索、知识库等，满足企业日常办公场景。

沙丘X 面向已开通账号的企业用户使用，需使用手机号验证登录。如有问题，请联系您所在企业的系统管理员。
```

### 7.4 关键词

```
审批,办公,IM,企业,协作,待办,聊天,沙丘X
```

### 7.5 截图（仅 6.3 寸真机也可）

1. Connect 若有 **6.3 英寸** 栏 → 直接上传真机截图（约 1206×2622）
2. 若只有 **6.5 英寸** → 批量缩放到 **1284×2778** 后上传
3. 至少 **3 张**，建议 5 张：登录、通讯、聊天、审批、我的

### 7.6 必填侧栏项

| 菜单 | 内容 |
|------|------|
| **App 隐私** | 隐私问卷（手机号、聊天等） |
| **定价与销售范围** | 免费 + 销售地区 |
| **App 审核** | 测试手机号、登录步骤说明、联系电话 |

审核备注示例：

```text
登录方式：手机号 + 短信验证码
测试手机号：138xxxxxxxx
操作：打开 App → 输入手机号 → 获取验证码 → 登录
核心功能：底部「通讯」IM；「我的」审批待办
```

---

## 八、上架操作流程（Windows 逐步）

```
① 配齐 GitHub Secrets（第五节）
        ↓
② Actions → iOS App Store Upload → Run workflow
        ↓
③ 等待绿勾（约 10～20 分钟）
        ↓
④ Connect → TestFlight → 等待构建「处理完成」
        ↓
⑤ 分发 → 沙丘X → 1.0 → 构建版本 → 选择刚上传的包
        ↓
⑥ 填截图、描述、隐私、审核信息
        ↓
⑦ 添加以供审核
```

### 8.1 TestFlight 构建状态

```
处理中 → 正在处理 → 缺少出口合规信息 → 可测试
```

**出口合规**：一般选 **否**（仅 HTTPS，无自研加密）。

### 8.2 构建版本选不了时

- 构建仍在处理中 → 再等 5～30 分钟
- 未跑 App Store Upload → 重跑 CI
- 出口合规未填 → 在 TestFlight 里先填

---

## 九、桌面 App 名称 vs 描述文件名称

| 名称 | 填什么 | 用户能否看到 |
|------|--------|--------------|
| 手机桌面图标下 | **沙丘X** | ✅ |
| App Store 商店页 | **沙丘X** | ✅ |
| 描述文件 Profile 名 | `Nova-Dunes-AppStore` | ❌ 仅开发用 |

修改桌面名后需 **重新安装** 新包才生效。配置文件：

- iOS：`ios/Runner/Info.plist` → `CFBundleDisplayName`
- Android：`android/app/src/main/AndroidManifest.xml` → `android:label`

---

## 十、推送与后端（联调参考）

| 项 | 说明 |
|----|------|
| iOS TPNS | 控制台 Bundle ID `nova.dunes.dunes-app`，生产 APNs |
| 后端 | `flow-go` iOS 推送使用 `badge_type` + `custom_content` |
| 单设备 token | 用户登录新平台会 deactivate 旧平台 token，只保留最后登录设备 |

---

## 十一、常见问题

### GitHub Actions 未启动 / 账单错误

```text
recent account payments have failed or your spending limit needs to be increased
```

→ **Settings → Billing and plans**，检查付款与 Actions 消费上限。

### 看不到「iOS App Store Upload」

1. 确认在 **GitHub** 仓库（非 Gitee）
2. Actions → **All workflows**
3. 确认 `master` 分支存在 `.github/workflows/ios-appstore.yml`

### 上传 409 SDK 版本错误

→ 确认 `ios-appstore.yml` 使用 `macos-26` 且日志中 `xcodebuild -version` 为 **Xcode 26.x**。

### API 上传 401

→ 检查 Issuer ID、Key ID、`.p8` 是否完整；密钥权限是否足够。

### Ad Hoc 与 App Store 区别

| | Ad Hoc | App Store |
|---|--------|-----------|
| 描述文件 | Nova-Dunes-AdHoc | Nova-Dunes-AppStore |
| ExportOptions | `ExportOptions.adhoc.plist` | `ExportOptions.appstore.plist` |
| 安装方式 | 蒲公英链接 | TestFlight / App Store |

---

## 十二、相关仓库文件

| 路径 | 说明 |
|------|------|
| `.github/workflows/ios-appstore.yml` | App Store 打包 + 上传 TestFlight |
| `.github/workflows/main.yml` | Ad Hoc 蒲公英内测 |
| `ios/ExportOptions.appstore.plist` | App Store 导出配置 |
| `ios/ExportOptions.adhoc.plist` | Ad Hoc 导出配置 |
| `ios/Runner/Info.plist` | iOS 桌面显示名 |
| `android/app/src/main/AndroidManifest.xml` | Android 桌面显示名 |

---

## 十三、检查清单（提交审核前）

- [ ] `iOS App Store Upload` CI 绿勾
- [ ] TestFlight 构建处理完成
- [ ] 版本页已选择构建
- [ ] 截图 ≥ 3 张
- [ ] 描述、关键词、副标题已填
- [ ] App 隐私问卷完成
- [ ] 定价（免费）与销售地区已设
- [ ] 审核测试账号与说明已填
- [ ] 出口合规已答

全部完成后 → **添加以供审核** → 等待 1～3 个工作日。

---

*文档版本：2026-06-29 · 适用仓库 `dune_flutter` / 沙丘X iOS 上架*
