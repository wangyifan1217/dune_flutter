use std::collections::HashMap;
use std::io::Cursor;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use calamine::{Reader, Xlsx};
use parking_lot::Mutex;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::{mpsc, oneshot, Mutex as AsyncMutex};
use tracing::{debug, error, warn};

use crate::models::{AppSettings, PromptAttachment, SessionUpdateEvent};
use crate::workspace::{absolutize, read_text_file, write_text_file_with_diff};

static REQUEST_ID: AtomicU64 = AtomicU64::new(1);

const EXCEL_MAX_ROWS_PER_SHEET: usize = 200;
const EXCEL_MAX_COLUMNS: usize = 30;
const EXCEL_MAX_OUTPUT_CHARS: usize = 100_000;
const MAX_BINARY_ATTACHMENT_BYTES: usize = 10 * 1024 * 1024;

fn excel_attachment_to_text(attachment: &PromptAttachment) -> Result<String> {
    let bytes = STANDARD
        .decode(&attachment.data)
        .map_err(|_| anyhow!("Excel 文件编码无效：{}", attachment.name))?;
    let mut workbook = Xlsx::new(Cursor::new(bytes))
        .map_err(|e| anyhow!("无法读取 Excel 文件 {}：{e}", attachment.name))?;
    let sheet_names = workbook.sheet_names().to_owned();
    let mut output = format!("--- Excel 文件：{} ---\n", attachment.name);

    for sheet_name in sheet_names {
        let range = workbook
            .worksheet_range(&sheet_name)
            .map_err(|e| anyhow!("无法读取工作表 {sheet_name}：{e}"))?;
        output.push_str(&format!("\n## 工作表：{sheet_name}\n"));
        for row in range.rows().take(EXCEL_MAX_ROWS_PER_SHEET) {
            let values = row
                .iter()
                .take(EXCEL_MAX_COLUMNS)
                .map(ToString::to_string)
                .collect::<Vec<_>>();
            output.push_str(&values.join("\t"));
            output.push('\n');
            if output.len() >= EXCEL_MAX_OUTPUT_CHARS {
                output.push_str("\n[内容已截断：仅发送前 100,000 个字符]\n");
                return Ok(output);
            }
        }
    }

    Ok(output)
}

struct OutboundWriter {
    tx: mpsc::UnboundedSender<String>,
}

impl Clone for OutboundWriter {
    fn clone(&self) -> Self {
        Self {
            tx: self.tx.clone(),
        }
    }
}

impl OutboundWriter {
    fn send(&self, payload: Value) -> Result<()> {
        let line = serde_json::to_string(&payload)?;
        self.tx
            .send(line)
            .map_err(|_| anyhow!("Agent stdin writer closed"))
    }
}

pub struct AgentHandle {
    child: AsyncMutex<Child>,
    writer: OutboundWriter,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<Result<Value>>>>>,
    session_id: Option<String>,
    workspace: String,
    /// 启动时绑定的模型；设置变更后需重建进程。
    model_id: String,
    /// 模型 / 网关 / CLI 指纹；与当前设置不一致时按会话惰性重建，避免拖死其它会话。
    config_fingerprint: String,
    supports_images: bool,
    supports_embedded_context: bool,
}

/// 用于判断已有 Agent 是否仍匹配当前运行时设置。
pub fn settings_fingerprint(settings: &AppSettings) -> String {
    format!(
        "m={}|b={}|k={}|c={}|a={}",
        settings.model_id.trim(),
        settings.api_base_url.trim().trim_end_matches('/'),
        settings.api_key.trim(),
        settings.grok_command.trim(),
        settings.grok_args.join("\u{1f}")
    )
}

fn rpc_id_key(id: &Value) -> Option<String> {
    match id {
        Value::Number(n) => Some(n.to_string()),
        Value::String(s) => Some(s.clone()),
        _ => None,
    }
}

