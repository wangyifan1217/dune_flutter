use anyhow::{Context, Result};
use serde::Serialize;
use std::path::Path;
use std::process::Command;

const MAX_LISTED_CHANGES: usize = 80;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GitFileChange {
    pub path: String,
    pub status: String,
    /// 列表阶段可为空，展开时再懒加载
    pub diff: String,
}

fn run_git(cwd: &Path, args: &[&str]) -> Result<String> {
    let mut cmd = Command::new("git");
    cmd.args(args)
        .current_dir(cwd)
        .env("GIT_OPTIONAL_LOCKS", "1")
        .env("GIT_TERMINAL_PROMPT", "0");
    crate::process_win::hide_console(&mut cmd);
    let output = cmd
        .output()
        .with_context(|| "无法执行 git（请确认已安装 Git）")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!(stderr.trim().to_string());
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// 只列变更路径，不逐文件跑 diff（打开项目时必须快）
pub fn list_changes(cwd: &str) -> Result<Vec<GitFileChange>> {
    let root = Path::new(cwd);
    // 未跟踪目录只显示目录本身，避免扫出海量文件
    let status = run_git(root, &["status", "--porcelain", "-unormal"])?;
    let mut changes = Vec::new();

    for line in status.lines() {
        if line.len() < 4 {
            continue;
        }
        let code = line[..2].to_string();
        let mut path = line[3..].trim().to_string();
        if path.is_empty() {
            continue;
        }
        // 处理 "old -> new" 重命名
        if let Some((_, new_path)) = path.split_once(" -> ") {
            path = new_path.trim().to_string();
        }
        // 去掉引号
        if path.starts_with('"') && path.ends_with('"') && path.len() >= 2 {
            path = path[1..path.len() - 1].to_string();
        }

        changes.push(GitFileChange {
            path,
            status: code.trim().to_string(),
            diff: String::new(),
        });

        if changes.len() >= MAX_LISTED_CHANGES {
            break;
        }
    }

    Ok(changes)
}

/// 展开某文件时再取 diff
pub fn file_diff(cwd: &str, path: &str) -> Result<String> {
    let root = Path::new(cwd);
    let status = run_git(root, &["status", "--porcelain", "--", path])?;
    let line = status.lines().next().unwrap_or("");
    if line.starts_with("??") || line.as_bytes().get(1) == Some(&b'?') {
        let full = root.join(path);
        if full.is_dir() {
            return Ok(format!("(未跟踪目录) {path}/"));
        }
        let preview = std::fs::read_to_string(&full).unwrap_or_default();
        let clipped: String = preview.chars().take(4000).collect();
        return Ok(format!("+++ b/{path}\n{clipped}"));
    }

    let unstaged = run_git(root, &["diff", "--", path]).unwrap_or_default();
    if !unstaged.trim().is_empty() {
        return Ok(unstaged);
    }
    let staged = run_git(root, &["diff", "--cached", "--", path]).unwrap_or_default();
    if !staged.trim().is_empty() {
        return Ok(staged);
    }
    Ok("(无 diff 内容)".into())
}

/// 拒绝改动：对已跟踪文件用 checkout 还原；未跟踪文件删除
pub fn reject_change(cwd: &str, path: &str) -> Result<()> {
    let root = Path::new(cwd);
    let status = run_git(root, &["status", "--porcelain", "--", path])?;
    let line = status.lines().next().unwrap_or("");
    if line.starts_with("??") {
        let full = root.join(path);
        if full.is_dir() {
            std::fs::remove_dir_all(&full)?;
        } else if full.exists() {
            std::fs::remove_file(&full)?;
        }
    } else {
        let _ = run_git(root, &["checkout", "--", path]);
        let _ = run_git(root, &["clean", "-f", "--", path]);
    }
    Ok(())
}

pub fn accept_change(cwd: &str, path: &str) -> Result<()> {
    let root = Path::new(cwd);
    let _ = run_git(root, &["add", "--", path])?;
    Ok(())
}

pub fn reject_all(cwd: &str) -> Result<()> {
    let root = Path::new(cwd);
    let _ = run_git(root, &["checkout", "--", "."]);
    let _ = run_git(root, &["clean", "-fd"]);
    Ok(())
}
