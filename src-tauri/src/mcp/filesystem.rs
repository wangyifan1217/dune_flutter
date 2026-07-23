use std::fs;
use std::path::{Component, Path, PathBuf};

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};

pub struct FilesystemServer {
    root: PathBuf,
}

impl FilesystemServer {
    pub fn new(root: impl Into<String>) -> Self {
        let root = PathBuf::from(root.into());
        Self {
            root: root.canonicalize().unwrap_or(root),
        }
    }

    fn join_under_root(&self, rel: &str) -> Result<PathBuf> {
        let raw = Path::new(rel);
        if raw.is_absolute() {
            let canon = raw.canonicalize().unwrap_or_else(|_| raw.to_path_buf());
            if !canon.starts_with(&self.root) {
                bail!("path escapes allowed directory: {rel}");
            }
            return Ok(canon);
        }
        let mut out = self.root.clone();
        for comp in raw.components() {
            match comp {
                Component::ParentDir => {
                    if !out.pop() || !out.starts_with(&self.root) {
                        bail!("path escapes allowed directory: {rel}");
                    }
                }
                Component::Normal(s) => out.push(s),
                Component::CurDir => {}
                _ => {}
            }
        }
        if !out.starts_with(&self.root) {
            bail!("path escapes allowed directory: {rel}");
        }
        Ok(out)
    }

    fn resolve_existing(&self, rel: &str) -> Result<PathBuf> {
        let full = self.join_under_root(rel)?;
        let canon = full
            .canonicalize()
            .with_context(|| format!("path not found: {rel}"))?;
        if !canon.starts_with(&self.root) {
            bail!("path escapes allowed directory: {rel}");
        }
        Ok(canon)
    }
}

impl McpServer for FilesystemServer {
    fn name(&self) -> &str {
        "nova-filesystem"
    }

    fn tools(&self) -> Value {
        json!([
            {
                "name": "read_file",
                "description": "Read a UTF-8 text file under the allowed directory",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Relative or absolute path within allowed root" }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "write_file",
                "description": "Write UTF-8 text to a file under the allowed directory",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string" },
                        "content": { "type": "string" }
                    },
                    "required": ["path", "content"]
                }
            },
            {
                "name": "list_directory",
                "description": "List files and folders in a directory",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Directory path (default .)" }
                    }
                }
            },
            {
                "name": "create_directory",
                "description": "Create a directory (and parents)",
                "inputSchema": {
                    "type": "object",
                    "properties": { "path": { "type": "string" } },
                    "required": ["path"]
                }
            }
        ])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        match name {
            "read_file" => {
                let path = require_str(arguments, "path")?;
                let full = self.resolve_existing(path)?;
                let content = fs::read_to_string(&full)
                    .with_context(|| format!("read failed: {}", full.display()))?;
                Ok(text_result(content))
            }
            "write_file" => {
                let path = require_str(arguments, "path")?;
                let content = require_str(arguments, "content")?;
                let full = self.join_under_root(path)?;
                if let Some(parent) = full.parent() {
                    fs::create_dir_all(parent)?;
                }
                fs::write(&full, content)?;
                Ok(text_result(format!("wrote {}", full.display())))
            }
            "list_directory" => {
                let path = arguments
                    .get("path")
                    .and_then(Value::as_str)
                    .unwrap_or(".");
                let full = self.resolve_existing(path)?;
                let mut lines = Vec::new();
                for entry in fs::read_dir(&full)? {
                    let entry = entry?;
                    let meta = entry.metadata()?;
                    let kind = if meta.is_dir() { "dir" } else { "file" };
                    lines.push(format!(
                        "{kind}\t{}",
                        entry.file_name().to_string_lossy()
                    ));
                }
                lines.sort();
                Ok(text_result(lines.join("\n")))
            }
            "create_directory" => {
                let path = require_str(arguments, "path")?;
                let full = self.join_under_root(path)?;
                fs::create_dir_all(&full)?;
                Ok(text_result(format!("created {}", full.display())))
            }
            other => bail!("unknown tool: {other}"),
        }
    }
}