/// 从 agent 下发的 options 里选一个合法 optionId
fn pick_option_id(params: &Value, allow: bool) -> Option<String> {
    let options = params.get("options")?.as_array()?;
    let prefer_kinds: &[&str] = if allow {
        &["allow_once", "allow_always", "allow"]
    } else {
        &["reject_once", "reject_always", "reject", "deny"]
    };
    for kind in prefer_kinds {
        for opt in options {
            let k = opt.get("kind").and_then(Value::as_str).unwrap_or("");
            if k == *kind {
                if let Some(oid) = opt.get("optionId").and_then(Value::as_str) {
                    return Some(oid.to_string());
                }
            }
        }
    }
    // 再按 optionId 文本匹配
    let prefer_ids: &[&str] = if allow {
        &["allow-once", "allow-always", "allow", "allow_once"]
    } else {
        &["reject-once", "reject-always", "reject", "deny"]
    };
    for want in prefer_ids {
        for opt in options {
            if opt.get("optionId").and_then(Value::as_str) == Some(*want) {
                return Some((*want).to_string());
            }
        }
    }
    if allow {
        options
            .first()
            .and_then(|o| o.get("optionId"))
            .and_then(Value::as_str)
            .map(str::to_string)
    } else {
        options
            .iter()
            .rev()
            .find_map(|o| o.get("optionId").and_then(Value::as_str).map(str::to_string))
    }
}

fn permission_response(rpc_id: &Value, params: &Value, allow: bool) -> Value {
    if allow {
        let option_id =
            pick_option_id(params, true).unwrap_or_else(|| "allow-once".to_string());
        json!({
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {
                "outcome": {
                    "outcome": "selected",
                    "optionId": option_id
                }
            }
        })
    } else if let Some(option_id) = pick_option_id(params, false) {
        json!({
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {
                "outcome": {
                    "outcome": "selected",
                    "optionId": option_id
                }
            }
        })
    } else {
        json!({
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {
                "outcome": { "outcome": "cancelled" }
            }
        })
    }
}

impl AgentHandle {
    pub async fn spawn(
        settings: &AppSettings,
        workspace: &str,
        thread_id: String,
        app: AppHandle,
        permission_waiters: Arc<Mutex<HashMap<String, oneshot::Sender<bool>>>>,
        live_settings: Arc<Mutex<AppSettings>>,
    ) -> Result<Self> {
        let workspace = absolutize(workspace)?;
        let api_key = if !settings.api_key.trim().is_empty() {
            Some(settings.api_key.trim().to_string())
        } else {
            std::env::var("XAI_API_KEY")
                .or_else(|_| std::env::var("OPENAI_API_KEY"))
                .ok()
        };
        let base = settings.api_base_url.trim().trim_end_matches('/').to_string();

        // 网关模型 id 区分大小写。用户填 GPT-5.6-sol、网关是 gpt-5.6-sol 时会选错模型。
        let model_id = {
            let raw = settings.model_id.trim().to_string();
            if raw.is_empty() || base.is_empty() {
                raw
            } else {
                let key = api_key.clone().unwrap_or_default();
                let wanted = raw.clone();
                let base_c = base.clone();
                tokio::task::spawn_blocking(move || {
                    crate::model_resolve::resolve_gateway_model_id(&base_c, &key, &wanted)
                })
                .await
                .unwrap_or(raw)
            }
        };
        if !model_id.is_empty() && model_id != settings.model_id.trim() {
            warn!(
                "模型 ID 已对齐网关：`{}` → `{}`",
                settings.model_id.trim(),
                model_id
            );
        }

        // `grok agent stdio --model X` 会直接报错退出；正确写法是全局 `-m` 在子命令前：
        //   grok -m <model> agent stdio
        let mut args: Vec<String> = Vec::new();
        if !model_id.is_empty()
            && !settings
                .grok_args
                .iter()
                .any(|a| a == "--model" || a == "-m")
        {
            args.push("-m".into());
            args.push(model_id.clone());
        }
        args.extend(settings.grok_args.iter().cloned());

        // macOS 用户刚按引导安装 Grok 后，设置中可能仍保留旧的 `grok` 值。
        // 每次启动 Agent 时重新解析，可直接使用 ~/.grok/bin/grok。
        let grok_command = crate::models::resolve_grok_command(&settings.grok_command);
        let mut command = Command::new(&grok_command);
        command
            .args(&args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .current_dir(&workspace)
            .kill_on_drop(true);

        // Windows：grok / MCP 控制台程序不设此标志会弹 CMD。
        crate::process_win::hide_console_tokio(&mut command);

        if let Some(key) = api_key {
            command.env("XAI_API_KEY", &key);
            command.env("OPENAI_API_KEY", &key);
        }

        if !base.is_empty() {
            command.env("GROK_MODELS_BASE_URL", &base);
            command.env("OPENAI_BASE_URL", &base);
            command.env("OPENAI_API_BASE", &base);
        }

        if !model_id.is_empty() {
            // 官方文档：GROK_DEFAULT_MODEL；部分发行版也认 GROK_MODEL / OPENAI_MODEL
            command.env("GROK_DEFAULT_MODEL", &model_id);
            command.env("GROK_MODEL", &model_id);
            command.env("OPENAI_MODEL", &model_id);
        }

        let mut child = command
            .spawn()
            .with_context(|| {
                format!(
                    "无法启动 Nova Build Agent：{}（请确认已安装 Agent CLI，或在设置里填写完整路径）",
                    settings.grok_command
                )
            })?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("Failed to open agent stdin"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("Failed to open agent stdout"))?;
        let stderr = child.stderr.take();

        let (out_tx, mut out_rx) = mpsc::unbounded_channel::<String>();
        tokio::spawn(async move {
            let mut stdin = stdin;
            while let Some(line) = out_rx.recv().await {
                if stdin.write_all(line.as_bytes()).await.is_err() {
                    break;
                }
                if stdin.write_all(b"\n").await.is_err() {
                    break;
                }
                if stdin.flush().await.is_err() {
                    break;
                }
            }
        });

        let writer = OutboundWriter { tx: out_tx };
        let pending: Arc<Mutex<HashMap<String, oneshot::Sender<Result<Value>>>>> =
            Arc::new(Mutex::new(HashMap::new()));
        let pending_reader = Arc::clone(&pending);
        let app_stderr = app.clone();
        let app_reader = app.clone();
        let outbound_reader = OutboundWriter {
            tx: writer.tx.clone(),
        };
        let permission_waiters_reader = Arc::clone(&permission_waiters);
        let live_settings_reader = Arc::clone(&live_settings);

        tokio::spawn(async move {
            if let Some(stderr) = stderr {
                let mut reader = BufReader::new(stderr).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    debug!(target: "grok.stderr", "{line}");
                    let _ = app_stderr.emit(
                        "agent://log",
                        json!({ "level": "stderr", "message": line }),
                    );
                }
            }
        });

        tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }

