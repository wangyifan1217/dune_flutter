# Flutter APP — NOVA 与知识库对接（双网关 · Nova 适配）

> 分析范围：`flutter/` 目录下移动端（WebView 原型壳）对 **NOVA 企业助手** 与 **企业知识库（KB）** 的前端对接。  
> **UI / 交互保持不变**；底层已切换为 **双网关 + 适配层**。  
> 更新日期：2026-06-17

---

## 1. 总体架构（改造后）

Flutter APP 仍通过 **WebView 加载 HTML 原型**，由 Dart 注入 JS 适配层，将 C4/K2/K11/K1 的聊天与 KB 请求路由到 **Nova :3000**，业务 IM/审批/XFlow 仍走 **:6090**。

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter App (WebView)                                       │
│  ├─ assets/prototype/index.html   页面骨架（K1/K3 管理 UI）   │
│  ├─ nova_api_injection.dart       window.DunesNovaApi        │
│  ├─ nova_chat_injection.dart      window.DunesNovaChat       │
│  ├─ kb_chat_injection.dart        window.DunesKbChat         │
│  └─ mobile_injection.dart         路由、C1 列表、注入编排     │
└───────────────┬─────────────────────────────┬───────────────┘
                │ :6090 JWT                   │ Nova Bearer sk
                ▼                             ▼
┌───────────────────────────┐   ┌─────────────────────────────┐
│  flow/im 业务网关 :6090    │   │  NOVA-API :3000             │
│  /auth/sms/token          │   │  POST /v1/chat/completions   │
│  GET /me/nova-models      │   │  POST /v1/audio/transcriptions│
│  GET /me/nova-credentials │   │  POST /v1/chat/completions   │
│  IM / 审批 / XFlow        │   │  POST /v1/audio/transcriptions│
│                           │   │  GET  /v1/app/kb/status      │
│                           │   │  POST /v1/app/kb/documents   │
└───────────────────────────┘   └─────────────────────────────┘
                ▲
                │ admin-web 岗位 novaAllowedModels + 初始额度（优先）
                │ admin-web 部门 novaAllowedModels（无岗位时 fallback）
```

### 1.1 登录与 Provisioning

1. `POST /auth/sms/token`（:6090）→ dunes JWT  
2. `GET /me/nova-models`（:6090）→ 部门对话模型 + 自动并入 `glm-asr-2512`  
3. `GET /me/nova-credentials`（:6090）→ Nova `api_token` / `baseUrl` / `defaultModel`  
4. 可选 fallback：`POST {NOVA}/api/app/auth/login`  
5. Dart `NovaAuthService.provisionAfterLogin` 将结果写入 `AuthSession.novaLocalStorage`，经 `authScript` 注入 WebView

### 1.2 模型解析规则（前后端一致）

```
chat_models    = 部门 nova_allowed_models 非空 ? 配置 : ['nova_deepseek']
allowed_models = mergeUnique(chat_models, ['glm-asr-2512'])
defaultModel   = 部门 default 或 chat_models 首个 nova_*
```

### 1.3 鉴权与基址

| 项 | 说明 |
|---|---|
| 业务 API | `http://{host}:6090/api/v1` → `window.__dunesApiBase` |
| Nova API | `http://124.221.216.24:3000`（`NovaConfig.baseUrl`，可 `--dart-define=NOVA_BASE_URL=`） |
| 业务 Token | `dunes_token` / `dunes_jwt` |
| Nova Token | `dunes_nova_api_key`（来自 `api_token`，与 dunes JWT 分离） |
| 就绪标记 | `localStorage.dunes_nova_ready === '1'` |

### 1.4 注入顺序（`mobile_injection.dart`）

1. `authScript` — dunes + nova localStorage  
2. `NovaApiInjection.js` — `window.DunesNovaApi`  
3. `KbChatInjection.js` / `NovaChatInjection.js` — 页面逻辑（内部优先调 DunesNovaApi）

---

## 2. 页面与入口映射（UI 不变）

| 屏幕 ID | 名称 | 改造后 API |
|---------|------|------------|
| **C4** | NOVA 助手 | Nova `POST /v1/chat/completions` SSE（含多模态） |
| **C11** | AI 历史 | 本地 session 缓存（`DunesNovaApi.loadSessionMessages`） |
| **K2** | 知识库对话 | Nova chat/completions + RAG |
| **K11** | KB 历史 | 本地轮次缓存（`DunesNovaApi.loadLocalTurns('kb')`） |
| **K1** | 知识库管理 | Nova `kb/status` + `kb/documents` |
| **C1** | 通讯列表 KB 行 | 本地 preview 缓存 + Nova 就绪检测 |

---

## 3. DunesNovaApi 适配层

