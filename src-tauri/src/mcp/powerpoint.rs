use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};
use crate::office::{create_blank_pptx, create_pptx, extract_pptx_text};

pub struct PowerpointServer;

impl McpServer for PowerpointServer {
    fn name(&self) -> &str {
        "nova-powerpoint"
    }

    fn tools(&self) -> Value {
        json!([
            {
                "name": "create_blank",
                "description": "Create a blank .pptx with one empty slide",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Output .pptx path" }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "create_presentation",
                "description": "Create a .pptx from slides. slides is a JSON array of {title, body} objects.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string" },
                        "slides": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "title": { "type": "string" },
                                    "body": { "type": "string" }
                                }
                            }
                        }
                    },
                    "required": ["path", "slides"]
                }
            },
            {
                "name": "read_text",
                "description": "Extract text content from an existing .pptx",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string" }
                    },
                    "required": ["path"]
                }
            }
        ])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        match name {
            "create_blank" => {
                let path = require_str(arguments, "path")?;
                if !path.to_ascii_lowercase().ends_with(".pptx") {
                    bail!("path should end with .pptx");
                }
                create_blank_pptx(path)?;
                Ok(text_result(format!("created {path}")))
            }
            "create_presentation" => {
                let path = require_str(arguments, "path")?;
                if !path.to_ascii_lowercase().ends_with(".pptx") {
                    bail!("path should end with .pptx");
                }
                let slides_val = arguments
                    .get("slides")
                    .and_then(Value::as_array)
                    .context("slides must be an array")?;
                let slides: Vec<(String, String)> = slides_val
                    .iter()
                    .map(|s| {
                        (
                            s.get("title")
                                .and_then(Value::as_str)
                                .unwrap_or("")
                                .to_string(),
                            s.get("body")
                                .and_then(Value::as_str)
                                .unwrap_or("")
                                .to_string(),
                        )
                    })
                    .collect();
                create_pptx(path, &slides)?;
                Ok(text_result(format!(
                    "created {path} with {} slide(s)",
                    slides.len().max(1)
                )))
            }
            "read_text" => {
                let path = require_str(arguments, "path")?;
                let text = extract_pptx_text(path)?;
                Ok(text_result(text))
            }
            other => bail!("unknown tool: {other}"),
        }
    }
}
