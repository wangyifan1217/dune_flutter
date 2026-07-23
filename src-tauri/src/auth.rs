//! Dunes 登录（对齐 Flutter Desktop，但 channel=nova，不与 PC 工作台互踢）。

use std::time::Duration;

use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri_plugin_store::StoreExt;

const AUTH_STORE: &str = "auth.json";
const AUTH_SESSION_KEY: &str = "session";
const AUTH_API_BASE_KEY: &str = "apiBase";

/// 与 dunes Flutter 默认网关一致；可用设置覆盖。
pub const DEFAULT_API_BASE: &str = "http://124.221.216.24:6090/api/v1";
/// Nova Build 独立通道，后端 JWT `ch=nova` + `session_version_nova`。
const LOGIN_CHANNEL: &str = "nova";

fn http_agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(5))
        .timeout_read(Duration::from_secs(12))
        .timeout_write(Duration::from_secs(12))
        .build()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthSession {
    pub phone: String,
    pub user_id: i64,
    pub token: String,
    pub api_base: String,
    pub roles: Vec<String>,
    pub display_name: Option<String>,
    pub department_id: Option<i64>,
    pub user_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QrSession {
    pub session_id: String,
    pub client_secret: String,
    pub qr_code: String,
    pub ttl_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QrStatus {
    pub status: String,
    pub confirmed_user_name: Option<String>,
}

fn api_message(body: &Value) -> Option<String> {
    body.get("message")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn unwrap_data(body: Value) -> Result<Value, String> {
    if body.get("success") == Some(&Value::Bool(false)) {
        return Err(api_message(&body).unwrap_or_else(|| "请求失败".into()));
    }
    Ok(body.get("data").cloned().unwrap_or(body))
}

fn friendly_http_status(status: u16) -> &'static str {
    match status {
        400 => "请求参数有误，请检查后重试",
        401 => "登录已失效，请重新登录",
        403 => "账号无权限或已停用",
        404 => "请求的资源不存在",
        408 | 504 => "请求超时，请稍后重试",
        429 => "操作过于频繁，请稍后再试",
        500..=599 => "服务暂时不可用，请稍后重试",
        _ => "请求失败，请稍后重试",
    }
}

fn friendly_transport_error(err: &ureq::Error) -> String {
    let msg = err.to_string().to_ascii_lowercase();
    if msg.contains("timed out") || msg.contains("timeout") {
        return "网络超时，请检查网络后重试".into();
    }
    if msg.contains("connection")
        || msg.contains("dns")
        || msg.contains("failed to lookup")
        || msg.contains("refused")
    {
        return "无法连接服务器，请检查网络后重试".into();
    }
    "网络异常，请稍后重试".into()
}

fn parse_body_text(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|_| {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            json!({ "success": false })
        } else {
            json!({ "message": trimmed, "success": false })
        }
    })
}

fn response_to_result(status: u16, text: String) -> Result<(u16, Value), String> {
    let body = parse_body_text(&text);
    if (200..300).contains(&status) {
        return Ok((status, body));
    }
    Err(api_message(&body)
        .unwrap_or_else(|| friendly_http_status(status).to_string()))
}

fn post_json(url: &str, body: &Value, bearer: Option<&str>) -> Result<(u16, Value), String> {
    let agent = http_agent();
    let mut req = agent.post(url).set("Content-Type", "application/json");
    if let Some(token) = bearer {
        req = req.set("Authorization", &format!("Bearer {token}"));
    }
    match req.send_string(&body.to_string()) {
        Ok(resp) => {
            let status = resp.status();
            let text = resp
                .into_string()
                .map_err(|_| "读取服务器响应失败".to_string())?;
            response_to_result(status, text)
        }
        Err(ureq::Error::Status(status, resp)) => {
            let text = resp.into_string().unwrap_or_default();
            response_to_result(status, text)
        }
        Err(err) => Err(friendly_transport_error(&err)),
    }
}

fn get_json(url: &str, bearer: &str) -> Result<(u16, Value), String> {
    let agent = http_agent();
    match agent
        .get(url)
        .set("Authorization", &format!("Bearer {bearer}"))
        .call()
    {
        Ok(resp) => {
            let status = resp.status();
            let text = resp
                .into_string()
                .map_err(|_| "读取服务器响应失败".to_string())?;
            response_to_result(status, text)
        }
        Err(ureq::Error::Status(status, resp)) => {
            let text = resp.into_string().unwrap_or_default();
            response_to_result(status, text)
        }
        Err(err) => Err(friendly_transport_error(&err)),
    }
}