文件：`lib/features/nova/nova_api_injection.dart`

| 方法 | Nova 端点 |
|------|-----------|
| `refreshCredentials()` | :6090 `GET /me/nova-credentials` |
| `chatCompletionsStream()` | `POST /v1/chat/completions`（OpenAI SSE，`user=bizUserId`） |
| `transcribeAudio()` | `POST /v1/audio/transcriptions`（`model=glm-asr-2512`） |
| `pickMultimodalModel()` | 多模态优先 `nova_gpt5.5` |
| `buildMultimodalContent()` | 图片 `image_url` / 文件 `file.file_data` base64 |
| `loadSessionMessages()` / `loadLocalTurns()` | C4/K11 本地历史（无 :6090 fallback） |
| `fetchKbStatus()` | `GET /v1/app/kb/status` |
| `uploadKbDocument()` | `POST /v1/app/kb/documents` |

---

## 4. C4 NOVA（nova_chat_injection.dart）

- `checkNovaReadiness()` → 优先 `DunesNovaApi.refreshCredentials()`  
- 文本/图片/文件 → **仅** Nova `chat/completions`；图片/文件用 OpenAI 多模态 content（`nova_gpt5.5`）
- 语音 → Nova ASR → 文本 chat
- **已移除** 对 `:6090 /ai/assistant/*`、`/ai/transcribe`、`/kb/*` 的降级路径

---

## 5. K2/K11 知识库对话（kb_chat_injection.dart）

- `checkReady()` → `DunesNovaApi.fetchKbStatus()`  
- `sendCurrent()` → Nova chat SSE；`rag.chunks` 映射为现有 citations / `.doc-excerpt`  
- `transcribeKbVoice()` → Nova ASR（不再调 :6090 `/ai/transcribe`）  
- `refreshKbInboxPreview()` → Nova 就绪时用 `dunes_kb_last_preview` 本地缓存

---

## 6. K1 知识库管理（index.html DunesApi JS）

HTML/CSS **未改**；以下 JS 函数增加 Nova 分支：

- `loadKbHome()` — 由 `fetchKbStatus` 组装 stats/目录/最近文档  
- `syncKbRagflow()` — 刷新 Nova KB 状态  
- `wireKbUpload` — 就绪时直传 `uploadKbDocument`  
- `loadKbSubscriptions()` — 适配桩：专属库 + 空可订阅列表  
- 上传文件夹下拉 → 单选项「我的知识库（手机号）」

---

## 7. 后端与运营配置

| 组件 | 路径 | 说明 |
|------|------|------|
| DB 迁移 | `V52` 部门 / `V53` 岗位 nova 配置 | 模型 + 岗位初始额度 |
| flow-go | `ResolveNovaModelsForUser` / `ResolveNovaQuotaForUser` | 岗位优先 → 部门 → 默认 |
| admin-web | `OrgPositionsPage.tsx` | 岗位 NOVA 模型 + 初始额度 |
| admin-web | `OrgDepartmentsPage.tsx` | 部门 NOVA 模型（fallback） |

---

## 8. 自测

```powershell
# 本地 flow-go 已部署 me/nova-* 时：
powershell -File flutter/scripts/nova_e2e_self_test.ps1 -ApiBase http://localhost:6090/api/v1

# 远程（需 6090 网关 + flow-go V52 就绪）：
powershell -File flutter/scripts/nova_e2e_self_test.ps1
```

脚本覆盖：SMS 登录 → `/me/nova-models` → `/me/nova-credentials` → 文本 SSE → **多模态 1×1 PNG** → `kb/status`。

## 9. 验收清单

- [ ] 部门 A 配置 `nova_gpt5.5` + `nova_deepseek`；部门 B 空配置 → 仅 `nova_deepseek`  
- [ ] 登录后 Nova Provisioning 成功，`dunes_nova_ready=1`  
- [ ] C4 文本/语音：抓包仅 :3000 chat + ASR  
- [ ] K2 问答 + 引用卡片；K1 上传 → status 就绪  
- [ ] IM/审批仍仅 :6090  
- [ ] UI 路径 C1→K2、K1→K2、C4→K11 无变化

---

## 10. 相关 Dart 文件索引

| 文件 | 职责 |
|------|------|
| `lib/core/config/nova_config.dart` | Nova baseUrl、默认模型 |
| `lib/features/nova/nova_models_service.dart` | `GET /me/nova-models` |
| `lib/features/nova/nova_auth_service.dart` | 登录后 Provisioning |
| `lib/features/nova/nova_model_utils.dart` | 模型 merge / default 解析 |
| `lib/features/nova/nova_api_injection.dart` | JS 客户端 |
| `lib/features/auth/login_flow.dart` | 登录后调用 Provisioning |