                let value: Value = match serde_json::from_str(trimmed) {
                    Ok(value) => value,
                    Err(err) => {
                        warn!("Invalid JSON from agent: {err}; line={trimmed}");
                        continue;
                    }
                };

                // Agent 可能回数字或字符串 id；必须两种都能匹配，否则会永久卡住。
                if let Some(id_key) = value.get("id").and_then(rpc_id_key) {
                    if value.get("result").is_some() || value.get("error").is_some() {
                        if let Some(sender) = pending_reader.lock().remove(&id_key) {
                            if let Some(error) = value.get("error") {
                                let _ = sender.send(Err(anyhow!("Agent error: {error}")));
                            } else {
                                let _ = sender.send(Ok(
                                    value.get("result").cloned().unwrap_or(Value::Null),
                                ));
                            }
                        }
                        continue;
                    }
                }

                if let Some(method) = value.get("method").and_then(Value::as_str) {
                    match method {
                        "session/update" => {
                            if let Some(params) = value.get("params") {
                                let session_id = params
                                    .get("sessionId")
                                    .and_then(Value::as_str)
                                    .unwrap_or_default()
                                    .to_string();
                                let update = params.get("update").cloned().unwrap_or(Value::Null);
                                let _ = app_reader.emit(
                                    "agent://session-update",
                                    SessionUpdateEvent {
                                        thread_id: thread_id.clone(),
                                        session_id,
                                        update,
                                    },
                                );
                            }
                        }
                        "session/request_permission" => {
                            let rpc_id = value.get("id").cloned().unwrap_or(Value::Null);
                            let params = value.get("params").cloned().unwrap_or(Value::Null);
                            let id_key = rpc_id_key(&rpc_id);

                            let auto = live_settings_reader.lock().auto_approve_permissions;

                            if auto {
                                // 自动批准：不弹窗，直接回允许
                                if let Err(err) = outbound_reader
                                    .send(permission_response(&rpc_id, &params, true))
                                {
                                    error!("Failed to respond to permission: {err}");
                                }
                            } else if let Some(id_key) = id_key {
                                // 先登记 waiter，再通知前端，避免点「允许」时请求还不存在
                                let (tx, rx) = oneshot::channel();
                                permission_waiters_reader.lock().insert(id_key.clone(), tx);

                                let tool_call = params.get("toolCall").cloned().unwrap_or(Value::Null);
                                let title = tool_call
                                    .get("title")
                                    .and_then(Value::as_str)
                                    .unwrap_or("工具权限请求")
                                    .to_string();

                                let _ = app_reader.emit(
                                    "agent://permission-request",
                                    json!({
                                        "id": rpc_id,
                                        "title": title,
                                        "params": params,
                                    }),
                                );

                                let outbound = outbound_reader.clone();
                                let waiters = Arc::clone(&permission_waiters_reader);
                                let id_for_cleanup = id_key;
                                tokio::spawn(async move {
                                    let allow = match tokio::time::timeout(
                                        std::time::Duration::from_secs(300),
                                        rx,
                                    )
                                    .await
                                    {
                                        Ok(Ok(v)) => v,
                                        _ => {
                                            waiters.lock().remove(&id_for_cleanup);
                                            false
                                        }
                                    };

                                    if let Err(err) =
                                        outbound.send(permission_response(&rpc_id, &params, allow))
                                    {
                                        error!("Failed to respond to permission: {err}");
                                    }
                                });
                            } else {
                                // 无法识别 id：拒绝以免卡死
                                if let Err(err) = outbound_reader
                                    .send(permission_response(&rpc_id, &params, false))
                                {
                                    error!("Failed to respond to permission: {err}");
                                }
                            }
                        }
                        "fs/read_text_file" | "fs/write_text_file" => {
                            let rpc_id = value.get("id").cloned();
                            let params = value.get("params");
                            if let (Some(rpc_id), Some(params)) = (rpc_id, params) {
                                // id 可能是 number 或 string；只认 u64 会导致不回包，Agent 整轮卡住
                                if rpc_id_key(&rpc_id).is_some() {
                                    let response = handle_fs_request(
                                        method,
                                        params,
                                        &app_reader,
                                        &thread_id,
                                    );
                                    let payload = if response.error.is_some() {
                                        json!({
                                            "jsonrpc": "2.0",
                                            "id": rpc_id,
                                            "error": response.error
                                        })
                                    } else {
                                        json!({
                                            "jsonrpc": "2.0",
                                            "id": rpc_id,
                                            "result": response.result
                                        })
                                    };
                                    if let Err(err) = outbound_reader.send(payload) {
                                        error!("Failed to respond to fs request: {err}");
                                    }
                                }
                            }
                        }
                        other => {
                            // 带 id 的未知请求必须回错误，否则 Agent 会一直等导致 UI 卡住
                            if let Some(rpc_id) = value.get("id").cloned() {
                                if rpc_id_key(&rpc_id).is_some() {
                                    let payload = json!({
                                        "jsonrpc": "2.0",
                                        "id": rpc_id,
                                        "error": {
                                            "code": -32601,
                                            "message": format!("Method not supported by Nova Desktop: {other}")
                                        }
                                    });
                                    if let Err(err) = outbound_reader.send(payload) {
                                        error!("Failed to respond to unsupported method: {err}");
                                    }
                                }
                            } else {
                                debug!("Unhandled agent notification: {other}");
                            }
                        }
                    }
                }
            }

            // 进程退出只影响所属 thread；全局连接状态不能据此断开其他会话。
        });

        let mut handle = Self {
            child: AsyncMutex::new(child),
            writer,
            pending,
            session_id: None,
            workspace: workspace.clone(),
            model_id: model_id.clone(),
            config_fingerprint: {
                let mut s = settings.clone();
                s.model_id = model_id;
                settings_fingerprint(&s)
            },
            supports_images: false,
            supports_embedded_context: false,
        };

        // 参数错误时 grok 会立刻退出；尽快失败，避免 UI 卡在「正在启动」几十秒。
        {
            tokio::time::sleep(std::time::Duration::from_millis(120)).await;
            let mut child = handle.child.lock().await;
            if let Ok(Some(status)) = child.try_wait() {
                return Err(anyhow!(
                    "Agent 进程启动后立即退出（{status}）。请检查 Agent 命令参数；模型请用 `-m <id> agent stdio`，不要写成 `agent stdio --model`。"
                ));
            }
        }

        handle.initialize().await?;
        let session_id = handle
            .session_new(&workspace, &settings.mcp_servers)
            .await?;
        handle.session_id = Some(session_id);

        Ok(handle)
    }

    fn send(&self, payload: Value) -> Result<()> {
        self.writer.send(payload)
    }

    async fn request(&self, method: &str, params: Value) -> Result<Value> {
        let id = REQUEST_ID.fetch_add(1, Ordering::Relaxed);
        let id_key = id.to_string();
        let (tx, rx) = oneshot::channel();
        self.pending.lock().insert(id_key.clone(), tx);
        self.send(json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        }))?;

        // session/prompt 可能很长；握手类请求超时后应明确报错，避免 UI 一直「分析中」。
        let timeout_secs: u64 = if method == "session/prompt" { 900 } else { 90 };
        match tokio::time::timeout(std::time::Duration::from_secs(timeout_secs), rx).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(anyhow!("Agent 请求通道已关闭（{method}）")),
            Err(_) => {
                self.pending.lock().remove(&id_key);
                Err(anyhow!(
                    "等待 Agent 响应超时（{method}，{timeout_secs}s）。请确认已安装 grok CLI、API Key / Base URL 正确，且 Agent 进程未卡死。"
                ))
            }
        }
    }

    async fn initialize(&mut self) -> Result<()> {
        let result = self
            .request(
                "initialize",
                json!({
                    "protocolVersion": 1,
                    "clientCapabilities": {
                        "fs": {
                            "readTextFile": true,
                            "writeTextFile": true
                        }
                    },
                    "clientInfo": {
                    "name": "nova-build",
                        "version": env!("CARGO_PKG_VERSION")
                    }
                }),
            )
            .await?;

        self.supports_images = result
            .pointer("/capabilities/promptCapabilities/image")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        self.supports_embedded_context = result
            .pointer("/capabilities/promptCapabilities/embeddedContext")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        debug!(
            "initialize result: {result}; image prompt support: {}, embedded context support: {}",
            self.supports_images,
            self.supports_embedded_context
        );
        Ok(())
    }

    async fn session_new(
        &self,
        workspace: &str,
        mcp_servers: &[crate::models::McpServerConfig],
    ) -> Result<String> {
        let servers: Vec<_> = mcp_servers
            .iter()
            .map(|s| {
                // nova-builtin → 当前 exe --mcp-server …（不依赖 Node）
                let (command, args) = crate::mcp::expand_builtin_mcp(&s.command, &s.args)
                    .unwrap_or_else(|| (s.command.clone(), s.args.clone()));
                // Windows 再包一层无窗口启动（对本机 exe 通常会跳过）
                let (command, args) = crate::process_win::wrap_mcp_command(&command, &args);
                json!({
                    "name": s.name,
                    "command": command,
                    "args": args,
                    "env": s.env.iter().map(|e| json!({
                        "name": e.name,
                        "value": e.value
                    })).collect::<Vec<_>>()
                })
            })
            .collect();

        let result = self
            .request(
                "session/new",
                json!({
                    "cwd": workspace,
                    "mcpServers": servers
                }),
            )
            .await?;

        result
            .get("sessionId")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| anyhow!("session/new did not return sessionId"))
    }

    pub async fn send_prompt(&self, text: &str, attachments: &[PromptAttachment]) -> Result<Value> {
        let session_id = self
            .session_id
            .clone()
            .ok_or_else(|| anyhow!("No active session"))?;

        let mut prompt = vec![json!({
            "type": "text",
            "text": text
        })];
        for attachment in attachments {
            if attachment.mime_type.starts_with("image/") {
                if !self.supports_images {
                    // 某些 Agent 实现未正确声明 capability，但仍能处理 ACP image 块。
                    // 将请求继续转发，由 Agent 返回实际的协议错误，而不是客户端提前拦截。
                    warn!(
                        "Agent did not advertise image prompt support; forwarding image attachment anyway"
                    );
                }
                if attachment.encoding != "base64"
                    || attachment.data.len() > MAX_BINARY_ATTACHMENT_BYTES * 4 / 3
                {
                    return Err(anyhow!("图片附件格式或大小无效：{}", attachment.name));
                }
                prompt.push(json!({
                    "type": "image",
                    "mimeType": attachment.mime_type,
                    "data": attachment.data
                }));
            } else if attachment.encoding == "utf8" {
                if attachment.size > 512 * 1024 {
                    return Err(anyhow!("文本附件大小无效：{}", attachment.name));
                }
                prompt.push(json!({
                    "type": "text",
                    "text": format!("\n\n--- 文件：{} ---\n{}", attachment.name, attachment.data)
                }));
            } else if attachment.mime_type
                == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            {
                if attachment.encoding != "base64" {
                    return Err(anyhow!("Excel 附件格式无效：{}", attachment.name));
                }
                prompt.push(json!({
                    "type": "text",
                    "text": excel_attachment_to_text(attachment)?
                }));
            } else {
                if !self.supports_embedded_context {
                    return Err(anyhow!(
                        "当前 Agent 未声明支持文件上下文，无法发送 {}",
                        attachment.name
                    ));
                }
                if attachment.encoding != "base64"
                    || attachment.size > MAX_BINARY_ATTACHMENT_BYTES as u64
                    || attachment.data.len() > MAX_BINARY_ATTACHMENT_BYTES * 4 / 3
                {
                    return Err(anyhow!("文件附件格式或大小无效：{}", attachment.name));
                }
                prompt.push(json!({
                    "type": "resource",
                    "resource": {
                        "uri": format!("attachment://{}", uuid::Uuid::new_v4()),
                        "mimeType": attachment.mime_type,
                        "blob": attachment.data
                    }
                }));
            }
        }

        self.request(
            "session/prompt",
            json!({
                "sessionId": session_id,
                "prompt": prompt
            }),
        )
        .await
    }

    pub async fn cancel_prompt(&self) -> Result<()> {
        let session_id = self
            .session_id
            .clone()
            .ok_or_else(|| anyhow!("No active session"))?;
        // ACP session/cancel is a fire-and-forget notification.
        self.send(json!({
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": {
                "sessionId": session_id
            }
        }))
    }

    pub fn session_id(&self) -> Option<&str> {
        self.session_id.as_deref()
    }

    pub fn workspace(&self) -> &str {
        &self.workspace
    }

    pub fn model_id(&self) -> &str {
        &self.model_id
    }

    pub fn config_fingerprint(&self) -> &str {
        &self.config_fingerprint
    }

    pub async fn shutdown(&self) -> Result<()> {
        let mut child = self.child.lock().await;
        let _ = child.start_kill();
        let _ = child.wait().await;
        Ok(())
    }
}

