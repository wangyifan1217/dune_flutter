// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    let mut args = std::env::args().skip(1).peekable();
    match args.peek().map(|s| s.as_str()) {
        Some("--nova-run-hidden") => {
            let _ = args.next();
            std::process::exit(nova_desktop_lib::run_hidden_child(args.collect()));
        }
        Some("--create-blank-pptx") => {
            let _ = args.next();
            std::process::exit(nova_desktop_lib::run_create_blank_pptx(args.collect()));
        }
        Some("--create-pptx-json") => {
            let _ = args.next();
            std::process::exit(nova_desktop_lib::run_create_pptx_json(args.collect()));
        }
        Some("--mcp-server") => {
            let _ = args.next();
            std::process::exit(nova_desktop_lib::run_mcp_server(args.collect()));
        }
        _ => nova_desktop_lib::run(),
    }
}
