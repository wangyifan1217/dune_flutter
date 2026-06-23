# Dunes × Nova 联调问题清单

> **文档用途**：Dunes 移动端 Nova 集成联调阻塞项，供 Nova 服务端确认与配置。  
> **日期**：2026-06-18  
> **Dunes 侧联系人**：（请填写）  
> **Nova 环境**：`http://124.221.216.24:3000`

---

## 1. 背景

Dunes APP 采用 **双网关** 架构：

| 网关 | 端口 | 职责 |
|------|------|------|
| flow-go 业务网关 | `:6090` / `:6087` | SMS 登录、JWT、`/me/nova-models`、`/me/nova-credentials` |
| Nova API | `:3000` | 对话 SSE、ASR、知识库 |

**当前进度（Dunes 侧已完成）：**

- [x] flow-go 部署 `GET /api/v1/me/nova-models`、`GET /api/v1/me/nova-credentials`
- [x] 部门 Nova 模型配置（admin-web）
- [x] APP 登录后 Nova Provisioning（写入 WebView `localStorage`）
- [x] Flutter WebView 适配层（C4/K2/K1 页面 UI 不变，底层走 Nova）

**联调脚本**：`flutter/scripts/nova_e2e_self_test.ps1`

---

## 2. 已通过项

使用测试账号在本地 flow-go 验证：

| 步骤 | 接口 | 结果 |
|------|------|------|
| SMS 登录 | `POST {6090}/api/v1/auth/sms/token` | ✅ |
| 读取模型列表 | `GET {6090}/api/v1/me/nova-models` | ✅ `defaultModel=nova_deepseek` |
| 读取 Nova 凭证 | `GET {6090}/api/v1/me/nova-credentials` | ✅ `ready=true` |
| Nova 健康检查 | `GET {3000}/api/status` | ✅ 200 |
| 模型枚举 | `GET {3000}/v1/models` | ✅ 200 |

**credentials 返回示例（节选）：**

```json
{
  "ready": true,
  "bizUserId": "dune_2",
  "apiKey": "sk-***",
  "baseUrl": "http://124.221.216.24:3000",
  "defaultModel": "nova_deepseek",
  "allowedModels": ["nova_deepseek", "glm-asr-2512"],
  "asrModel": "glm-asr-2512"
}
```

---

## 3. 阻塞问题

### 3.1 聊天接口路径不一致

**我们 APP 当前调用：**

```http
POST {BASE}/api/chat/completions
Authorization: Bearer sk-***
Content-Type: application/json
Accept: text/event-stream
X-Nova-Chat-Session-Id: <session-id>
```

**请求体示例：**

```json
{
  "model": "nova_deepseek",
  "stream": true,
  "messages": [
    { "role": "user", "content": "reply OK only" }
  ]
}
```

**实测响应（404）：**

```json
{
  "error": {
    "message": "Invalid URL (POST /api/chat/completions)",
    "type": "invalid_request_error",
    "param": "",
    "code": ""
  }
}
```

**改用标准路径后：**

```http
POST {BASE}/v1/chat/completions
```

路径存在，但返回 **503 / model_not_found**（见 §3.2）。

**请 Nova 确认：**

- [ ] Dunes 应使用 `/api/chat/completions` 还是 `/v1/chat/completions`？
- [ ] 若仅支持 `/v1/*`，是否可在网关增加 `/api/chat/completions` 别名？
- [ ] 还是由 Dunes 改客户端统一走 `/v1/chat/completions`？

---

### 3.2 模型 ID 未注册 / 无可用 channel

Dunes 业务侧约定的 model id：

| 用途 | Dunes 使用的 model id | 说明 |
|------|----------------------|------|
| 默认文本对话 | `nova_deepseek` | 部门未配置时的 fallback |
| 多模态（图片/文件） | `nova_gpt5.5` | C4 发图/发文件 |
| 语音 ASR | `glm-asr-2512` | 语音转文字 |

**当前测试用户（`bizUserId=dune_2`，分组 `svip`）调用：**

```http
POST {BASE}/v1/chat/completions
Authorization: Bearer sk-***
```

```json
{
  "model": "nova_deepseek",
  "user": "dune_2",
  "stream": false,
  "messages": [
    { "role": "user", "content": "reply OK only" }
  ]
}
```

**实测响应：**

```json
{
  "error": {
    "code": "model_not_found",
    "message": "No available channel for model nova_deepseek under group svip (distributor) (request id: ...)",
    "type": "new_api_error"
  }
}
```

