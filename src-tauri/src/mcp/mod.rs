//! 应用内置 MCP（stdio JSON-RPC），不依赖用户安装 Node.js / Python / Office。

mod excel;
mod fetch;
mod filesystem;
mod memory;
mod powerpoint;
mod protocol;
mod sequential;
mod word;

use protocol::McpServer;

/// CLI：`--mcp-server <name> [args…]`
pub fn run_mcp_server(argv: Vec<String>) -> i32 {
    let Some((name, rest)) = argv.split_first() else {
        eprintln!(
            "usage: nova-desktop --mcp-server <sequential-thinking|filesystem|memory|fetch|excel|word|powerpoint> [args]"
        );
        return 2;
    };
    let name = name.as_str();
    let rest = rest.to_vec();
    let result = match name {
        "sequential-thinking" | "sequential_thinking" => {
            sequential::SequentialThinkingServer::default().serve_stdio()
        }
        "filesystem" => {
            let root = rest.first().cloned().unwrap_or_else(|| {
                std::env::current_dir()
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_else(|_| ".".into())
            });
            filesystem::FilesystemServer::new(root).serve_stdio()
        }
        "memory" => memory::MemoryServer::open_default().and_then(|s| s.serve_stdio()),
        "fetch" => fetch::FetchServer.serve_stdio(),
        "excel" => excel::ExcelServer.serve_stdio(),
        "word" => word::WordServer.serve_stdio(),
        "powerpoint" | "pptx" => powerpoint::PowerpointServer.serve_stdio(),
        other => {
            eprintln!("unknown built-in MCP server: {other}");
            return 2;
        }
    };
    match result {
        Ok(()) => 0,
        Err(err) => {
            eprintln!("mcp-server {name} failed: {err:#}");
            1
        }
    }
}

/// 把前端的 `nova-builtin` 展开为当前可执行文件 + `--mcp-server …`
pub fn expand_builtin_mcp(command: &str, args: &[String]) -> Option<(String, Vec<String>)> {
    let is_builtin = matches!(
        command.trim(),
        "nova-builtin" | "__nova__" | "nova-desktop-builtin"
    );
    if !is_builtin {
        return None;
    }
    let exe = std::env::current_exe().ok()?;
    let mut out = vec!["--mcp-server".to_string()];
    out.extend(args.iter().cloned());
    Some((exe.to_string_lossy().into_owned(), out))
}