fn decode_jwt_claims(token: &str) -> Value {
    let parts: Vec<_> = token.split('.').collect();
    if parts.len() < 2 {
        return json!({});
    }
    let mut payload = parts[1].replace('-', "+").replace('_', "/");
    while payload.len() % 4 != 0 {
        payload.push('=');
    }
    let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(payload) else {
        return json!({});
    };
    serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}))
}

fn session_from_token(token: &str, phone: &str, api_base: &str) -> AuthSession {
    let claims = decode_jwt_claims(token);
    let roles = claims
        .get("roles")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    let user_id = claims
        .get("userId")
        .and_then(Value::as_i64)
        .or_else(|| {
            claims
                .get("sub")
                .and_then(Value::as_str)
                .and_then(|s| s.parse().ok())
        })
        .unwrap_or(0);
    let user_type = claims
        .get("userType")
        .and_then(Value::as_str)
        .map(|s| s.to_ascii_uppercase())
        .unwrap_or_else(|| {
            if claims.get("external") == Some(&Value::Bool(true)) {
                "EXTERNAL".into()
            } else {
                "ORG".into()
            }
        });
    AuthSession {
        phone: phone.to_string(),
        user_id,
        token: token.to_string(),
        api_base: api_base.to_string(),
        roles,
        display_name: claims
            .get("displayName")
            .and_then(Value::as_str)
            .map(str::to_string),
        department_id: claims.get("departmentId").and_then(Value::as_i64),
        user_type,
    }
}

fn enrich_from_me(mut session: AuthSession) -> AuthSession {
    let url = format!("{}/users/me", session.api_base.trim_end_matches('/'));
    let Ok((status, body)) = get_json(&url, &session.token) else {
        return session;
    };
    if !(200..300).contains(&status) {
        return session;
    }
    let Ok(data) = unwrap_data(body) else {
        return session;
    };
    if let Some(name) = data.get("displayName").and_then(Value::as_str) {
        session.display_name = Some(name.to_string());
    }
    if let Some(id) = data.get("departmentId").and_then(Value::as_i64) {
        session.department_id = Some(id);
    }
    if let Some(ut) = data.get("userType").and_then(Value::as_str) {
        session.user_type = ut.to_ascii_uppercase();
    }
    if let Some(phone) = data.get("phone").and_then(Value::as_str) {
        if !phone.is_empty() {
            session.phone = phone.to_string();
        }
    }
    session
}

pub fn get_api_base(app: &AppHandle) -> String {
    let Ok(store) = app.store(AUTH_STORE) else {
        return DEFAULT_API_BASE.into();
    };
    store
        .get(AUTH_API_BASE_KEY)
        .and_then(|v| v.as_str().map(str::to_string))
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_API_BASE.into())
}

pub fn set_api_base(app: &AppHandle, api_base: &str) -> Result<(), String> {
    let store = app.store(AUTH_STORE).map_err(|e| e.to_string())?;
    let base = api_base.trim().trim_end_matches('/').to_string();
    if base.is_empty() {
        store.delete(AUTH_API_BASE_KEY);
    } else {
        store.set(AUTH_API_BASE_KEY, Value::String(base));
    }
    store.save().map_err(|e| e.to_string())
}

pub fn load_session(app: &AppHandle) -> Option<AuthSession> {
    let store = app.store(AUTH_STORE).ok()?;
    let value = store.get(AUTH_SESSION_KEY)?;
    serde_json::from_value(value).ok()
}

pub fn save_session(app: &AppHandle, session: &AuthSession) -> Result<(), String> {
    let store = app.store(AUTH_STORE).map_err(|e| e.to_string())?;
    store.set(
        AUTH_SESSION_KEY,
        serde_json::to_value(session).map_err(|e| e.to_string())?,
    );
    store.set(AUTH_API_BASE_KEY, Value::String(session.api_base.clone()));
    store.save().map_err(|e| e.to_string())
}

pub fn clear_session(app: &AppHandle) -> Result<(), String> {
    let store = app.store(AUTH_STORE).map_err(|e| e.to_string())?;
    store.delete(AUTH_SESSION_KEY);
    store.save().map_err(|e| e.to_string())
}

/// 启动时校验本地会话；401 时可尝试 refresh。
pub fn restore_session(app: &AppHandle) -> Result<Option<AuthSession>, String> {
    let Some(session) = load_session(app) else {
        return Ok(None);
    };
    let url = format!("{}/users/me", session.api_base.trim_end_matches('/'));
    match get_json(&url, &session.token) {
        Ok((_status, body)) => {
            let mut next = session;
            if let Ok(data) = unwrap_data(body) {
                if let Some(name) = data.get("displayName").and_then(Value::as_str) {
                    next.display_name = Some(name.to_string());
                }
                if let Some(phone) = data.get("phone").and_then(Value::as_str) {
                    if !phone.is_empty() {
                        next.phone = phone.to_string();
                    }
                }
            }
            let _ = save_session(app, &next);
            Ok(Some(next))
        }
        Err(_) => match refresh_token(app, &session) {
            Ok(next) => Ok(Some(next)),
            Err(_) => {
                let _ = clear_session(app);
                Ok(None)
            }
        },
    }
}

