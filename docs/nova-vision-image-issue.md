# 云枢图片多模态：`vision API rejected the image`

> 关联文档：[nova-integration-issues-for-nova-team.md](./nova-integration-issues-for-nova-team.md)

---

## Nova 官方结论（一句话）

**本地图片 → 压缩成 JPEG → `data:image/jpeg;base64,` + base64 → 放进 `messages[].content[].image_url.url` → 调 `POST /v1/chat/completions`**

不支持（或未验证）直接传 FTP/CDN 公网 `https://` URL 给 vision。

---

## Dunes 客户端实现（已对齐）

| 步骤 | 实现 |
|------|------|
| 图片来源 | 优先用户选择的**本地 File**（draft 里 `a.file`），上传 objectKey 仅用于 IM 展示/历史 |
| 压缩 | canvas 转 **JPEG**，max 1568px，quality 0.82 |
| 编码 | `data:image/jpeg;base64,{base64}` |
| 请求体 | `{ type: "image_url", image_url: { url: "data:image/jpeg;base64,..." } }` |
| 接口 | `POST {nova_base}/v1/chat/completions`，`model=nova_gpt5.5`，`stream=true` |

代码位置：`flutter/lib/features/nova/nova_api_injection.dart`  
- `fileToJpegDataUrl()`  
- `buildMultimodalContent()`  
- `resolveMultimodalFile()`（本地 File 优先）

控制台日志：`[DunesNovaApi] vision jpeg dataUrl len=...`

---

## 标准请求示例

```json
{
  "model": "nova_gpt5.5",
  "stream": true,
  "user": "dune_{userId}",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "请分析这张图片" },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/jpeg;base64,/9j/4AAQSkZJRg..."
          }
        }
      ]
    }
  ]
}
```

---

## 历史现象（联调记录）

| 项 | 说明 |
|----|------|
| 文本对话 | ✅ 正常 |
| 图片对话（改之前） | ❌ AI 回复「vision API rejected the image」 |
| 曾尝试失败的方式 | 公网 CDN URL、presigned URL、未强制 JPEG 的 base64 |

---

## Nova 自测 curl（JPEG base64）

```bash
# 将 /path/to/photo.jpg 换成真实图片，生成 data URL 后填入 url 字段
B64=$(base64 -w0 /path/to/photo.jpg)
curl -sS "http://124.221.216.24:3000/v1/chat/completions" \
  -H "Authorization: Bearer sk-***" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"nova_gpt5.5\",
    \"stream\": false,
    \"user\": \"dune_2\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        { \"type\": \"text\", \"text\": \"描述这张图片，一句话。\" },
        {
          \"type\": \"image_url\",
          \"image_url\": { \"url\": \"data:image/jpeg;base64,${B64}\" }
        }
      ]
    }]
  }"
```

---

*文档由 Dunes 联调整理。*
