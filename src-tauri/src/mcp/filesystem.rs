use std::fs;
use std::path::{Component, Path, PathBuf};

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};
use crate::diff_text::unified_line_diff;
use crate::workspace::strip_verbatim_prefix;

pub struct FilesystemServer {
    root: PathBuf,
}

impl FilesystemServer {
    pub fn new(root: impl Into<String>) -> Self {
        let root = PathBuf::from(root.into());
        let root = root
            .canonicalize()
            .map(strip_verbatim_prefix)
            .unwrap_or(root);
        Self { root }
    }

    fn join_under_root(&self, rel: &str) -> Result<PathBuf> {
        let raw = Path::new(rel);
        if raw.is_absolute() {
            let canon = raw
                .canonicalize()
                .map(strip_verbatim_prefix)
                .unwrap_or_else(|_| raw.to_path_buf());
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
        let canon = strip_verbatim_prefix(
            full.canonicalize()
                .with_context(|| format!("path not found: {rel}"))?,
        );
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
                let bytes = fs::read(&full)
                    .with_context(|| format!("read failed: {}", full.display()))?;
                if bytes.iter().take(8192).any(|&b| b == 0)
                    || full
                        .extension()
                        .and_then(|e| e.to_str())
                        .is_some_and(|e| {
                            matches!(
                                e.to_ascii_lowercase().as_str(),
                                "png" | "jpg" | "jpeg" | "gif" | "webp" | "pdf" | "pptx" | "xlsx"
                                    | "docx" | "zip" | "exe"
                            )
                        })
                {
                    bail!(
                        "binary/image file cannot be read as text: {}. Use chat image attachments instead.",
                        full.display()
                    );
                }
                let content = String::from_utf8_lossy(&bytes).into_owned();
                Ok(text_result(content))
            }
            "write_file" => {
                let path = require_str(arguments, "path")?;
                let content = require_str(arguments, "content")?;
                let full = self.join_under_root(path)?;
                if let Some(parent) = full.parent() {
                    fs::create_dir_all(parent)?;
                }
                let created = !full.exists();
                let old = if created {
                    String::new()
                } else {
                    let raw = fs::read(&full).unwrap_or_default();
                    let slice = if raw.starts_with(&[0xEF, 0xBB, 0xBF]) {
                        &raw[3..]
                    } else {
                        raw.as_slice()
                    };
                    String::from_utf8_lossy(slice).into_owned()
                };
                // 与 workspace::write_text_file 一致：UTF-8 BOM
                let mut bytes = vec![0xEF, 0xBB, 0xBF];
                bytes.extend_from_slice(content.as_bytes());
                fs::write(&full, bytes)?;
                let display = full
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or(path);
                let diff = unified_line_diff(&old, content, display);
                let kind = if created { "created" } else { "updated" };
                Ok(text_result(format!(
                    "wrote {} ({kind})\n\n```diff\n{diff}\n```",
                    full.display()
                )))
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
