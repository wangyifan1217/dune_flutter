use std::io::{Read, Write};
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use parking_lot::Mutex;
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::Mutex as AsyncMutex;

pub struct TerminalSession {
    master: Mutex<Box<dyn MasterPty + Send>>,
    writer: Mutex<Box<dyn Write + Send>>,
}

pub struct TerminalState {
    pub session: AsyncMutex<Option<TerminalSession>>,
}

impl TerminalState {
    pub fn new() -> Self {
        Self {
            session: AsyncMutex::new(None),
        }
    }
}

pub async fn start_terminal(app: AppHandle, cwd: Option<String>) -> Result<()> {
    let state = app.state::<Arc<TerminalState>>();
    let mut guard = state.session.lock().await;
    if guard.is_some() {
        return Ok(());
    }

    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: 30,
            cols: 100,
            pixel_width: 0,
            pixel_height: 0,
        })
        .context("打开伪终端失败")?;

    let shell = if cfg!(target_os = "windows") {
        std::env::var("COMSPEC").unwrap_or_else(|_| "powershell.exe".into())
    } else {
        std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".into())
    };

    let mut cmd = CommandBuilder::new(shell);
    if cfg!(target_os = "windows") {
        // Prefer PowerShell if available
        if which_powershell() {
            cmd = CommandBuilder::new("powershell.exe");
            cmd.arg("-NoLogo");
        }
    }
    if let Some(cwd) = cwd {
        cmd.cwd(cwd);
    }

    let _child = pair
        .slave
        .spawn_command(cmd)
        .context("启动终端进程失败")?;

    let mut reader = pair
        .master
        .try_clone_reader()
        .context("克隆终端输出流失败")?;
    let writer = pair
        .master
        .take_writer()
        .context("获取终端输入流失败")?;

    let app_reader = app.clone();
    std::thread::spawn(move || {
        let mut buf = [0u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let chunk = String::from_utf8_lossy(&buf[..n]).to_string();
                    let _ = app_reader.emit("terminal://data", chunk);
                }
                Err(_) => break,
            }
        }
        let _ = app_reader.emit("terminal://exit", ());
    });

    *guard = Some(TerminalSession {
        master: Mutex::new(pair.master),
        writer: Mutex::new(writer),
    });

    Ok(())
}

fn which_powershell() -> bool {
    let mut cmd = std::process::Command::new("powershell.exe");
    cmd.arg("-NoLogo").arg("-WindowStyle").arg("Hidden").arg("-Command").arg("exit 0");
    crate::process_win::hide_console(&mut cmd);
    cmd.output().is_ok()
}

pub async fn write_terminal(app: &AppHandle, data: &str) -> Result<()> {
    let state = app.state::<Arc<TerminalState>>();
    let guard = state.session.lock().await;
    let session = guard.as_ref().ok_or_else(|| anyhow!("终端未启动"))?;
    let mut writer = session.writer.lock();
    writer.write_all(data.as_bytes())?;
    writer.flush()?;
    Ok(())
}

pub async fn resize_terminal(app: &AppHandle, rows: u16, cols: u16) -> Result<()> {
    let state = app.state::<Arc<TerminalState>>();
    let guard = state.session.lock().await;
    let session = guard.as_ref().ok_or_else(|| anyhow!("终端未启动"))?;
    session.master.lock().resize(PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    })?;
    Ok(())
}

pub async fn stop_terminal(app: &AppHandle) -> Result<()> {
    let state = app.state::<Arc<TerminalState>>();
    let mut guard = state.session.lock().await;
    *guard = None;
    Ok(())
}
