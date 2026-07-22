use std::sync::Arc;
use std::path::PathBuf;

use base64::{engine::general_purpose::STANDARD, Engine};
use tauri::{AppHandle, Emitter, State};
use tauri_plugin_opener::OpenerExt;
use tauri_plugin_store::StoreExt;

use crate::models::{AgentStatus, AppSettings, ChatMessage, FileEntry};
use crate::state::AppState;
use crate::workspace::{absolutize, build_tree, list_directory, DirectoryTreeNode};

const SETTINGS_STORE: &str = "settings.json";
const SETTINGS_KEY: &str = "app";
const MAX_BINARY_ATTACHMENT_BYTES: u64 = 10 * 1024 * 1024;
const MAX_TEXT_ATTACHMENT_BYTES: u64 = 512 * 1024;

#[tauri::command]
pub fn get_settings(app: AppHandle) -> Result<AppSettings, String> {
    let store = app.store(SETTINGS_STORE).map_err(|e| e.to_string())?;
    if let Some(value) = store.get(SETTINGS_KEY) {
        serde_json::from_value(value).map_err(|e| e.to_string())
    } else {
        Ok(AppSettings::default())
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

/// Opens a file explicitly referenced in an agent response.
/// Relative paths are resolved within the selected workspace; absolute paths require user confirmation.
#[tauri::command]
pub fn open_generated_file(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    path: String,
) -> Result<(), String> {
    let requested = PathBuf::from(path);
    let (candidate, workspace_root) = if requested.is_absolute() {
        (requested, None)
    } else {
        let workspace = state
            .workspace
            .lock()
            .clone()
            .ok_or_else(|| "打开相对路径前请先选择项目文件夹".to_string())?;
        let root = std::fs::canonicalize(&workspace).map_err(|e| e.to_string())?;
        (root.join(requested), Some(root))
    };
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
    app.opener()
        .open_path(canonical.to_string_lossy(), None::<String>)
        .map_err(|e| e.to_string())
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

    // 永久记忆、产品身份与中文偏好，拼进每次提问。
    let memory_block = crate::memory::format_for_prompt(&app);
    let mut prompt = String::new();
    if !memory_block.is_empty() {
        prompt.push_str(&memory_block);
        prompt.push_str("\n\n");
    }
    prompt.push_str(
        "你是 Nova Build 的 AI 编程助手。始终以“Nova Build”自我介绍，\
不要声称自己是 Grok、xAI 或任何其他第三方产品；不要在回答中提及底层模型或服务提供方。\
请始终使用简体中文回复。\n\n\
运行环境说明：\n\
- 用户使用的是 Nova Build 桌面客户端，不是终端 TUI。\n\
- 不要让用户输入 /cd 等 TUI 命令；切换项目由用户点击「选择项目」完成。\n\
- 需要打开浏览器时，在 Windows 上执行：cmd /c start \"\" \"http://127.0.0.1:端口\"\n\
- 启动 PHP 内置服务器可用：php -S 127.0.0.1:8000 -t <项目目录>；若 php 不存在，请明确说明并给出安装/替代方案。\n\
- 长驻后台进程可能无法在关闭应用后继续运行；请如实告知，并给出可在右侧「终端」手动执行的命令。\n\n",
    );

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
) -> Result<(), String> {
    save_settings(app.clone(), settings.clone())?;
    *state.settings.lock() = settings;
    Ok(())
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