**同一用户 `GET /v1/models` 当前可用模型：**

```
deepseek-v4-flash-none
glm-4v
hermes-agent
hermes-chat
hermes-pro
glm-4-voice
embedding-3
deepseek-v4-flash
hermes-prd
glm-asr-2512
```

> 列表中 **没有** `nova_deepseek`、`nova_gpt5.5`。

**请 Nova 确认（二选一）：**

**方案 A — Nova 注册 Dunes 模型名**

- [ ] 为 `svip` 分组配置 upstream channel，并注册/映射：
  - `nova_deepseek` → （请填写 upstream，如 `deepseek-v4-flash` / `hermes-chat`）
  - `nova_gpt5.5` → （请填写 upstream，如 `glm-4v`）
  - `glm-asr-2512` → （已出现在 models 列表，请确认 ASR 接口可用）

**方案 B — Dunes 改用 Nova 正式 model id**

请提供映射表，例如：

| Dunes 用途 | Nova 正式 model id |
|------------|-------------------|
| 默认对话 | `???` |
| 多模态 | `???` |
| ASR | `glm-asr-2512`？ |

---

### 3.3 请求体 `user` 字段与 Session 头

参考 New API 文档，`POST /v1/chat/completions` 要求请求体带 **`user`**（业务用户 ID，用于记忆隔离）。

Dunes flow-go 已在 credentials 中返回 `bizUserId`（如 `dune_2`）。

**请 Nova 确认：**

- [ ] 聊天请求是否 **必须** 带 `"user": "<bizUserId>"`？
- [ ] `X-Nova-Chat-Session-Id` 请求头是否支持？与 `user` 的关系是什么？
- [ ] 流式 SSE 响应格式是否为标准 OpenAI（`data: {...}`，`choices[0].delta.content`）？
- [ ] K2 知识库对话是否在 SSE 中附带 `rag` / `quota` 等扩展字段？格式请提供示例。

---

### 3.4 知识库 API 未找到（404）

Dunes K1（知识库管理）与 K2（知识库对话）依赖以下 Nova 应用层接口：

```http
GET  {BASE}/api/app/kb/status
Authorization: Bearer sk-***
```

```http
POST {BASE}/api/app/kb/documents
Authorization: Bearer sk-***
Content-Type: multipart/form-data

file=<binary>
title=<string>        # 可选
folderId=<string>     # 可选
```

**实测 `GET /api/app/kb/status` 响应（404）：**

```json
{
  "error": {
    "message": "Invalid URL (GET /api/app/kb/status)",
    "type": "invalid_request_error",
    "param": "",
    "code": ""
  }
}
```

**请 Nova 确认：**

- [ ] `/api/app/kb/*` 是否尚未部署？
- [ ] 若已有等价接口，请提供 **正式路径** 与 **请求/响应 JSON 示例**
- [ ] KB 是否对接 Ragflow？Dunes flow-go 侧配置了 `RAGFLOW_BASE_URL`，请说明 APP 应直连 Nova 还是 Ragflow
- [ ] `kb/status` 期望返回哪些字段（如 `ready`、`stats`、`folders`、`recentDocuments`）？

---

### 3.5 语音 ASR 接口

Dunes APP 语音输入调用：

```http
POST {BASE}/v1/audio/transcriptions
Authorization: Bearer sk-***
Content-Type: multipart/form-data

file=<audio binary>
model=glm-asr-2512
```

**请 Nova 确认：**

- [ ] 该接口在 `:3000` 上是否已上线？
- [ ] 支持的音频格式（webm / wav / mp3）与大小限制？
- [ ] 响应格式是否为 OpenAI 兼容（`{ "text": "..." }`）？

---

### 3.6 Partner 开户：额度仍为 $0.02、令牌无 `glm-asr-2512`

**状态更新（2026-06-17）**：Nova 已提供 **`POST /api/partner/v1/users/{username}/tokens`**（Partner Key 代管令牌）。Dunes flow-go 已接入：开户同步时 **优先** 调用该接口配置 `model_limits`（含 `glm-asr-2512`），**无需用户登录**。仍待 Nova 确认：`initial_quota_cny` 生效、`topup` 接口。

**原现象（admin-web 组织用户 → 同步 NOVA，测试账号 `15268642022` / `user_id=2`）：**

| 项 | Dunes 期望 | Nova 后台实际 |
|----|-----------|--------------|
| 账户额度 | `initial_quota_cny=2000`（¥20） | **$0.02** |
| 令牌 `model_limits` | `nova_deepseek,glm-asr-2512,...` | 仅默认托管令牌，**无 `glm-asr-2512`** |

