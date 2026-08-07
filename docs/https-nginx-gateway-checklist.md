# 域名 HTTPS + Nginx 转发清单

> 目标：用域名 + HTTPS 访问后端，经 Nginx 反代到现有端口服务；旧的 `http://IP:端口` 可并存。  
> 适用范围：Flutter App、admin-web、业务网关、Nova/知识库、Centrifuge WS。  
> 更新日期：2026-08-07

---

## 1. 背景与原则

### 1.1 现状（端口直连）

| 服务 | 当前访问 | 路径特点 |
|------|----------|----------|
| 业务网关 (flow/im) | `http://{host}:6090/api/v1` | 已有 `/api/v1` |
| Centrifuge WS | `ws://{host}:6090/connection/websocket` | **不在** `/api` 下 |
| flow-go 直连 | `http://{host}:6087/api/v1` | 与 6090 路径相同 |
| Nova / 知识库 | `http://{host}:3000` | 主路径 `/v1/...`，另有 `/api/app/...` |
| admin-go | `http://{host}:6092/admin/api/v1` | 已有 `/admin/api/v1` |

默认主机参考：`124.221.216.24`（见 `lib/core/config/dunes_defaults.dart`、`nova_config.dart`）。

### 1.2 改造原则

1. **6090 已带 `/api/v1`**：对外优先保持路径，不要随意改成另一套前缀（除非前后端一起改）。
2. **WebSocket 必须单独配**：`/connection/` 不能只靠 `/api` 一条规则。
3. **Nova 与业务会撞路径**：两边都有 `/api/...`，Nova 还有 `/v1/...`，需子路径或子域名拆开。
4. **旧 HTTP 默认不受影响**：只加域名 443 入口、旧端口继续监听即可并存。

---

## 2. 推荐 Nginx 拆分（同一域名）

```text
https://api.xxx.com
├── /api/v1/              → 127.0.0.1:6090     # 业务（保持现有路径）
├── /connection/          → 127.0.0.1:6090     # Centrifuge WSS
├── /nova/                → 127.0.0.1:3000     # 需 rewrite 去掉 /nova 前缀
│     或更好：用子域名 nova.xxx.com → :3000
└── /admin/api/v1/        → 127.0.0.1:6092     # 管理端
```

> 将文中 `api.xxx.com` / `nova.xxx.com` 替换为真实域名。

---

## 3. 域名与入口清单

| 项 | 内容 | 状态 |
|----|------|------|
| 主域名 | `https://api.xxx.com` | ☐ 待定 |
| TLS 证书 | 443 配置；80 → 301 https | ☐ |
| Nova 方案 | A 同域 `/nova` / B 子域名 `nova.xxx.com`（推荐 B） | ☐ 待定 |
| 旧入口保留 | `http://IP:6090` / `:3000` / `:6092` 过渡期不关 | ☐ |
| 反代目标 | Nginx → `127.0.0.1:端口` | ☐ |
| 公网是否关闭旧端口 | 稳定后再关；联调需要可继续开放 | ☐ 待定 |

---

## 4. 路径转发明细

### 4.1 业务 API → `:6090`

| 项 | 值 |
|----|-----|
| 对外 | `https://api.xxx.com/api/v1/...` |
| 对内 | `http://127.0.0.1:6090/api/v1/...` |
| rewrite | **不需要**（路径原样转发） |
| 用途 | 登录、IM、审批、灯塔、会议 REST、存储下载等 |
| App 现基址 | `http://host:6090/api/v1` |
| `client_max_body_size` | 建议 ≥ `100m` |

### 4.2 Centrifuge WebSocket → `:6090`

| 项 | 值 |
|----|-----|
| 对外 | `wss://api.xxx.com/connection/websocket` |
| 对内 | `http://127.0.0.1:6090/connection/websocket` |
| location | `/connection/` |
| 必配 | `Upgrade`、`Connection "upgrade"`；拉长 `proxy_read_timeout` |
| App 现基址 | `ws://host:6090/connection/websocket` |

### 4.3 Nova / 知识库 → `:3000`

#### 方案 A：同域路径前缀（需 rewrite）

| 项 | 值 |
|----|-----|
| 对外 | `https://api.xxx.com/nova/v1/...` |
| 对内 | `http://127.0.0.1:3000/v1/...` |
| rewrite | **去掉前缀 `/nova`** |
| App `NovaConfig.baseUrl` | `https://api.xxx.com/nova` |
| 额外 | SSE：`proxy_buffering off`；上传加大 body |

