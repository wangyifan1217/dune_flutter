use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::Mutex;
use tauri::{AppHandle, Emitter};
use tokio::sync::{oneshot, Mutex as AsyncMutex};

use crate::acp::AgentHandle;
use crate::models::{AgentStatus, AppSettings};

pub struct AppState {
    pub settings: Arc<Mutex<AppSettings>>,
    pub workspace: Mutex<Option<String>>,
    /// 每个前端对话各自持有一个 ACP 进程和 session，互不阻塞。
    pub agents: Arc<AsyncMutex<HashMap<String, Arc<AgentHandle>>>>,
    pub status: Arc<Mutex<AgentStatus>>,
    /// 等待前端批准的权限请求（JSON-RPC id 可能是数字或字符串）
    pub permission_waiters: Arc<Mutex<HashMap<String, oneshot::Sender<bool>>>>,
}

impl AppState {
    pub fn new(settings: AppSettings) -> Self {
        Self {
            settings: Arc::new(Mutex::new(settings)),
            workspace: Mutex::new(None),
            agents: Arc::new(AsyncMutex::new(HashMap::new())),
            status: Arc::new(Mutex::new(AgentStatus::default())),
            permission_waiters: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn set_status(&self, status: AgentStatus) {
        *self.status.lock() = status;
    }

    pub fn snapshot_status(&self) -> AgentStatus {
        self.status.lock().clone()
    }

    pub async fn disconnect(&self) -> anyhow::Result<()> {
        let agents = {
            let mut guard = self.agents.lock().await;
            std::mem::take(&mut *guard)
        };
        for agent in agents.into_values() {
            agent.shutdown().await?;
        }
        self.set_status(AgentStatus {
            connected: false,
            session_id: None,
            workspace: self.workspace.lock().clone(),
            message: "已断开".into(),
        });
        Ok(())
    }

    pub async fn connect(&self, workspace: &str, app: AppHandle) -> anyhow::Result<()> {
        self.disconnect().await?;
        let status = AgentStatus {
            connected: true,
            session_id: None,
            workspace: Some(workspace.to_owned()),
            message: "已连接".into(),
        };
        *self.workspace.lock() = Some(workspace.to_owned());
        self.set_status(status.clone());
        let _ = app.emit("agent://status", &status);
        Ok(())
    }

    pub async fn agent_for_session(
        &self,
        thread_id: &str,
        workspace: &str,
        app: AppHandle,
    ) -> anyhow::Result<Arc<AgentHandle>> {
        {
            let agents = self.agents.lock().await;
            if let Some(agent) = agents.get(thread_id).cloned() {
                return Ok(agent);
            }
        }

        // 启动/握手可能较久：不要一直占着 agents 锁，否则其它会话也会一起卡住。
        let settings = self.settings.lock().clone();
        let agent = Arc::new(
            AgentHandle::spawn(
                &settings,
                workspace,
                thread_id.to_owned(),
                app,
                Arc::clone(&self.permission_waiters),
                Arc::clone(&self.settings),
            )
            .await?,
        );

        let mut agents = self.agents.lock().await;
        if let Some(existing) = agents.get(thread_id).cloned() {
            // 并发启动时保留先登记的那个，关掉后启的。
            let _ = agent.shutdown().await;
            return Ok(existing);
        }
        agents.insert(thread_id.to_owned(), Arc::clone(&agent));
        Ok(agent)
    }

    pub async fn cancel_session_prompt(&self, thread_id: &str) -> anyhow::Result<()> {
        let agents = self.agents.lock().await;
        let agent = agents
            .get(thread_id)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("该会话没有正在运行的 Agent"))?;
        drop(agents);
        agent.cancel_prompt().await
    }

    pub fn resolve_permission(&self, id: &str, allow: bool) -> bool {
        if let Some(tx) = self.permission_waiters.lock().remove(id) {
            let _ = tx.send(allow);
            true
        } else {
            false
        }
    }
}