**Dunes 已按文档发送 Partner 注册请求（flow-go 日志）：**

```json
{
  "username": "dune_id_15268642022",
  "password": "***",
  "biz_user_id": "dune_2",
  "plan": "svip",
  "initial_quota": 2000000000,
  "initial_quota_cny": 2000
}
```

**实际联调链路（`docker logs dunes-flow-go`）：**

```text
1. POST /api/partner/v1/users/register  → success，响应含 api_token（非文档标准形态）
2. POST /api/partner/v1/users/topup    → 404（接口未实现）
3. POST /api/user/login (dune_id_15268642022) → "Username or password is incorrect"
4. Dunes 兜底：使用 register 返回的 api_token 标记 ready
5. ensureRagflow 内 POST /api/token/ → "普通用户不能自行创建令牌，系统将自动托管聊天令牌"
```

**根因说明：**

Dunes 标准开户流程应为（见 `NEW_API_THIRD_PARTY_INTEGRATION.md` §4.5）：

```text
Partner register → user login → POST /api/token/（model_limits_enabled + model_limits）→ 取 sk-
```

当前 Nova 环境导致该流程 **无法走完**：

1. **注册响应直接返回 `api_token`**，且为平台默认托管令牌（低额度、无业务模型限制），与文档「响应不含 sk-」不一致。
2. **`initial_quota` / `initial_quota_cny` 未生效**（或对已存在用户不更新），账户仍为 $0.02。
3. **`POST /api/partner/v1/users/topup` 返回 404**，Dunes 无法补额。
4. **登录失败**：Dunes 提交 `username=dune_id_15268642022`，Nova 侧用户名为 `15268642022`；且历史用户密码与本次 register 密码可能不一致。
5. **普通用户禁止自建令牌**：即使登录成功，`POST /api/token/` 也会被拒，无法创建带 `glm-asr-2512` 的专用令牌。

因此 **$0.02 与缺少 ASR 模型不是 Dunes 未传参，而是 Nova Partner / 托管令牌能力未满足对接文档**。

**请 Nova 团队实现或确认（优先级 P0）：**

| # | 需求 | 说明 |
|---|------|------|
| 1 | 注册时生效额度 | `initial_quota` / `initial_quota_cny` 对新用户 **和** 已存在用户（re-register）均生效 |
| 2 | 实现 Partner 充值 | `POST /api/partner/v1/users/topup`（当前 404），或文档指明等价接口 |
| 3 | 注册时配置托管令牌模型 | 请求体支持 `allowed_models` / `model_limits`（逗号分隔），开户时写入 **系统托管聊天令牌** |
| 4 | 注册时配置托管令牌额度 | 托管令牌的 `remain_quota` 或与账户额度联动，避免 $0.02 默认值 |
| 5 | 已存在用户 re-register | 同步本次 `password`，或返回明确错误 **且不要** 返回误导性的默认 `api_token` |
| 6 | 用户名约定 | 确认以 `dune_id_{phone}` 还是 `{phone}` 为准；响应 `data.username` 应与请求一致 |
| 7 | Partner 代管令牌 | ✅ `POST /api/partner/v1/users/{username}/tokens` 已上线；Dunes 已对接 |

**Dunes 期望的 register 扩展示例（待 Nova 确认字段名）：**

```json
{
  "username": "dune_id_15268642022",
  "password": "SecurePass123",
  "biz_user_id": "dune_2",
  "plan": "svip",
  "initial_quota_cny": 2000,
  "allowed_models": ["nova_deepseek", "glm-asr-2512"],
  "model_limits_enabled": true,
  "model_limits": "nova_deepseek,glm-asr-2512"
}
```

**临时手工解堵（仅测试）：** 在 Nova 管理台删除用户 `15268642022` / `dune_id_15268642022`，Dunes 侧重置该用户 nova 记录后重新同步——**仅当 Nova 修复上述接口后才会得到正确额度与 ASR 模型**。

---

## 4. Dunes 侧完整 API 依赖清单

以下为 APP 改造后 **仅走 Nova :3000** 的接口（不再 fallback 到 :6090）：

