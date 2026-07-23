use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};

pub struct MemoryServer {
    path: PathBuf,
    data: Value,
}

impl MemoryServer {
    pub fn open_default() -> Result<Self> {
        let dir = dirs_next_path()?;
        fs::create_dir_all(&dir)?;
        let path = dir.join("mcp-memory.json");
        let data = if path.exists() {
            let raw = fs::read_to_string(&path)?;
            serde_json::from_str(&raw).unwrap_or_else(|_| json!({ "notes": [] }))
        } else {
            json!({ "notes": [] })
        };
        Ok(Self { path, data })
    }

    fn save(&self) -> Result<()> {
        let raw = serde_json::to_string_pretty(&self.data)?;
        fs::write(&self.path, raw)?;
        Ok(())
    }
}

fn dirs_next_path() -> Result<PathBuf> {
    let base = if let Ok(appdata) = std::env::var("APPDATA") {
        PathBuf::from(appdata).join("com.nova.desktop")
    } else if let Ok(home) = std::env::var("HOME") {
        PathBuf::from(home).join(".nova-desktop")
    } else {
        std::env::temp_dir().join("nova-desktop")
    };
    Ok(base)
}

impl McpServer for MemoryServer {
    fn name(&self) -> &str {
        "nova-memory"
    }

    fn tools(&self) -> Value {
        json!([
            {
                "name": "add_note",
                "description": "Store a short memory note",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "text": { "type": "string" }
                    },
                    "required": ["text"]
                }
            },
            {
                "name": "search_notes",
                "description": "Search stored notes by keyword (case-insensitive)",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "query": { "type": "string" }
                    },
                    "required": ["query"]
                }
            },
            {
                "name": "list_notes",
                "description": "List all stored notes",
                "inputSchema": { "type": "object", "properties": {} }
            }
        ])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        match name {
            "add_note" => {
                let text = require_str(arguments, "text")?.to_string();
                let notes = self
                    .data
                    .get_mut("notes")
                    .and_then(Value::as_array_mut)
                    .context("invalid memory store")?;
                notes.push(json!({
                    "id": uuid::Uuid::new_v4().to_string(),
                    "text": text,
                    "at": chrono_timestamp()
                }));
                self.save()?;
                Ok(text_result("note saved"))
            }
            "search_notes" => {
                let query = require_str(arguments, "query")?.to_ascii_lowercase();
                let notes = self
                    .data
                    .get("notes")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                let hits: Vec<_> = notes
                    .into_iter()
                    .filter(|n| {
                        n.get("text")
                            .and_then(Value::as_str)
                            .map(|t| t.to_ascii_lowercase().contains(&query))
                            .unwrap_or(false)
                    })
                    .collect();
                Ok(text_result(serde_json::to_string_pretty(&hits)?))
            }
            "list_notes" => {
                let notes = self.data.get("notes").cloned().unwrap_or_else(|| json!([]));
                Ok(text_result(serde_json::to_string_pretty(&notes)?))
            }
            other => anyhow::bail!("unknown tool: {other}"),
        }
    }
}

fn chrono_timestamp() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    secs.to_string()
}
