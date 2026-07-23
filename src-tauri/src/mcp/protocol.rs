use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};

pub trait McpServer {
    fn name(&self) -> &str;
    fn tools(&self) -> Value;
    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value>;

    fn serve_stdio(mut self) -> Result<()>
    where
        Self: Sized,
    {
        let stdin = std::io::stdin();
        let mut stdout = std::io::stdout();
        let mut reader = BufReader::new(stdin.lock());
        let mut line = String::new();

        loop {
            line.clear();
            let n = reader.read_line(&mut line)?;
            if n == 0 {
                break;
            }
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let msg: Value = match serde_json::from_str(trimmed) {
                Ok(v) => v,
                Err(_) => continue,
            };

            // notification：无 id
            let has_id = msg.get("id").is_some() && !msg.get("id").unwrap().is_null();
            let method = msg.get("method").and_then(Value::as_str).unwrap_or("");

            if !has_id {
                // notifications/initialized 等忽略
                let _ = method;
                continue;
            }

            let id = msg.get("id").cloned().unwrap_or(Value::Null);
            let response = match method {
                "initialize" => json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": { "tools": {} },
                        "serverInfo": {
                            "name": self.name(),
                            "version": env!("CARGO_PKG_VERSION")
                        }
                    }
                }),
                "ping" => json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": {}
                }),
                "tools/list" => json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": { "tools": self.tools() }
                }),
                "tools/call" => {
                    let params = msg.get("params").cloned().unwrap_or(Value::Null);
                    let tool = params
                        .get("name")
                        .and_then(Value::as_str)
                        .unwrap_or("");
                    let args = params
                        .get("arguments")
                        .cloned()
                        .unwrap_or_else(|| json!({}));
                    match self.call_tool(tool, &args) {
                        Ok(result) => json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": result
                        }),
                        Err(err) => json!({
                            "jsonrpc": "2.0",
                            "id": id,
                            "result": {
                                "content": [{ "type": "text", "text": format!("Error: {err:#}") }],
                                "isError": true
                            }
                        }),
                    }
                }
                other => json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": {
                        "code": -32601,
                        "message": format!("Method not found: {other}")
                    }
                }),
            };

            writeln!(stdout, "{}", serde_json::to_string(&response)?)
                .context("write mcp response")?;
            stdout.flush()?;
        }
        Ok(())
    }
}

pub fn text_result(text: impl Into<String>) -> Value {
    json!({
        "content": [{ "type": "text", "text": text.into() }]
    })
}

pub fn require_str<'a>(args: &'a Value, key: &str) -> Result<&'a str> {
    args.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("missing string argument: {key}"))
}
