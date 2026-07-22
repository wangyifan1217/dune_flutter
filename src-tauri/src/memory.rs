use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoryEntry {
    pub id: String,
    pub content: String,
    pub created_at: i64,
    #[serde(default)]
    pub source: String,
}

fn memory_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("无法获取应用数据目录：{e}"))?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("memory.json"))
}

pub fn load_memories(app: &AppHandle) -> Result<Vec<MemoryEntry>, String> {
    let path = memory_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }
    let raw = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str(&raw).map_err(|e| e.to_string())
}

pub fn save_memories(app: &AppHandle, items: &[MemoryEntry]) -> Result<(), String> {
    let path = memory_path(app)?;
    let raw = serde_json::to_string_pretty(items).map_err(|e| e.to_string())?;
    fs::write(path, raw).map_err(|e| e.to_string())
}

pub fn add_memory(app: &AppHandle, content: String, source: String) -> Result<MemoryEntry, String> {
    let text = content.trim().to_string();
    if text.is_empty() {
        return Err("记忆内容不能为空".into());
    }
    let mut items = load_memories(app)?;
    // 去重：相同内容不重复写
    if items.iter().any(|m| m.content == text) {
        return Err("已有相同记忆".into());
    }
    let entry = MemoryEntry {
        id: Uuid::new_v4().to_string(),
        content: text,
        created_at: chrono_now(),
        source: if source.trim().is_empty() {
            "user".into()
        } else {
            source
        },
    };
    items.insert(0, entry.clone());
    // 上限 200 条，避免 prompt 过长
    if items.len() > 200 {
        items.truncate(200);
    }
    save_memories(app, &items)?;
    Ok(entry)
}

pub fn delete_memory(app: &AppHandle, id: &str) -> Result<(), String> {
    let mut items = load_memories(app)?;
    let before = items.len();
    items.retain(|m| m.id != id);
    if items.len() == before {
        return Err("记忆不存在".into());
    }
    save_memories(app, &items)
}

pub fn clear_memories(app: &AppHandle) -> Result<(), String> {
    save_memories(app, &[])
}

/// 拼进 prompt 的记忆块（最多取最近 40 条）
pub fn format_for_prompt(app: &AppHandle) -> String {
    let Ok(items) = load_memories(app) else {
        return String::new();
    };
    if items.is_empty() {
        return String::new();
    }
    let mut lines = vec!["【永久记忆 — 请在后续回复中遵守并参考】".to_string()];
    for (i, m) in items.iter().take(40).enumerate() {
        lines.push(format!("{}. {}", i + 1, m.content));
    }
    lines.join("\n")
}

fn chrono_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
