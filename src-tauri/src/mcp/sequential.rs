use anyhow::Result;
use serde_json::{json, Value};

use super::protocol::{text_result, McpServer};

#[derive(Default)]
pub struct SequentialThinkingServer {
    thought_history: Vec<String>,
}

impl McpServer for SequentialThinkingServer {
    fn name(&self) -> &str {
        "nova-sequential-thinking"
    }

    fn tools(&self) -> Value {
        json!([{
            "name": "sequentialthinking",
            "description": "A detailed tool for dynamic and reflective problem-solving through thoughts. Use for complex multi-step reasoning.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "thought": { "type": "string", "description": "Your current thinking step" },
                    "nextThoughtNeeded": { "type": "boolean", "description": "Whether another thought step is needed" },
                    "thoughtNumber": { "type": "integer", "description": "Current thought number (e.g. 1, 2, 3)", "minimum": 1 },
                    "totalThoughts": { "type": "integer", "description": "Estimated total thoughts needed (e.g. 5, 10)", "minimum": 1 },
                    "isRevision": { "type": "boolean", "description": "Whether this revises previous thinking" },
                    "revisesThought": { "type": "integer", "description": "Which thought is being reconsidered" },
                    "branchFromThought": { "type": "integer", "description": "Branching point thought number" },
                    "branchId": { "type": "string", "description": "Branch identifier" },
                    "needsMoreThoughts": { "type": "boolean", "description": "If more thoughts are needed" }
                },
                "required": ["thought", "nextThoughtNeeded", "thoughtNumber", "totalThoughts"]
            }
        }])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        if name != "sequentialthinking" {
            anyhow::bail!("unknown tool: {name}");
        }
        let thought = arguments
            .get("thought")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let thought_number = arguments
            .get("thoughtNumber")
            .and_then(Value::as_u64)
            .unwrap_or(1);
        let total = arguments
            .get("totalThoughts")
            .and_then(Value::as_u64)
            .unwrap_or(thought_number);
        let next_needed = arguments
            .get("nextThoughtNeeded")
            .and_then(Value::as_bool)
            .unwrap_or(false);

        self.thought_history.push(format!("#{thought_number}: {thought}"));

        let summary = json!({
            "thoughtNumber": thought_number,
            "totalThoughts": total,
            "nextThoughtNeeded": next_needed,
            "thoughtCount": self.thought_history.len(),
            "branches": [],
            "thoughtHistoryLength": self.thought_history.len()
        });

        Ok(text_result(serde_json::to_string_pretty(&summary)?))
    }
}
