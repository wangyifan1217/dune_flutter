# RAGFlow 智能客服接口文档

本文介绍知识库和智能客服的常用 API 接口。

## 1. API 地址

API 基础地址：`http://nova.heunion.com:6080/api/v1`。

当前地址使用 HTTP，传输内容未加密。API Key 请通过安全渠道获取，并妥善保管。

## 2. 认证

使用提供的 API Key 进行身份认证，请求头格式如下：

```http
Authorization: Bearer <API_KEY>
```

API Key 应保存在调用方的后端或密钥管理系统中，不要放在浏览器前端代码或公开文档中。

下文为 Bash 示例，请先设置变量：

```bash
export BASE_URL='http://nova.heunion.com:6080/api/v1'
export API_KEY='<API Key>'
```

多数接口返回 JSON，通常包含 `code`、`message` 和 `data`；应同时检查 HTTP 状态和业务 `code`，HTTP 200 不一定代表业务成功。流式接口的响应格式不同。

## 3. 典型接入流程

1. 在客服租户中创建知识库并记录 `dataset_id`。
2. 上传文档，记录返回的 `document_id`；发起解析并等待解析完成。
3. 创建聊天助手，绑定知识库，记录 `chat_id`。
4. 按需创建会话并记录 `session_id`，调用聊天接口。

ID 需替换为接口实际返回值。下列业务调用的请求格式已核对，除认证及知识库列表外尚未进行完整流程验证。

## 4. 知识库

### 4.1 查询知识库

```bash
curl "$BASE_URL/datasets" \
  -H "Authorization: Bearer $API_KEY"
```

### 4.2 创建知识库

```bash
curl -X POST "$BASE_URL/datasets" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"客服知识库","description":"客户服务资料","permission":"me","chunk_method":"naive"}'
```

`name` 必填；省略 `embedding_model` 时使用当前租户默认嵌入模型。`permission` 可设置为 `me` 或 `team`。

### 4.3 上传文档

```bash
curl -X POST "$BASE_URL/datasets/<dataset_id>/documents" \
  -H "Authorization: Bearer $API_KEY" \
  -F 'file=@./faq.pdf'
```

请求为 `multipart/form-data`，文件字段名为 `file`。返回的文档 ID 用于后续解析。

### 4.4 启动文档解析

```bash
curl -X POST "$BASE_URL/datasets/<dataset_id>/documents/parse" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"document_ids":["<document_id>"]}'
```

解析是异步过程，可调用 `GET /datasets/<dataset_id>/documents` 查询文档状态。解析完成后再进行检索。

### 4.5 检索知识库

```bash
curl -X POST "$BASE_URL/retrieval" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"dataset_ids":["<dataset_id>"],"question":"如何联系客服？","page":1,"page_size":10}'
```

`dataset_ids` 和 `question` 必填；一次检索多个知识库时，服务端要求它们使用相同的嵌入模型。

## 5. 智能客服

### 5.1 查询及创建聊天助手

```bash
curl "$BASE_URL/chats" -H "Authorization: Bearer $API_KEY"

curl -X POST "$BASE_URL/chats" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"智能客服","dataset_ids":["<dataset_id>"]}'
```

创建时 `name` 必填，`dataset_ids` 指定绑定的知识库；省略模型时使用租户默认聊天模型。

### 5.2 创建聊天会话

```bash
curl -X POST "$BASE_URL/chats/<chat_id>/sessions" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"客服会话"}'
```

返回数据中的会话 ID 用作后续的 `session_id`。也可以通过 `GET /chats/<chat_id>/sessions` 查询。

### 5.3 发起对话

```bash
curl -X POST "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"chat_id":"<chat_id>","session_id":"<session_id>","question":"你们的服务时间是什么？","stream":false}'
```

`question` 可替换为 `messages` 消息数组，最后一条应为 `user` 消息。需要沿用会话时同时提供 `chat_id` 和 `session_id`；提供 `chat_id` 而不提供 `session_id` 时服务端可创建会话。`stream` 默认为 `true`，上例设置为 `false` 便于处理完整响应。

## 6. 常见问题

如遇 HTTP 401，请检查 API Key 和请求头；如遇业务错误，请检查响应中的 `code` 和 `message`，以及资源是否属于当前账号。