| 功能 | 后端真实路径 | 经 Nginx 后完整 URL |
|------|--------------|---------------------|
| KB 状态 | `/v1/app/kb/status` | `https://api.xxx.com/nova/v1/app/kb/status` |
| KB 文档 | `/v1/app/kb/documents` | `https://api.xxx.com/nova/v1/app/kb/documents` |
| 对话 SSE | `/v1/chat/completions` | `https://api.xxx.com/nova/v1/chat/completions` |
| ASR | `/v1/audio/transcriptions` | `https://api.xxx.com/nova/v1/audio/transcriptions` |
| 文件下载 | `/v1/files/download` | `https://api.xxx.com/nova/v1/files/download` |
| App 登录 | `/api/app/auth/login` | `https://api.xxx.com/nova/api/app/auth/login` |

#### 方案 B：子域名（更推荐，少踩坑）

| 项 | 值 |
|----|-----|
| 对外 | `https://nova.xxx.com/...` |
| 对内 | `http://127.0.0.1:3000/...` |
| rewrite | **不需要** |
| App `NovaConfig.baseUrl` | `https://nova.xxx.com` |

### 4.4 管理端 → `:6092`

| 项 | 值 |
|----|-----|
| 对外 | `https://api.xxx.com/admin/api/v1/...` |
| 对内 | `http://127.0.0.1:6092/admin/api/v1/...` |
| rewrite | **不需要** |
| 客户端 | admin-web（非 Flutter App） |

### 4.5 暂不对外 / 另议

| 端口/服务 | 建议 |
|-----------|------|
| `:6087` flow-go 直连 | 尽量在 6090 代理齐 `/xflow`，客户端只打业务网关 |
| 会议实时转写 WS | 后端返回的 `baseUrl` 改为 `wss://域名/...`，Nginx 增加对应 location |
| MinIO / CDN | 可暂维持原样，或单独域名 |

---

## 5. Nginx 配置核对表

| 检查项 | `/api/v1/` | `/connection/` | `/nova/`（方案 A） | `/admin/api/v1/` |
|--------|:----------:|:--------------:|:-----------------:|:----------------:|
| `proxy_pass` 本机端口 | 6090 | 6090 | 3000 | 6092 |
| 去掉前缀 rewrite | 否 | 否 | **是** | 否 |
| WebSocket 升级头 | 否 | **是** | 否 | 否 |
| SSE 关 buffering | 可选 | — | **是** | — |
| 大 body | **是** | — | **是** | 视上传 |
| 长超时 | 中 | **长** | **长**（对话/ASR） | 中 |
| `Host` / `X-Forwarded-*` | 是 | 是 | 是 | 是 |
| `X-Forwarded-Proto https` | 是 | 是 | 是 | 是 |

### 5.1 参考配置片段（需替换域名与证书路径）

```nginx
# 仅作参考草稿，上线前按环境校对

upstream dunes_gateway {
    server 127.0.0.1:6090;
}

upstream nova_api {
    server 127.0.0.1:3000;
}

upstream admin_go {
    server 127.0.0.1:6092;
}

server {
    listen 80;
    server_name api.xxx.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.xxx.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    client_max_body_size 100m;

    # 业务 API
    location /api/v1/ {
        proxy_pass http://dunes_gateway;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300s;
    }

    # Centrifuge WSS
    location /connection/ {
        proxy_pass http://dunes_gateway;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
    }

    # Nova（方案 A：去掉 /nova 前缀）
    location /nova/ {
        rewrite ^/nova/(.*)$ /$1 break;
        proxy_pass http://nova_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;          # SSE
        proxy_read_timeout 3600s;
        client_max_body_size 100m;
    }

    # 管理端
    location /admin/api/v1/ {
        proxy_pass http://admin_go;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300s;
    }
}

# 方案 B：Nova 子域名（可选，与上方 /nova/ 二选一）
# server {
#     listen 443 ssl http2;
#     server_name nova.xxx.com;
#     ssl_certificate     /path/to/fullchain.pem;
#     ssl_certificate_key /path/to/privkey.pem;
#     client_max_body_size 100m;
#     location / {
#         proxy_pass http://nova_api;
#         proxy_set_header Host $host;
#         proxy_set_header X-Forwarded-Proto https;
#         proxy_buffering off;
#         proxy_read_timeout 3600s;
#     }
# }
```

---

## 6. 客户端 / 下发字段改址清单

### 6.1 Flutter

