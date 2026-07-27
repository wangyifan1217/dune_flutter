use std::path::PathBuf;
use std::sync::Arc;

use base64::{engine::general_purpose::STANDARD, Engine};
use calamine::{open_workbook_auto, Data, Reader};
use serde::Serialize;
use tauri::{AppHandle, Emitter, State};
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_store::StoreExt;

use crate::models::{AgentStatus, AppSettings, ChatMessage, FileEntry};
use crate::state::AppState;
use crate::workspace::{absolutize, build_tree, list_directory, DirectoryTreeNode};

const SETTINGS_STORE: &str = "settings.json";
const SETTINGS_KEY: &str = "app";
const MCP_SEED_KEY: &str = "mcpRecommendedSeeded";
const MAX_BINARY_ATTACHMENT_BYTES: u64 = 10 * 1024 * 1024;
const MAX_TEXT_ATTACHMENT_BYTES: u64 = 512 * 1024;

#[tauri::command]
pub fn get_settings(app: AppHandle) -> Result<AppSettings, String> {
    let store = app.store(SETTINGS_STORE).map_err(|e| e.to_string())?;
    if let Some(value) = store.get(SETTINGS_KEY) {
        let mut settings: AppSettings =
            serde_json::from_value(value).map_err(|e| e.to_string())?;
        // 仅首次空列表时注入推荐套件；用户清空后不再强行加回
        if settings.mcp_servers.is_empty() && store.get(MCP_SEED_KEY).is_none() {
            settings.mcp_servers = crate::models::recommended_mcp_servers();
            store.set(
                SETTINGS_KEY,
                serde_json::to_value(&settings).map_err(|e| e.to_string())?,
            );
            store.set(MCP_SEED_KEY, serde_json::Value::Bool(true));
            store.save().map_err(|e| e.to_string())?;
        }
        Ok(settings)
    } else {
        let settings = AppSettings::default();
        store.set(
            SETTINGS_KEY,
            serde_json::to_value(&settings).map_err(|e| e.to_string())?,
        );
        store.set(MCP_SEED_KEY, serde_json::Value::Bool(true));
        store.save().map_err(|e| e.to_string())?;
        Ok(settings)
    }
}

#[tauri::command]
pub fn save_settings(app: AppHandle, settings: AppSettings) -> Result<(), String> {
    let store = app.store(SETTINGS_STORE).map_err(|e| e.to_string())?;
    store.set(
        SETTINGS_KEY,
        serde_json::to_value(settings).map_err(|e| e.to_string())?,
    );
    store.save().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn get_agent_status(state: State<'_, Arc<AppState>>) -> AgentStatus {
    state.snapshot_status()
}

#[tauri::command]
pub fn get_grok_installation(
    state: State<'_, Arc<AppState>>,
) -> crate::models::GrokInstallationStatus {
    let configured = state.settings.lock().grok_command.clone();
    crate::models::grok_installation_status(&configured)
}

fn mime_type_for(path: &std::path::Path) -> &'static str {
    match path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "pdf" => "application/pdf",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "zip" => "application/zip",
        _ => "application/octet-stream",
    }
}

/// Reads files that the user explicitly dropped onto the native application window.
#[tauri::command]
pub fn read_dropped_files(paths: Vec<String>) -> Result<Vec<crate::models::DroppedFile>, String> {
    paths
        .into_iter()
        .map(|path| {
            let path = PathBuf::from(path);
            let metadata = std::fs::metadata(&path).map_err(|e| e.to_string())?;
            if !metadata.is_file() {
                return Err(format!("{} 不是文件", path.display()));
            }
            let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
            let name = path
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| "未命名文件".into());

            match String::from_utf8(bytes.clone()) {
                Ok(text) if metadata.len() <= MAX_TEXT_ATTACHMENT_BYTES => Ok(crate::models::DroppedFile {
                    name,
                    mime_type: "text/plain".into(),
                    size: metadata.len(),
                    encoding: "utf8".into(),
                    data: text,
                }),
                _ if metadata.len() <= MAX_BINARY_ATTACHMENT_BYTES => Ok(crate::models::DroppedFile {
                    name,
                    mime_type: mime_type_for(&path).into(),
                    size: metadata.len(),
                    encoding: "base64".into(),
                    data: STANDARD.encode(bytes),
                }),
                _ => Err(format!(
                    "{} 超过 {} MB 限制",
                    path.display(),
                    MAX_BINARY_ATTACHMENT_BYTES / 1024 / 1024
                )),
            }
        })
        .collect()
}

