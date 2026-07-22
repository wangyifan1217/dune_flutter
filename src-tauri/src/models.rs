use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServerConfig {
    pub name: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: Vec<McpEnvVar>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpEnvVar {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelEntry {
    pub id: String,
    #[serde(default)]
    pub label: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptAttachment {
    pub name: String,
    pub mime_type: String,
    pub size: u64,
    pub encoding: String,
    /// Base64 image payload or UTF-8 text-file contents.
    pub data: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DroppedFile {
    pub name: String,
    pub mime_type: String,
    pub size: u64,
    pub encoding: String,
    pub data: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub grok_command: String,
    pub grok_args: Vec<String>,
    pub auto_approve_permissions: bool,
    #[serde(default)]
    pub api_base_url: String,
    #[serde(default)]
    pub api_key: String,
    #[serde(default)]
    pub model_id: String,
    /// 用户配置的可选模型（共用一把 new-api key）
    #[serde(default)]
    pub models: Vec<ModelEntry>,
    /// MCP 服务器列表，会在 session/new 时传给 Agent
    #[serde(default)]
    pub mcp_servers: Vec<McpServerConfig>,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            grok_command: default_grok_command(),
            grok_args: vec!["agent".into(), "stdio".into()],
            auto_approve_permissions: true,
            api_base_url: String::new(),
            api_key: String::new(),
            model_id: String::new(),
            models: Vec::new(),
            mcp_servers: Vec::new(),
        }
    }
}

fn default_grok_command() -> String {
    if let Ok(home) = std::env::var("USERPROFILE").or_else(|_| std::env::var("HOME")) {
        let candidate = std::path::PathBuf::from(home)
            .join(".grok")
            .join("bin")
            .join(if cfg!(target_os = "windows") {
                "grok.exe"
            } else {
                "grok"
            });
        if candidate.exists() {
            return candidate.to_string_lossy().into_owned();
        }
    }
    if cfg!(target_os = "windows") {
        "grok.exe".into()
    } else {
        "grok".into()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentStatus {
    pub connected: bool,
    pub session_id: Option<String>,
    pub workspace: Option<String>,
    pub message: String,
}

impl Default for AgentStatus {
    fn default() -> Self {
        Self {
            connected: false,
            session_id: None,
            workspace: None,
            message: "未连接".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionUpdateEvent {
    /// 前端 ThreadSession ID，用于在多个 ACP session 间路由更新。
    pub thread_id: String,
    pub session_id: String,
    pub update: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    pub id: String,
    pub role: String,
    pub content: String,
    pub status: String,
}

/// 发给 Agent 的近期对话摘要，用于重启后接续上下文。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptHistoryMessage {
    pub role: String,
    pub content: String,
}
