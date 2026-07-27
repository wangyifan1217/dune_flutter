//! 对接网关 `/v1/models`：列出可用模型，并把用户填写的 id 对齐到规范大小写。

use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GatewayModel {
    pub id: String,
    pub label: String,
}

fn fetch_models_json(base_url: &str, api_key: &str) -> Result<Value, String> {
    let base = base_url.trim().trim_end_matches('/');
    if base.is_empty() {
        return Err("请先填写 Base URL".into());
    }
    let url = format!("{base}/models");
    let mut req = ureq::get(&url);
    if !api_key.trim().is_empty() {
        req = req.set("Authorization", &format!("Bearer {}", api_key.trim()));
    }
    let resp = req
        .timeout(std::time::Duration::from_secs(15))
        .call()
        .map_err(|e| format!("请求模型列表失败：{e}"))?;
    resp.into_json::<Value>()
        .map_err(|e| format!("解析模型列表失败：{e}"))
}

fn parse_model_entries(body: &Value) -> Vec<GatewayModel> {
    let Some(models) = body.get("data").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for item in models {
        let Some(id) = item.get("id").and_then(Value::as_str).map(str::trim) else {
            continue;
        };
        if id.is_empty() || !seen.insert(id.to_string()) {
            continue;
        }
        let display = item
            .get("name")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or(id);
        out.push(GatewayModel {
            id: id.to_string(),
            label: display.to_string(),
        });
    }
    out.sort_by(|a, b| a.id.to_ascii_lowercase().cmp(&b.id.to_ascii_lowercase()));
    out
}

/// 列出网关上的模型（OpenAI 兼容 `{ data: [{ id, ... }] }`）。
pub fn list_gateway_models(base_url: &str, api_key: &str) -> Result<Vec<GatewayModel>, String> {
    let body = fetch_models_json(base_url, api_key)?;
    let list = parse_model_entries(&body);
    if list.is_empty() {
        return Err("网关未返回任何模型（检查 Base URL / API Key 是否有权限）".into());
    }
    Ok(list)
}

/// 查询 `{base}/models`，按精确 / 忽略大小写匹配，返回网关侧的规范 id。
/// 失败时原样返回 `wanted`，不阻断启动。
pub fn resolve_gateway_model_id(base_url: &str, api_key: &str, wanted: &str) -> String {
    let wanted = wanted.trim();
    let base = base_url.trim().trim_end_matches('/');
    if wanted.is_empty() || base.is_empty() {
        return wanted.to_string();
    }

    let Ok(body) = fetch_models_json(base, api_key) else {
        return wanted.to_string();
    };
    let models = parse_model_entries(&body);

    if let Some(hit) = models.iter().find(|m| m.id == wanted) {
        return hit.id.clone();
    }
    let lower = wanted.to_ascii_lowercase();
    if let Some(hit) = models
        .iter()
        .find(|m| m.id.to_ascii_lowercase() == lower)
    {
        return hit.id.clone();
    }

    wanted.to_string()
}
