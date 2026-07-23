use std::fs;
use std::path::Path;

use anyhow::{bail, Context, Result};
use docx_rs::*;
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};

pub struct WordServer;

impl McpServer for WordServer {
    fn name(&self) -> &str {
        "nova-word"
    }

    fn tools(&self) -> Value {
        json!([
            {
                "name": "create_document",
                "description": "Create a new .docx with optional title and body paragraphs. paragraphs is a JSON string array.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Output .docx path" },
                        "title": { "type": "string" },
                        "paragraphs": {
                            "type": "array",
                            "items": { "type": "string" },
                            "description": "Body paragraphs"
                        }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "read_text",
                "description": "Extract plain text from a .docx file",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string" }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "append_paragraphs",
                "description": "Append paragraphs to an existing .docx (rewrites file). paragraphs is a JSON string array.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string" },
                        "paragraphs": {
                            "type": "array",
                            "items": { "type": "string" }
                        }
                    },
                    "required": ["path", "paragraphs"]
                }
            }
        ])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        match name {
            "create_document" => {
                let path = require_str(arguments, "path")?;
                if !path.to_ascii_lowercase().ends_with(".docx") {
                    bail!("path should end with .docx");
                }
                ensure_parent(path)?;
                let title = arguments.get("title").and_then(Value::as_str);
                let paragraphs = arguments
                    .get("paragraphs")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();

                let mut doc = Docx::new();
                if let Some(t) = title {
                    if !t.trim().is_empty() {
                        doc = doc.add_paragraph(
                            Paragraph::new().add_run(Run::new().add_text(t).bold().size(32)),
                        );
                    }
                }
                for p in paragraphs {
                    let text = p.as_str().unwrap_or("").to_string();
                    if text.is_empty() {
                        doc = doc.add_paragraph(Paragraph::new());
                    } else {
                        doc = doc.add_paragraph(Paragraph::new().add_run(Run::new().add_text(text)));
                    }
                }

                let file = fs::File::create(path)
                    .with_context(|| format!("无法创建：{path}"))?;
                doc.build().pack(file).context("写入 docx 失败")?;
                Ok(text_result(format!("created {path}")))
            }
            "read_text" => {
                let path = require_str(arguments, "path")?;
                let bytes = fs::read(path).with_context(|| format!("无法读取：{path}"))?;
                let text = extract_docx_text(&bytes)?;
                Ok(text_result(text))
            }
            "append_paragraphs" => {
                let path = require_str(arguments, "path")?;
                let paragraphs = arguments
                    .get("paragraphs")
                    .and_then(Value::as_array)
                    .context("paragraphs must be an array")?;
                let bytes = fs::read(path).with_context(|| format!("无法读取：{path}"))?;
                let existing = extract_docx_text(&bytes)?;

                let mut doc = Docx::new();
                for line in existing.lines() {
                    doc = doc.add_paragraph(Paragraph::new().add_run(Run::new().add_text(line)));
                }
                for p in paragraphs {
                    let text = p.as_str().unwrap_or("");
                    doc = doc.add_paragraph(Paragraph::new().add_run(Run::new().add_text(text)));
                }
                let file = fs::File::create(path)?;
                doc.build().pack(file)?;
                Ok(text_result(format!("updated {path}")))
            }
            other => bail!("unknown tool: {other}"),
        }
    }
}

fn ensure_parent(path: &str) -> Result<()> {
    if let Some(parent) = Path::new(path).parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}

/// 从 docx zip 中抽取 document.xml 的纯文本（简易）。
fn extract_docx_text(bytes: &[u8]) -> Result<String> {
    use std::io::Cursor;
    let reader = Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(reader).context("invalid docx zip")?;
    let mut file = archive
        .by_name("word/document.xml")
        .context("docx missing word/document.xml")?;
    let mut xml = String::new();
    std::io::Read::read_to_string(&mut file, &mut xml)?;
    Ok(strip_xml_to_text(&xml))
}

fn strip_xml_to_text(xml: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    let mut last_was_space = true;
    for ch in xml.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => {
                in_tag = false;
                // paragraph breaks roughly
                if !last_was_space {
                    out.push('\n');
                    last_was_space = true;
                }
            }
            _ if in_tag => {}
            c if c.is_whitespace() => {
                if !last_was_space {
                    out.push(' ');
                    last_was_space = true;
                }
            }
            c => {
                out.push(c);
                last_was_space = false;
            }
        }
    }
    out.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}
