// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // 轻量子模式：被 Agent 用来无窗口拉起 MCP / 工具进程，避免 CMD 闪屏。
    let mut args = std::env::args().skip(1).peekable();
    if args.peek().map(|s| s.as_str()) == Some("--nova-run-hidden") {
        let _ = args.next();
        std::process::exit(nova_desktop_lib::run_hidden_child(args.collect()));
    }

    nova_desktop_lib::run()
}
