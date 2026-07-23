use anyhow::{Context, Result};
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};

pub struct FetchServer;

impl McpServer for FetchServer {
    fn name(&self) -> &str {
        "nova-fetch"
    }

    fn tools(&self) -> Value {
        json!([{
            "name": "fetch_url",
            "description": "Fetch a URL and return response body as text (HTML/plain). Max ~500KB.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "url": { "type": "string", "description": "http(s) URL" },
                    "maxChars": { "type": "integer", "description": "Truncate after N characters (default 80000)" }
                },
                "required": ["url"]
            }
        }])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        if name != "fetch_url" {
            anyhow::bail!("unknown tool: {name}");
        }
        let url = require_str(arguments, "url")?;
        if !(url.starts_with("http://") || url.starts_with("https://")) {
            anyhow::bail!("only http(s) URLs are allowed");
        }
        let max_chars = arguments
            .get("maxChars")
            .and_then(Value::as_u64)
            .unwrap_or(80_000) as usize;

        let body = ureq::get(url)
            .timeout(std::time::Duration::from_secs(20))
            .call()
            .with_context(|| format!("request failed: {url}"))?
            .into_string()
            .context("read body")?;

        let clipped = if body.chars().count() > max_chars {
            let t: String = body.chars().take(max_chars).collect();
            format!("{t}\n\n…(truncated)")
        } else {
            body
        };
        Ok(text_result(clipped))
    }
}