pub fn refresh_token(app: &AppHandle, session: &AuthSession) -> Result<AuthSession, String> {
    let url = format!(
        "{}/auth/session/refresh",
        session.api_base.trim_end_matches('/')
    );
    let (_status, body) = post_json(&url, &json!({}), Some(&session.token))?;
    let data = unwrap_data(body)?;
    let token = data
        .get("token")
        .and_then(Value::as_str)
        .ok_or_else(|| "登录已失效，请重新登录".to_string())?;
    let mut next = session_from_token(token, &session.phone, &session.api_base);
    next = enrich_from_me(next);
    save_session(app, &next)?;
    Ok(next)
}

pub fn request_sms(app: &AppHandle, phone: &str) -> Result<(), String> {
    let phone = phone.trim();
    if !phone.chars().all(|c| c.is_ascii_digit()) || phone.len() != 11 {
        return Err("请输入 11 位手机号".into());
    }
    let api_base = get_api_base(app);
    let url = format!("{}/auth/sms/request", api_base.trim_end_matches('/'));
    let (status, body) = post_json(
        &url,
        &json!({ "phone": phone, "channel": LOGIN_CHANNEL }),
        None,
    )?;
    let _ = status;
    let _ = body;
    Ok(())
}

pub fn sign_in_sms(app: &AppHandle, phone: &str, code: &str) -> Result<AuthSession, String> {
    let phone = phone.trim();
    let code = code.trim();
    if phone.len() != 11 {
        return Err("请输入 11 位手机号".into());
    }
    if code.len() != 6 || !code.chars().all(|c| c.is_ascii_digit()) {
        return Err("请输入 6 位验证码".into());
    }
    let api_base = get_api_base(app);
    let url = format!("{}/auth/sms/token", api_base.trim_end_matches('/'));
    let (_status, body) = post_json(
        &url,
        &json!({ "phone": phone, "code": code, "channel": LOGIN_CHANNEL }),
        None,
    )?;
    let data = unwrap_data(body)?;
    let token = data
        .get("token")
        .and_then(Value::as_str)
        .ok_or_else(|| "登录失败，请稍后重试".to_string())?;
    let mut session = session_from_token(token, phone, &api_base);
    session = enrich_from_me(session);
    save_session(app, &session)?;
    Ok(session)
}

pub fn create_qr_session(app: &AppHandle) -> Result<QrSession, String> {
    let api_base = get_api_base(app);
    let url = format!("{}/auth/qr/session", api_base.trim_end_matches('/'));
    let (_status, body) = post_json(&url, &json!({ "channel": LOGIN_CHANNEL }), None)?;
    let data = unwrap_data(body)?;
    Ok(QrSession {
        session_id: data
            .get("sessionId")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        client_secret: data
            .get("clientSecret")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        qr_code: data
            .get("qrCode")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        ttl_seconds: data
            .get("ttlSeconds")
            .and_then(Value::as_u64)
            .unwrap_or(120),
    })
}

pub fn poll_qr_status(
    app: &AppHandle,
    session_id: &str,
    client_secret: &str,
) -> Result<QrStatus, String> {
    let api_base = get_api_base(app);
    let url = format!("{}/auth/qr/status", api_base.trim_end_matches('/'));
    let (_status, body) = post_json(
        &url,
        &json!({ "sessionId": session_id, "clientSecret": client_secret }),
        None,
    )?;
    let data = unwrap_data(body)?;
    Ok(QrStatus {
        status: data
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("PENDING")
            .to_string(),
        confirmed_user_name: data
            .get("confirmedUserName")
            .and_then(Value::as_str)
            .map(str::to_string),
    })
}

pub fn sign_in_qr(
    app: &AppHandle,
    session_id: &str,
    client_secret: &str,
) -> Result<AuthSession, String> {
    let api_base = get_api_base(app);
    let url = format!("{}/auth/qr/token", api_base.trim_end_matches('/'));
    let (_status, body) = post_json(
        &url,
        &json!({ "sessionId": session_id, "clientSecret": client_secret }),
        None,
    )?;
    let data = unwrap_data(body)?;
    let token = data
        .get("token")
        .and_then(Value::as_str)
        .ok_or_else(|| "扫码登录失败，请刷新二维码后重试".to_string())?;
    let mut session = session_from_token(token, "", &api_base);
    session = enrich_from_me(session);
    save_session(app, &session)?;
    Ok(session)
}
