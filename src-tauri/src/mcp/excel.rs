use std::path::Path;

use anyhow::{bail, Context, Result};
use calamine::{open_workbook_auto, Data, Reader};
use rust_xlsxwriter::Workbook;
use serde_json::{json, Value};

use super::protocol::{require_str, text_result, McpServer};

pub struct ExcelServer;

impl McpServer for ExcelServer {
    fn name(&self) -> &str {
        "nova-excel"
    }

    fn tools(&self) -> Value {
        json!([
            {
                "name": "list_sheets",
                "description": "List worksheet names in an .xlsx/.xls file",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Path to spreadsheet file" }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "read_sheet",
                "description": "Read a worksheet as TSV text (tab-separated). Caps at 200 rows / 40 columns.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string" },
                        "sheet": { "type": "string", "description": "Sheet name (default first sheet)" }
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "create_workbook",
                "description": "Create a new .xlsx workbook with one sheet of rows. rows is a JSON array of arrays (string/number cells).",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Output .xlsx path" },
                        "sheet": { "type": "string", "description": "Sheet name (default Sheet1)" },
                        "rows": {
                            "type": "array",
                            "description": "2D array of cell values",
                            "items": { "type": "array", "items": {} }
                        }
                    },
                    "required": ["path", "rows"]
                }
            }
        ])
    }

    fn call_tool(&mut self, name: &str, arguments: &Value) -> Result<Value> {
        match name {
            "list_sheets" => {
                let path = require_str(arguments, "path")?;
                ensure_parent(path)?;
                let wb = open_workbook_auto(path)
                    .with_context(|| format!("无法打开表格：{path}"))?;
                let names = wb.sheet_names().to_vec();
                Ok(text_result(names.join("\n")))
            }
            "read_sheet" => {
                let path = require_str(arguments, "path")?;
                let mut wb = open_workbook_auto(path)
                    .with_context(|| format!("无法打开表格：{path}"))?;
                let sheet = arguments
                    .get("sheet")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string())
                    .or_else(|| wb.sheet_names().first().cloned())
                    .context("workbook has no sheets")?;
                let range = wb
                    .worksheet_range(&sheet)
                    .with_context(|| format!("无法读取工作表：{sheet}"))?;
                let mut lines = Vec::new();
                for (r, row) in range.rows().enumerate() {
                    if r >= 200 {
                        lines.push("…(rows truncated)".into());
                        break;
                    }
                    let cells: Vec<String> = row
                        .iter()
                        .take(40)
                        .map(|c| match c {
                            Data::Empty => String::new(),
                            Data::String(s) => s.replace('\t', " ").replace('\n', " "),
                            Data::Float(f) => f.to_string(),
                            Data::Int(i) => i.to_string(),
                            Data::Bool(b) => b.to_string(),
                            Data::DateTime(dt) => format!("{dt:?}"),
                            Data::DateTimeIso(s) | Data::DurationIso(s) => s.clone(),
                            Data::Error(e) => format!("#ERR:{e:?}"),
                        })
                        .collect();
                    lines.push(cells.join("\t"));
                }
                Ok(text_result(format!("sheet: {sheet}\n{}", lines.join("\n"))))
            }
            "create_workbook" => {
                let path = require_str(arguments, "path")?;
                if !path.to_ascii_lowercase().ends_with(".xlsx") {
                    bail!("path should end with .xlsx");
                }
                ensure_parent(path)?;
                let sheet_name = arguments
                    .get("sheet")
                    .and_then(Value::as_str)
                    .unwrap_or("Sheet1");
                let rows = arguments
                    .get("rows")
                    .and_then(Value::as_array)
                    .context("rows must be a JSON array")?;

                let mut workbook = Workbook::new();
                let worksheet = workbook.add_worksheet();
                worksheet.set_name(sheet_name)?;

                for (r, row) in rows.iter().enumerate() {
                    if r >= 5000 {
                        break;
                    }
                    let Some(cols) = row.as_array() else {
                        continue;
                    };
                    for (c, cell) in cols.iter().enumerate() {
                        if c >= 100 {
                            break;
                        }
                        let rr = r as u32;
                        let cc = c as u16;
                        match cell {
                            Value::Null => {}
                            Value::Bool(b) => {
                                worksheet.write_boolean(rr, cc, *b)?;
                            }
                            Value::Number(n) => {
                                if let Some(i) = n.as_i64() {
                                    worksheet.write_number(rr, cc, i as f64)?;
                                } else if let Some(f) = n.as_f64() {
                                    worksheet.write_number(rr, cc, f)?;
                                }
                            }
                            Value::String(s) => {
                                worksheet.write_string(rr, cc, s)?;
                            }
                            other => {
                                worksheet.write_string(rr, cc, &other.to_string())?;
                            }
                        }
                    }
                }
                workbook
                    .save(path)
                    .with_context(|| format!("无法保存：{path}"))?;
                Ok(text_result(format!("created {path}")))
            }
            other => bail!("unknown tool: {other}"),
        }
    }
}

fn ensure_parent(path: &str) -> Result<()> {
    if let Some(parent) = Path::new(path).parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    Ok(())
}
