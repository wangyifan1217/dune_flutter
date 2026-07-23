//! 把用户填写的模型 ID 对齐到网关 `/v1/models` 返回的真实 id（主要修大小写）。

use serde_json::Value;

/// 查询 `{base}/models`，按精确 / 忽略大小写匹配，返回网关侧的规范 id。
/// 失败时原样返回 `wanted`，不阻断启动。
pub fn resolve_gateway_model_id(base_url: &str, api_key: &str, wanted: &str) -> String {
    let wanted = wanted.trim();
    let base = base_url.trim().trim_end_matches('/');
    if wanted.is_empty() || base.is_empty() {
        return wanted.to_string();
    }

    let url = format!("{base}/models");
    let mut req = ureq::get(&url);
    if !api_key.trim().is_empty() {
        req = req.set("Authorization", &format!("Bearer {}", api_key.trim()));
    }

    let Ok(resp) = req.timeout(std::time::Duration::from_secs(8)).call() else {
        return wanted.to_string();
    };
    let Ok(body) = resp.into_json::<Value>() else {
        return wanted.to_string();
    };
    let Some(models) = body.get("data").and_then(Value::as_array) else {
        return wanted.to_string();
    };

    for item in models {
        if let Some(id) = item.get("id").and_then(Value::as_str) {
            if id == wanted {
                return id.to_string();
            }
        }
    }

    let lower = wanted.to_ascii_lowercase();
    for item in models {
        if let Some(id) = item.get("id").and_then(Value::as_str) {
            if id.to_ascii_lowercase() == lower {
                return id.to_string();
            }
        }
    }

    wanted.to_string()
}
