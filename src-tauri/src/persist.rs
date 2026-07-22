use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use tauri::{AppHandle, Manager};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredSessions {
    pub sessions: Value,
    pub active_id: Option<String>,
}

fn sessions_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("无法获取应用数据目录：{e}"))?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("sessions.json"))
}

pub fn load_sessions(app: &AppHandle) -> Result<StoredSessions, String> {
    let path = sessions_path(app)?;
    if !path.exists() {
        return Ok(StoredSessions {
            sessions: Value::Array(vec![]),
            active_id: None,
        });
    }
    let raw = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    if raw.trim().is_empty() {
        return Ok(StoredSessions {
            sessions: Value::Array(vec![]),
            active_id: None,
        });
    }
    serde_json::from_str(&raw).map_err(|e| e.to_string())
}

pub fn save_sessions(app: &AppHandle, data: &StoredSessions) -> Result<(), String> {
    let path = sessions_path(app)?;
    let raw = serde_json::to_string_pretty(data).map_err(|e| e.to_string())?;
    fs::write(path, raw).map_err(|e| e.to_string())
}