| 功能 | 方法 | 路径 | 状态 |
|------|------|------|------|
| 文本对话 SSE | POST | `/api/chat/completions` 或 `/v1/chat/completions` | ❌ 待对齐 |
| 多模态对话 | POST | 同上，`model=nova_gpt5.5`，content 含 `image_url` / `file_data` | ❌ 待对齐 |
| 语音 ASR | POST | `/v1/audio/transcriptions` | ❓ 待确认 |
| KB 状态 | GET | `/api/app/kb/status` | ❌ 404 |
| KB 文档上传 | POST | `/api/app/kb/documents` | ❌ 404 |
| Nova 登录 fallback | POST | `/api/app/auth/login` | ❓ 可选，待确认 |

业务网关 `:6090` 仍负责：SMS 登录、IM、审批、XFlow 等，**不涉及 Nova 聊天**。

---

## 5. 联调验收标准

Nova 配置完成后，Dunes 将跑以下 E2E 自测（全部 PASS 即验收）：

```powershell
powershell -File flutter/scripts/nova_e2e_self_test.ps1 `
  -ApiBase http://localhost:6090/api/v1 `
  -NovaBase http://124.221.216.24:3000
```

| # | 测试项 | 期望 |
|---|--------|------|
| 1 | SMS 登录 | 返回 JWT |
| 2 | `GET /me/nova-models` | 返回 `defaultModel`、`allowedModels` |
| 3 | `GET /me/nova-credentials` | `ready=true`，有 `apiKey`、`baseUrl` |
| 4 | 文本 chat SSE | 有非空回复 |
| 5 | 多模态（1×1 PNG） | `nova_gpt5.5` 或指定 vision 模型有回复 |
| 6 | `GET /api/app/kb/status` | 返回 KB 就绪状态 |

---

## 6. 请 Nova 回复的清单

请逐项回复，便于 Dunes 一次性改完客户端：

1. **聊天路径**：`/api/chat/completions` 还是 `/v1/chat/completions`？
2. **模型映射表**：`nova_deepseek`、`nova_gpt5.5`、`glm-asr-2512` 对应的正式 model id 及 svip 分组 channel 配置
3. **`user` 字段**：是否必填？格式是否为 `dune_{userId}`？
4. **SSE 格式**：标准 OpenAI？是否有 `rag` / `quota` 扩展？
5. **KB 接口**：`/api/app/kb/*` 上线时间，或提供替代 API 文档
6. **ASR 接口**：`/v1/audio/transcriptions` 是否可用及限制
7. **多模态**：支持的 content 类型（`image_url` base64、`file.file_data` 等）

---

## 8. 云枢图片多模态失败（vision rejected）

详见独立文档：**[nova-vision-image-issue.md](./nova-vision-image-issue.md)**  
（现象、已尝试的三种 `image_url` 传参、Nova 自测 curl、待确认问题清单）

---

## 9. 云枢对话审计与 Admin 监管（新增）

Dunes 已在 APP 每轮云枢对话完成后向 flow-go 同步记录，并在 admin-web 增加「**云枢对话记录**」页面。

**完整方案（含 flow-go API 规格、DB 表结构、Nova Phase 2 待办）见：**

👉 **[nova-history-audit-integration.md](./nova-history-audit-integration.md)**

**Nova 团队 Phase 2 简要待办：**

1. Assistant 回复中生成文件时使用 **HTTPS Markdown 链接**（非仅 `/opt/data/...` 路径）
2. 确认 **`X-Nova-Chat-Session-Id`** 在 Nova 侧持久化并可审计
3. （可选）提供 **对话完成 Webhook** 或 **bizUser 维度只读审计 API**

---

## 7. 附录：curl 复现命令

Nova 同学可用已有 `sk-` 快速复现：

```bash
# 1. 模型列表
curl -sS "http://124.221.216.24:3000/v1/models" \
  -H "Authorization: Bearer sk-***"

# 2. 聊天（/api 路径 — 当前 404）
curl -sS "http://124.221.216.24:3000/api/chat/completions" \
  -H "Authorization: Bearer sk-***" \
  -H "Content-Type: application/json" \
  -d '{"model":"nova_deepseek","stream":false,"messages":[{"role":"user","content":"hi"}]}'

# 3. 聊天（/v1 路径 — model_not_found）
curl -sS "http://124.221.216.24:3000/v1/chat/completions" \
  -H "Authorization: Bearer sk-***" \
  -H "Content-Type: application/json" \
  -d '{"model":"nova_deepseek","user":"dune_2","stream":false,"messages":[{"role":"user","content":"hi"}]}'

# 4. KB 状态（当前 404）
curl -sS "http://124.221.216.24:3000/api/app/kb/status" \
  -H "Authorization: Bearer sk-***"
```

---

*文档由 Dunes 联调自动生成，如有疑问请联系 Dunes 开发同学。*