const MAX_PREVIEW_TEXT_CHARS: usize = 200_000;
const MAX_PREVIEW_IMAGE_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PreviewSlide {
    pub title: String,
    pub body: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FilePreviewPayload {
    pub kind: String,
    pub path: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mime: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_base64: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slides: Option<Vec<PreviewSlide>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sheet: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub headers: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rows: Option<Vec<Vec<String>>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

fn resolve_user_path(
    state: &AppState,
    path: &str,
) -> Result<(PathBuf, Option<PathBuf>), String> {
    let requested = PathBuf::from(path);
    if requested.is_absolute() {
        Ok((requested, None))
    } else {
        let workspace = state
            .workspace
            .lock()
            .clone()
            .unwrap_or(default_agent_workspace()?);
        let root = std::fs::canonicalize(&workspace).map_err(|e| e.to_string())?;
        Ok((root.join(&requested), Some(root)))
    }
}

fn canonicalize_checked(
    candidate: PathBuf,
    workspace_root: Option<PathBuf>,
) -> Result<PathBuf, String> {
    let canonical = std::fs::canonicalize(&candidate)
        .map_err(|_| format!("找不到文件：{}", candidate.display()))?;
    if workspace_root
        .as_ref()
        .is_some_and(|root| !canonical.starts_with(root))
    {
        return Err("相对路径不能超出当前项目文件夹".into());
    }
    if !canonical.is_file() {
        return Err("只能打开文件，不能打开文件夹".into());
    }
    Ok(canonical)
}

fn cell_to_string(c: &Data) -> String {
    match c {
        Data::Empty => String::new(),
        Data::String(s) => s.replace('\n', " "),
        Data::Float(f) => f.to_string(),
        Data::Int(i) => i.to_string(),
        Data::Bool(b) => b.to_string(),
        Data::DateTime(dt) => format!("{dt:?}"),
        Data::DateTimeIso(s) | Data::DurationIso(s) => s.clone(),
        Data::Error(e) => format!("#ERR:{e:?}"),
    }
}

fn parse_pptx_slides(raw: &str) -> Vec<PreviewSlide> {
    let mut slides = Vec::new();
    for block in raw.split("--- slide ") {
        let block = block.trim();
        if block.is_empty() {
            continue;
        }
        let body = block
            .lines()
            .skip(1)
            .collect::<Vec<_>>()
            .join("\n")
            .trim()
            .to_string();
        let first_line = body.lines().next().unwrap_or("幻灯片").trim();
        let title = if first_line.chars().count() > 48 {
            format!("{}…", first_line.chars().take(48).collect::<String>())
        } else if first_line.is_empty() {
            "幻灯片".into()
        } else {
            first_line.to_string()
        };
        slides.push(PreviewSlide { title, body });
    }
    if slides.is_empty() && !raw.trim().is_empty() {
        slides.push(PreviewSlide {
            title: "内容".into(),
            body: raw.trim().to_string(),
        });
    }
    slides
}

/// Opens a file explicitly referenced in an agent response.
/// Relative paths resolve against the selected workspace; if none is open, fall back to the
/// same default cwd used by the agent (user home), so generated files remain openable.
#[tauri::command]
pub fn open_generated_file(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), String> {
    let (candidate, workspace_root) = resolve_user_path(state.inner(), &path)?;
    let canonical = canonicalize_checked(candidate, workspace_root)?;
    app.opener()
        .open_path(canonical.to_string_lossy(), None::<String>)
        .map_err(|e| e.to_string())
}

/// 右侧预览：按扩展名返回可读内容（非完整 Office 编辑器）。
#[tauri::command]
pub fn preview_file(
    state: State<'_, Arc<AppState>>,
    path: String,
) -> Result<FilePreviewPayload, String> {
    let (candidate, workspace_root) = resolve_user_path(state.inner(), &path)?;
    let canonical = canonicalize_checked(candidate, workspace_root)?;
    let path_str = canonical.to_string_lossy().into_owned();
    let name = canonical
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path_str.clone());
    let ext = canonical
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    match ext.as_str() {
        "md" | "markdown" => {
            let text = crate::workspace::read_text_file(&path_str).map_err(|e| e.to_string())?;
            let clipped = truncate_chars(&text, MAX_PREVIEW_TEXT_CHARS);
            Ok(FilePreviewPayload {
                kind: "markdown".into(),
                path: path_str,
                name,
                text: Some(clipped),
                mime: None,
                image_base64: None,
                slides: None,
                sheet: None,
                headers: None,
                rows: None,
                message: None,
            })
        }
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "bmp" => {
            let meta = std::fs::metadata(&canonical).map_err(|e| e.to_string())?;
            if meta.len() > MAX_PREVIEW_IMAGE_BYTES {
                return Ok(FilePreviewPayload {
                    kind: "unsupported".into(),
                    path: path_str,
                    name,
                    text: None,
                    mime: None,
                    image_base64: None,
                    slides: None,
                    sheet: None,
                    headers: None,
                    rows: None,
                    message: Some("图片过大，请用系统打开查看".into()),
                });
            }
            let bytes = std::fs::read(&canonical).map_err(|e| e.to_string())?;
            let mime = match ext.as_str() {
                "png" => "image/png",
                "jpg" | "jpeg" => "image/jpeg",
                "gif" => "image/gif",
                "webp" => "image/webp",
                "svg" => "image/svg+xml",
                "bmp" => "image/bmp",
                _ => "application/octet-stream",
            };
            Ok(FilePreviewPayload {
                kind: "image".into(),
                path: path_str,
                name,
                text: None,
                mime: Some(mime.into()),
                image_base64: Some(STANDARD.encode(bytes)),
                slides: None,
                sheet: None,
                headers: None,
                rows: None,
                message: None,
            })
        }
        "pptx" => {
            let raw = crate::office::extract_pptx_text(&path_str).map_err(|e| e.to_string())?;
            let slides = parse_pptx_slides(&raw);
            Ok(FilePreviewPayload {
                kind: "pptx".into(),
                path: path_str,
                name,
                text: None,
                mime: None,
                image_base64: None,
                slides: Some(slides),
                sheet: None,
                headers: None,
                rows: None,
                message: None,
            })
        }
        "xlsx" | "xls" => {
            let mut wb = open_workbook_auto(&path_str).map_err(|e| e.to_string())?;
            let sheet = wb
                .sheet_names()
                .first()
                .cloned()
                .ok_or_else(|| "工作簿没有工作表".to_string())?;
            let range = wb
                .worksheet_range(&sheet)
                .map_err(|e| format!("无法读取工作表：{e}"))?;
            let mut rows: Vec<Vec<String>> = Vec::new();
            for (r, row) in range.rows().enumerate() {
                if r >= 80 {
                    break;
                }
                let cells: Vec<String> = row.iter().take(20).map(cell_to_string).collect();
                rows.push(cells);
            }
            let headers = rows.first().cloned().unwrap_or_default();
            let data_rows = if rows.len() > 1 {
                rows[1..].to_vec()
            } else {
                Vec::new()
            };
            Ok(FilePreviewPayload {
                kind: "xlsx".into(),
                path: path_str,
                name,
                text: None,
                mime: None,
                image_base64: None,
                slides: None,
                sheet: Some(sheet),
                headers: Some(headers),
                rows: Some(data_rows),
                message: None,
            })
        }
        "html" | "htm" => {
            let text = crate::workspace::read_text_file(&path_str).map_err(|e| e.to_string())?;
            let clipped = truncate_chars(&text, MAX_PREVIEW_TEXT_CHARS);
            Ok(FilePreviewPayload {
                kind: "html".into(),
                path: path_str,
                name,
                text: Some(clipped),
                mime: Some("text/html".into()),
                image_base64: None,
                slides: None,
                sheet: None,
                headers: None,
                rows: None,
                message: None,
            })
        }
        "txt" | "json" | "csv" | "ts" | "tsx" | "js" | "jsx" | "css" | "xml"
        | "yaml" | "yml" | "toml" | "rs" | "py" | "java" | "go" | "c" | "cpp" | "h" | "hpp"
        | "sql" | "sh" | "log" | "ini" | "cfg" | "env" => {
            let text = crate::workspace::read_text_file(&path_str).map_err(|e| e.to_string())?;
            let clipped = truncate_chars(&text, MAX_PREVIEW_TEXT_CHARS);
            Ok(FilePreviewPayload {
                kind: "text".into(),
                path: path_str,
                name,
                text: Some(clipped),
                mime: None,
                image_base64: None,
                slides: None,
                sheet: None,
                headers: None,
                rows: None,
                message: None,
            })
        }
        _ => {
            // 尝试当文本读；失败则 unsupported
            match crate::workspace::read_text_file(&path_str) {
                Ok(text) if text.len() < MAX_PREVIEW_TEXT_CHARS => Ok(FilePreviewPayload {
                    kind: "text".into(),
                    path: path_str,
                    name,
                    text: Some(text),
                    mime: None,
                    image_base64: None,
                    slides: None,
                    sheet: None,
                    headers: None,
                    rows: None,
                    message: None,
                }),
                _ => Ok(FilePreviewPayload {
                    kind: "unsupported".into(),
                    path: path_str,
                    name,
                    text: None,
                    mime: None,
                    image_base64: None,
                    slides: None,
                    sheet: None,
                    headers: None,
                    rows: None,
                    message: Some("此类型暂不支持内嵌预览，可用系统打开".into()),
                }),
            }
        }
    }
}

fn truncate_chars(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let clipped: String = text.chars().take(max).collect();
    format!("{clipped}\n…(内容已截断)")
}

fn default_agent_workspace() -> Result<String, String> {
    let home = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .map(PathBuf::from)
        .unwrap_or(std::env::current_dir().map_err(|e| e.to_string())?);
    absolutize(home.to_string_lossy().as_ref()).map_err(|e| e.to_string())
}

/// 无项目时以用户主目录作为 Agent 的工作目录，仍可进行普通对话。
#[tauri::command]
pub async fn connect_default_agent(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<AgentStatus, String> {
    let workspace = state
        .workspace
        .lock()
        .clone()
        .unwrap_or(default_agent_workspace()?);
    state
        .connect(&workspace, app.clone())
        .await
        .map_err(|e| e.to_string())?;
    // Agent 仍需要一个 cwd；这里不把默认目录当作用户已打开的项目。
    *state.workspace.lock() = None;
    let status = AgentStatus {
        connected: true,
        session_id: None,
        workspace: None,
        message: "已连接（未打开项目）".into(),
    };
    state.set_status(status.clone());
    let _ = app.emit("agent://status", &status);
    Ok(status)
}

#[tauri::command]
pub async fn clear_workspace(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<AgentStatus, String> {
    state.disconnect().await.map_err(|e| e.to_string())?;
    *state.workspace.lock() = None;
    let status = AgentStatus {
        connected: false,
        session_id: None,
        workspace: None,
        message: "未打开项目".into(),
    };
    state.set_status(status.clone());
    let _ = app.emit("agent://status", &status);
    Ok(status)
}

/// 只设置工作区并返回状态；Agent 连接单独调用，避免选文件夹被卡住。
#[tauri::command]
pub async fn set_workspace(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    path: String,
) -> Result<AgentStatus, String> {
    let abs = absolutize(&path).map_err(|e| format!("无效路径：{e}"))?;
    *state.workspace.lock() = Some(abs.clone());

    let status = AgentStatus {
        connected: false,
        session_id: None,
        workspace: Some(abs.clone()),
        message: "工作区已打开，正在连接 Agent…".into(),
    };
    state.set_status(status.clone());
    let _ = app.emit("agent://status", &status);

    // 尝试连接；失败也保留工作区，方便先看文件树
    match state.connect(&abs, app.clone()).await {
        Ok(()) => Ok(state.snapshot_status()),
        Err(err) => {
            let failed = AgentStatus {
                connected: false,
                session_id: None,
                workspace: Some(abs),
                message: format!("工作区已打开，但 Agent 连接失败：{err}"),
            };
            state.set_status(failed.clone());
            let _ = app.emit("agent://status", &failed);
            Ok(failed)
        }
    }
}

#[tauri::command]
pub async fn disconnect_agent(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<AgentStatus, String> {
    state.disconnect().await.map_err(|e| e.to_string())?;
    let status = state.snapshot_status();
    let _ = app.emit("agent://status", &status);
    Ok(status)
}

#[tauri::command]
pub async fn reconnect_agent(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<AgentStatus, String> {
    let workspace = state
        .workspace
        .lock()
        .clone()
        .ok_or_else(|| "请先打开工作区文件夹".to_string())?;
    state
        .connect(&workspace, app.clone())
        .await
        .map_err(|e| e.to_string())?;
    let status = state.snapshot_status();
    let _ = app.emit("agent://status", &status);
    Ok(status)
}

fn truncate_for_history(content: &str, max_chars: usize) -> String {
    let trimmed = content.trim();
    if trimmed.chars().count() <= max_chars {
        return trimmed.to_string();
    }
    let truncated: String = trimmed.chars().take(max_chars).collect();
    format!("{truncated}\n…(内容已截断)")
}

#[tauri::command]
pub async fn send_prompt(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    thread_id: String,
    text: String,
    attachments: Option<Vec<crate::models::PromptAttachment>>,
    history: Option<Vec<crate::models::PromptHistoryMessage>>,
) -> Result<ChatMessage, String> {
    if thread_id.trim().is_empty() {
        return Err("缺少会话 ID".into());
    }
    let workspace = state
        .workspace
        .lock()
        .clone()
        .unwrap_or(default_agent_workspace()?);
    let _ = app.emit(
        "agent://request-progress",
        serde_json::json!({
            "threadId": thread_id.clone(),
            "stage": "正在启动 Agent（首次可能稍慢）"
        }),
    );
    let agent = state
        .agent_for_session(&thread_id, &workspace, app.clone())
        .await
        .map_err(|e| e.to_string())?;

    let current_model = state.settings.lock().model_id.trim().to_string();

    // 永久记忆、产品身份与中文偏好，拼进每次提问。
    let memory_block = crate::memory::format_for_prompt(&app);
    let mut prompt = String::new();
    if !memory_block.is_empty() {
        prompt.push_str(&memory_block);
        prompt.push_str("\n\n");
    }
    if !current_model.is_empty() {
        prompt.push_str(&format!(
            "【会话模型】当前请求必须使用模型 `{current_model}`（已通过启动参数配置）。\n\n"
        ));
    }
    let self_exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "nova-desktop".into());
    prompt.push_str(&format!(
        "你是 Nova Build 桌面端的 AI 编程助手。\n\
身份与措辞：\n\
- 产品名称是 Nova Build；不要声称自己是 Grok、xAI、Cursor、Claude 或其他第三方产品。\n\
- 不要每条回复都自我介绍；直接回答用户问题。\n\
- 不要在回答中提及底层模型名称或服务提供方。\n\
- 请始终使用简体中文回复。\n\
- 先给结论或可用答案，再按需补充简要说明；避免空泛的「我将要…」式套话。\n\
- 天气、新闻、股价等实时信息：不要凭记忆瞎编。若已启用 fetch MCP，用 fetch_url 拉取可信来源后再回答；\
若工具不可用或失败，明确说「当前无法联网核实」，并给出用户可自行打开的查询链接。\n\n\
运行环境说明：\n\
- 用户使用的是 Nova Build 桌面客户端，不是终端 TUI。\n\
- 不要让用户输入 /cd 等 TUI 命令；切换项目由用户点击「选择项目」完成。\n\
- 需要打开浏览器时，在 Windows 上执行：cmd /c start \"\" \"http://127.0.0.1:端口\"\n\
- 启动 PHP 内置服务器可用：php -S 127.0.0.1:8000 -t <项目目录>；若 php 不存在，请明确说明并给出安装/替代方案。\n\
- 长驻后台进程可能无法在关闭应用后继续运行；请如实告知，并给出可在右侧「终端」手动执行的命令。\n\
- 生成 Office 文档（.pptx / .docx / .xlsx）：客户端的 fs 写文件只能写文本，不能直接写二进制。\
优先使用已启用的内置 MCP（excel / word / powerpoint）创建与读写；\
这些工具由 Nova Build 内置，不依赖 Node.js、Python 或已安装的 Office。\
若用户只要空白 PPT 且未启用 powerpoint MCP，可执行：\n\
  \"{self_exe}\" --create-blank-pptx \"./空白演示文稿.pptx\"\n\
不要用 write_text_file 硬写 .pptx/.docx/.xlsx。\n\n"
    ));

    let history = history.unwrap_or_default();
    if !history.is_empty() {
        prompt.push_str(
            "以下是本对话的近期上下文。这不是新会话，请基于上下文继续，不要说你看不到之前的内容：\n\n",
        );
        for item in history.iter().rev().take(16).collect::<Vec<_>>().into_iter().rev() {
            let role = match item.role.as_str() {
                "user" => "用户",
                "assistant" => "助手",
                other => other,
            };
            prompt.push_str(&format!(
                "[{role}]\n{}\n\n",
                truncate_for_history(&item.content, 2500)
            ));
        }
    }

    prompt.push_str("[用户最新消息]\n");
    prompt.push_str(text.trim());

    let attachments = attachments.unwrap_or_default();
    let _ = app.emit(
        "agent://request-progress",
        serde_json::json!({
            "threadId": thread_id.clone(),
            "stage": "正在等待模型响应"
        }),
    );
    let result = agent
        .send_prompt(&prompt, &attachments)
        .await
        .map_err(|e| e.to_string())?;
    Ok(ChatMessage {
        id: uuid::Uuid::new_v4().to_string(),
        role: "assistant".into(),
        content: result.to_string(),
        status: "completed".into(),
    })
}

#[tauri::command]
pub async fn cancel_prompt(
    state: State<'_, Arc<AppState>>,
    thread_id: String,
) -> Result<(), String> {
    if thread_id.trim().is_empty() {
        return Err("缺少会话 ID".into());
    }
    state
        .cancel_session_prompt(&thread_id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn drop_session_agent(
    state: State<'_, Arc<AppState>>,
    thread_id: String,
) -> Result<(), String> {
    if thread_id.trim().is_empty() {
        return Err("缺少会话 ID".into());
    }
    state.drop_session_agent(&thread_id).await;
    Ok(())
}

#[tauri::command]
pub fn open_url(app: AppHandle, url: String) -> Result<(), String> {
    let url = url.trim();
    if !(url.starts_with("http://") || url.starts_with("https://")) {
        return Err("只能打开 http/https 链接".into());
    }
    app.opener()
        .open_url(url, None::<String>)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn auth_get_api_base(app: AppHandle) -> String {
    crate::auth::get_api_base(&app)
}

#[tauri::command]
pub fn auth_set_api_base(app: AppHandle, api_base: String) -> Result<(), String> {
    crate::auth::set_api_base(&app, &api_base)
}

#[tauri::command]
pub async fn auth_restore_session(
    app: AppHandle,
) -> Result<Option<crate::auth::AuthSession>, String> {
    tokio::task::spawn_blocking(move || crate::auth::restore_session(&app))
        .await
        .map_err(|e| format!("恢复登录中断：{e}"))?
}

#[tauri::command]
pub fn auth_logout(app: AppHandle) -> Result<(), String> {
    crate::auth::clear_session(&app)
}

#[tauri::command]
pub async fn auth_request_sms(app: AppHandle, phone: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || crate::auth::request_sms(&app, &phone))
        .await
        .map_err(|e| format!("请求中断：{e}"))?
}

#[tauri::command]
pub async fn auth_sign_in_sms(
    app: AppHandle,
    phone: String,
    code: String,
) -> Result<crate::auth::AuthSession, String> {
    tokio::task::spawn_blocking(move || crate::auth::sign_in_sms(&app, &phone, &code))
        .await
        .map_err(|e| format!("登录中断：{e}"))?
}

#[tauri::command]
pub async fn auth_create_qr_session(app: AppHandle) -> Result<crate::auth::QrSession, String> {
    tokio::task::spawn_blocking(move || crate::auth::create_qr_session(&app))
        .await
        .map_err(|e| format!("创建二维码中断：{e}"))?
}

#[tauri::command]
pub async fn auth_poll_qr_status(
    app: AppHandle,
    session_id: String,
    client_secret: String,
) -> Result<crate::auth::QrStatus, String> {
    tokio::task::spawn_blocking(move || {
        crate::auth::poll_qr_status(&app, &session_id, &client_secret)
    })
    .await
    .map_err(|e| format!("查询扫码状态中断：{e}"))?
}

#[tauri::command]
pub async fn auth_sign_in_qr(
    app: AppHandle,
    session_id: String,
    client_secret: String,
) -> Result<crate::auth::AuthSession, String> {
    tokio::task::spawn_blocking(move || {
        crate::auth::sign_in_qr(&app, &session_id, &client_secret)
    })
    .await
    .map_err(|e| format!("扫码登录中断：{e}"))?
}

#[tauri::command]
pub fn list_skills(state: State<'_, Arc<AppState>>) -> Result<Vec<crate::skills::SkillInfo>, String> {
    let workspace = state.workspace.lock().clone();
    Ok(crate::skills::list_skills(workspace.as_deref()))
}

#[tauri::command]
pub fn create_skill(
    state: State<'_, Arc<AppState>>,
    scope: String,
    name: String,
    description: String,
) -> Result<crate::skills::SkillInfo, String> {
    let workspace = state.workspace.lock().clone();
    crate::skills::create_skill(workspace.as_deref(), &scope, &name, &description)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn delete_skill(path: String) -> Result<(), String> {
    crate::skills::delete_skill(&path).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn read_skill_markdown(path: String) -> Result<String, String> {
    crate::skills::read_skill_markdown(&path).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn write_skill_markdown(path: String, content: String) -> Result<(), String> {
    crate::skills::write_skill_markdown(&path, &content).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn open_skills_folder(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    scope: String,
) -> Result<String, String> {
    let workspace = state.workspace.lock().clone();
    let dir = crate::skills::skills_folder_path(workspace.as_deref(), &scope)
        .map_err(|e| e.to_string())?;
    let path = dir.to_string_lossy().into_owned();
    app.opener()
        .open_path(path.clone(), None::<String>)
        .map_err(|e| e.to_string())?;
    Ok(path)
}

#[tauri::command]
pub fn list_memories(app: AppHandle) -> Result<Vec<crate::memory::MemoryEntry>, String> {
    crate::memory::load_memories(&app)
}

#[tauri::command]
pub fn add_memory(
    app: AppHandle,
    content: String,
    source: Option<String>,
) -> Result<crate::memory::MemoryEntry, String> {
    crate::memory::add_memory(&app, content, source.unwrap_or_else(|| "user".into()))
}

#[tauri::command]
pub fn delete_memory(app: AppHandle, id: String) -> Result<(), String> {
    crate::memory::delete_memory(&app, &id)
}

#[tauri::command]
pub fn clear_memories(app: AppHandle) -> Result<(), String> {
    crate::memory::clear_memories(&app)
}

#[tauri::command]
pub fn load_sessions(app: AppHandle) -> Result<crate::persist::StoredSessions, String> {
    crate::persist::load_sessions(&app)
}

#[tauri::command]
pub fn save_sessions(
    app: AppHandle,
    sessions: serde_json::Value,
    active_id: Option<String>,
) -> Result<(), String> {
    crate::persist::save_sessions(
        &app,
        &crate::persist::StoredSessions {
            sessions,
            active_id,
        },
    )
}

#[tauri::command]
pub fn list_workspace(path: String) -> Result<Vec<FileEntry>, String> {
    list_directory(&path).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_workspace_tree(path: String) -> Result<DirectoryTreeNode, String> {
    // 深度 1 + 后台线程，避免选项目时卡死 UI
    tokio::task::spawn_blocking(move || build_tree(&path, 1))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn read_workspace_file(path: String) -> Result<String, String> {
    crate::workspace::read_text_file(&path).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn update_runtime_settings(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    settings: AppSettings,
) -> Result<AppSettings, String> {
    let prev = state.settings.lock().clone();
    let mut settings = settings;

    // 防止设置页未加载完 / 空草稿误把已有网关配置清空
    let incoming_empty = settings.api_key.trim().is_empty()
        && settings.api_base_url.trim().is_empty()
        && settings.models.is_empty()
        && settings.model_id.trim().is_empty();
    let prev_has_config = !prev.api_key.trim().is_empty()
        || !prev.api_base_url.trim().is_empty()
        || !prev.models.is_empty();
    if incoming_empty && prev_has_config {
        return Err("已忽略空配置覆盖，避免清空现有 Base URL / API Key / 模型列表".into());
    }
    if !settings.model_id.trim().is_empty() && !settings.api_base_url.trim().is_empty() {
        let base = settings.api_base_url.clone();
        let key = settings.api_key.clone();
        let wanted = settings.model_id.clone();
        let resolved = tokio::task::spawn_blocking(move || {
            crate::model_resolve::resolve_gateway_model_id(&base, &key, &wanted)
        })
        .await
        .unwrap_or_else(|_| settings.model_id.clone());
        if !resolved.is_empty() {
            for m in &mut settings.models {
                if m.id.eq_ignore_ascii_case(&resolved) {
                    m.id = resolved.clone();
                }
            }
            settings.model_id = resolved;
        }
    }

    save_settings(app.clone(), settings.clone())?;
    *state.settings.lock() = settings.clone();

    // 不在这里杀掉全部 Agent：其它会话可能正在分析。
    // 各会话下次 send_prompt 时按 config_fingerprint 惰性重建进程。
    Ok(settings)
}

#[tauri::command]
pub fn respond_permission(
    state: State<'_, Arc<AppState>>,
    id: serde_json::Value,
    allow: bool,
) -> Result<(), String> {
    let key = match &id {
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::String(s) => s.clone(),
        other => other.to_string(),
    };
    if state.resolve_permission(&key, allow) {
        Ok(())
    } else {
        Err("权限请求不存在或已过期，请重试或重新发送指令".into())
    }
}

#[tauri::command]
pub async fn git_list_changes(
    state: State<'_, Arc<AppState>>,
) -> Result<Vec<crate::git::GitFileChange>, String> {
    let cwd = state
        .workspace
        .lock()
        .clone()
        .ok_or_else(|| "请先打开工作区".to_string())?;
    tokio::task::spawn_blocking(move || crate::git::list_changes(&cwd))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn git_file_diff(
    state: State<'_, Arc<AppState>>,
    path: String,
) -> Result<String, String> {
    let cwd = state
        .workspace
        .lock()
        .clone()
        .ok_or_else(|| "请先打开工作区".to_string())?;
    tokio::task::spawn_blocking(move || crate::git::file_diff(&cwd, &path))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn git_accept_change(state: State<'_, Arc<AppState>>, path: String) -> Result<(), String> {
    let cwd = state
        .workspace
        .lock()
        .clone()
        .ok_or_else(|| "请先打开工作区".to_string())?;
    tokio::task::spawn_blocking(move || crate::git::accept_change(&cwd, &path))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn git_reject_change(state: State<'_, Arc<AppState>>, path: String) -> Result<(), String> {
    let cwd = state
        .workspace
        .lock()
        .clone()
        .ok_or_else(|| "请先打开工作区".to_string())?;
    tokio::task::spawn_blocking(move || crate::git::reject_change(&cwd, &path))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn git_reject_all(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    let cwd = state
        .workspace
        .lock()
        .clone()
        .ok_or_else(|| "请先打开工作区".to_string())?;
    tokio::task::spawn_blocking(move || crate::git::reject_all(&cwd))
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_start(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    let cwd = state.workspace.lock().clone();
    crate::terminal::start_terminal(app, cwd)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_write(app: AppHandle, data: String) -> Result<(), String> {
    crate::terminal::write_terminal(&app, &data)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_resize(app: AppHandle, rows: u16, cols: u16) -> Result<(), String> {
    crate::terminal::resize_terminal(&app, rows, cols)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn terminal_stop(app: AppHandle) -> Result<(), String> {
    crate::terminal::stop_terminal(&app)
        .await
        .map_err(|e| e.to_string())
}