struct FsResponse {
    result: Option<Value>,
    error: Option<Value>,
}

fn handle_fs_request(
    method: &str,
    params: &Value,
    app: &AppHandle,
    thread_id: &str,
) -> FsResponse {
    let path = params
        .get("path")
        .and_then(Value::as_str)
        .unwrap_or_default();

    match method {
        "fs/read_text_file" => {
            let line = params.get("line").and_then(Value::as_u64);
            let limit = params.get("limit").and_then(Value::as_u64);
            match read_text_file(path) {
                Ok(content) => {
                    let content = apply_line_limit(&content, line, limit);
                    FsResponse {
                        result: Some(json!({ "content": content })),
                        error: None,
                    }
                }
                Err(err) => FsResponse {
                    result: None,
                    error: Some(json!({
                        "code": -32000,
                        "message": err.to_string()
                    })),
                },
            }
        }
        "fs/write_text_file" => {
            let content = params
                .get("content")
                .and_then(Value::as_str)
                .unwrap_or_default();
            match write_text_file_with_diff(path, content) {
                Ok(info) => {
                    let _ = app.emit(
                        "agent://workspace-changed",
                        json!({ "path": path }),
                    );
                    let _ = app.emit(
                        "agent://file-edited",
                        json!({
                            "threadId": thread_id,
                            "path": path,
                            "created": info.created,
                            "diff": info.diff,
                        }),
                    );
                    FsResponse {
                        result: Some(json!({
                            "path": path,
                            "created": info.created,
                            "diff": info.diff,
                        })),
                        error: None,
                    }
                }
                Err(err) => FsResponse {
                    result: None,
                    error: Some(json!({
                        "code": -32000,
                        "message": err.to_string()
                    })),
                },
            }
        }
        _ => FsResponse {
            result: None,
            error: Some(json!({
                "code": -32601,
                "message": format!("Unsupported method: {method}")
            })),
        },
    }
}

fn apply_line_limit(content: &str, line: Option<u64>, limit: Option<u64>) -> String {
    let Some(start) = line.filter(|&n| n >= 1) else {
        return match limit {
            Some(n) if n > 0 => content.lines().take(n as usize).collect::<Vec<_>>().join("\n"),
            _ => content.to_string(),
        };
    };
    let skip = (start as usize).saturating_sub(1);
    let lines = content.lines().skip(skip);
    match limit {
        Some(n) if n > 0 => lines.take(n as usize).collect::<Vec<_>>().join("\n"),
        _ => lines.collect::<Vec<_>>().join("\n"),
    }
}
