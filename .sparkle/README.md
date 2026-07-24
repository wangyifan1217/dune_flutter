# Sparkle 更新签名密钥

- `eddsa_pub.key`：公钥，已写入 `macos/Runner/Info.plist` 的 `SUPublicEDKey`。
- `eddsa_priv.key`：私钥，**勿提交仓库**。请把文件内容完整粘贴到 GitHub Secret：

  **Name:** `SPARKLE_PRIVATE_KEY`

  **Value:**（`eddsa_priv.key` 单行 base64，无换行）

CI 在签名更新包时会读取该 Secret。丢失后只能轮换密钥并发布强制更新。
