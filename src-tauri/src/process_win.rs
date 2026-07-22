//! Windows 下隐藏子进程控制台窗口，避免 git / MCP / 工具调用时 CMD 闪屏。

#[cfg(windows)]
pub const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// 给 `std::process::Command` 加上 CREATE_NO_WINDOW（非 Windows 为空操作）。
pub fn hide_console(cmd: &mut std::process::Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

/// 给 `tokio::process::Command` 加上 CREATE_NO_WINDOW。
pub fn hide_console_tokio(cmd: &mut tokio::process::Command) {
    #[cfg(windows)]
    {
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = cmd;
    }
}

/// 以无窗口方式启动子进程，并继承当前 stdio（供 MCP 代理使用）。
pub fn run_hidden_child(argv: Vec<String>) -> i32 {
    if argv.is_empty() {
        eprintln!("nova-run-hidden: missing command");
        return 2;
    }
    let program = &argv[0];
    let args = &argv[1..];
    let mut cmd = std::process::Command::new(program);
    cmd.args(args)
        .stdin(std::process::Stdio::inherit())
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit());
    hide_console(&mut cmd);
    match cmd.status() {
        Ok(status) => status.code().unwrap_or(1),
        Err(err) => {
            eprintln!("nova-run-hidden: failed to start {program}: {err}");
            1
        }
    }
}

/// Windows 上将 MCP 命令包一层无窗口启动，避免 Agent 拉起时闪 CMD。
pub fn wrap_mcp_command(command: &str, args: &[String]) -> (String, Vec<String>) {
    #[cfg(windows)]
    {
        if command.ends_with("nova-desktop.exe")
            || args.first().is_some_and(|a| a == "--nova-run-hidden")
        {
            return (command.to_string(), args.to_vec());
        }
        if let Ok(exe) = std::env::current_exe() {
            let mut wrapped = Vec::with_capacity(args.len() + 2);
            wrapped.push("--nova-run-hidden".to_string());
            wrapped.push(command.to_string());
            wrapped.extend(args.iter().cloned());
            return (exe.to_string_lossy().into_owned(), wrapped);
        }
    }
    (command.to_string(), args.to_vec())
}
