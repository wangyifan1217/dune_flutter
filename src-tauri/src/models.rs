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
            mcp_servers: recommended_mcp_servers(),
        }
    }
}

/// 内置推荐 MCP：Office / 联网 / 文件 / 记忆 / 分步推理（nova-builtin，无需 Node）。
pub fn recommended_mcp_servers() -> Vec<McpServerConfig> {
    fn builtin(name: &str, args: &[&str]) -> McpServerConfig {
        McpServerConfig {
            name: name.into(),
            command: "nova-builtin".into(),
            args: args.iter().map(|s| (*s).to_string()).collect(),
            env: Vec::new(),
        }
    }
    vec![
        builtin("sequential-thinking", &["sequential-thinking"]),
        builtin("filesystem", &["filesystem", "."]),
        builtin("memory", &["memory"]),
        builtin("fetch", &["fetch"]),
        builtin("excel", &["excel"]),
        builtin("word", &["word"]),
        builtin("powerpoint", &["powerpoint"]),
    ]
}

fn bundled_grok_command() -> Option<String> {
    // 安装包内置的 Grok Agent：新机器无需另行安装。
    // NSIS 资源会解压至 exe 同级目录；macOS .app 使用 Contents/Resources。
    if let Ok(exe) = std::env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            let binary_name = if cfg!(target_os = "windows") {
                "grok.exe"
            } else {
                "grok"
            };
            let bundled_candidates = [
                exe_dir.join("resources").join(binary_name),
                exe_dir.join("Resources").join(binary_name),
                exe_dir.join(binary_name),
                exe_dir.join("..").join("resources").join(binary_name),
                exe_dir.join("..").join("Resources").join(binary_name),
            ];
            for candidate in bundled_candidates {
                if candidate.is_file() {
                    return Some(candidate.to_string_lossy().into_owned());
                }
            }
        }
    }
    None
}

fn home_grok_command() -> Option<String> {
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
            return Some(candidate.to_string_lossy().into_owned());
        }
    }
    None
}

fn path_grok_command() -> Option<String> {
    let binary_name = if cfg!(target_os = "windows") {
        "grok.exe"
    } else {
        "grok"
    };
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|dir| dir.join(binary_name))
            .find(|candidate| candidate.is_file())
            .map(|candidate| candidate.to_string_lossy().into_owned())
    })
}

pub fn resolve_grok_command(configured: &str) -> String {
    let configured = configured.trim();
    if !configured.is_empty() && std::path::Path::new(configured).is_file() {
        return configured.to_string();
    }
    bundled_grok_command()
        .or_else(home_grok_command)
        .or_else(path_grok_command)
        .unwrap_or_else(|| {
            if configured.is_empty() {
                if cfg!(target_os = "windows") {
                    "grok.exe".into()
                } else {
                    "grok".into()
                }
            } else {
                configured.to_string()
            }
        })
}

fn default_grok_command() -> String {
    let fallback = if cfg!(target_os = "windows") {
        "grok.exe"
    } else {
        "grok"
    };
    resolve_grok_command(fallback)
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GrokInstallationStatus {
    pub platform: String,
    pub installed: bool,
    pub command: Option<String>,
}

pub fn grok_installation_status(configured: &str) -> GrokInstallationStatus {
    let command = resolve_grok_command(configured);
    let installed = std::path::Path::new(&command).is_file();
    GrokInstallationStatus {
        platform: if cfg!(target_os = "macos") {
            "macos".into()
        } else if cfg!(target_os = "windows") {
            "windows".into()
        } else {
            std::env::consts::OS.into()
        },
        installed,
        command: installed.then_some(command),
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