| 配置 | 现在 | 方案 A（同域） | 方案 B（Nova 子域） | 代码位置 |
|------|------|---------------|---------------------|----------|
| `apiBase` | `http://IP:6090/api/v1` | `https://api.xxx.com/api/v1` | 同左 | `lib/core/config/dunes_defaults.dart` |
| `wsBase` | `ws://IP:6090/connection/websocket` | `wss://api.xxx.com/connection/websocket` | 同左 | 同上 |
| `NovaConfig.baseUrl` | `http://IP:3000` | `https://api.xxx.com/nova` | `https://nova.xxx.com` | `lib/core/config/nova_config.dart` |
| `flowApiBase` (:6087) | 直连 6087 | 优先并入 `apiBase`，能不用则不用 | 同左 | `dunes_defaults.dart` |

可通过 `--dart-define` 覆盖（如 `DUNES_API_HOST`、`NOVA_BASE_URL`），生产建议改为完整 HTTPS 基址。

### 6.2 后端下发字段（易漏）

| 字段 | 谁用 | 应返回 |
|------|------|--------|
| `/me/nova-credentials` → `baseUrl` | Flutter Nova/KB | HTTPS 域名基址（勿再返回 `http://IP:3000`） |
| 会议 session → `baseUrl` | 实时转写 WS | `wss://...` 可经 Nginx 的地址 |
| 各类下载 / 回调 URL | 附件、纪要等 | 尽量 HTTPS 域名，避免混合内容 |

### 6.3 admin-web

| 项 | 改法 |
|----|------|
| Vite 代理 / 生产 `VITE_*` | `/api/v1`、`/connection`、`/admin/api/v1` 指向 HTTPS 域名 |
| Nova 直连 | `https://api.xxx.com/nova` 或 `https://nova.xxx.com` |

---

## 7. 对旧 HTTP 的影响

| 动作 | 是否影响旧 `http://IP:端口` |
|------|------------------------------|
| 只加域名 443 Nginx | **不影响** |
| 6090/3000/6092 继续监听 | **不影响** |
| 关掉公网旧端口 | **影响**（仅内网 + Nginx） |
| 对 IP:端口 做强制跳 HTTPS | **影响** |
| 已发版、写死 IP:端口 的旧 App | 只要旧端口开着就仍可用 |
| 新 App 改为 HTTPS 域名 | 走新入口；与旧包可并存 |

**结论：** Nginx 只做域名 HTTPS 转发、旧端口照开 → 老用法可并存。

---

## 8. 验收测试单

### 8.1 业务 6090

- [ ] `GET https://api.xxx.com/api/v1/...`（带 token）通
- [ ] 短信登录 / 刷新 token 通
- [ ] IM 会话列表、发消息通
- [ ] 文件上传 / 下载通

### 8.2 WebSocket

- [ ] `wss://api.xxx.com/connection/websocket` 能连上
- [ ] 实时消息能推到

### 8.3 Nova / KB

- [ ] KB status 通
- [ ] 上传文档通
- [ ] 对话 SSE 流式返回正常（不会整包卡住）
- [ ] ASR / 文件下载通

### 8.4 Admin

- [ ] `https://api.xxx.com/admin/api/v1/...` 通

### 8.5 兼容

- [ ] 旧 `http://IP:6090/api/v1` 仍通（若保留端口）
- [ ] 旧 App 包不受影响
- [ ] 新 App 无明文混合请求报错

---

## 9. 建议落地顺序

1. Nginx 先挂 **6090 的 `/api/v1` + `/connection`** 到域名 HTTPS  
2. App 改 `apiBase` / `wsBase`，验证登录、IM、WS  
3. 再挂 Nova（优先子域名）  
4. 收口 6087、会议 WS 返回地址、admin  
5. 稳定后视情况关闭公网旧端口  

---

## 10. 待拍板（开工前）

1. 真实域名：`api.xxx.com` / 是否需要 `nova.xxx.com`  
2. Nova 用同域 `/nova` 还是子域名（建议子域名）  
3. 公网是否继续开放 `IP:6090/3000`（建议过渡期开放）  

---

## 11. 相关代码与文档

| 说明 | 路径 |
|------|------|
| 业务 API / WS 默认配置 | `flutter/lib/core/config/dunes_defaults.dart` |
| Nova 默认配置 | `flutter/lib/core/config/nova_config.dart` |
| Nova / KB 双网关说明 | `flutter/docs/nova-kb-integration.md` |
| KB 服务调用 | `flutter/lib/features/kb/native_kb_service.dart` |
