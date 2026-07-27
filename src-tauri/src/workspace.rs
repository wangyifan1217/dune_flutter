use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Serialize;

use crate::models::FileEntry;

/// Windows `canonicalize` 会加上 `\\?\` 前缀；传给 grok / 会话目录时会变成
/// URL 编码的奇怪路径（如 `%5C%5C%3F%5CD%3A%5C...`），导致资源读写异常。
pub fn strip_verbatim_prefix(path: PathBuf) -> PathBuf {
    let s = path.to_string_lossy();
    #[cfg(windows)]
    {
        if let Some(rest) = s.strip_prefix(r"\\?\") {
            if let Some(unc) = rest.strip_prefix(r"UNC\") {
                return PathBuf::from(format!(r"\\{unc}"));
            }
            return PathBuf::from(rest);
        }
    }
    let _ = &s;
    path
}

fn looks_like_binary(path: &str, bytes: &[u8]) -> bool {
    let ext = Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    matches!(
        ext.as_str(),
        "png"
            | "jpg"
            | "jpeg"
            | "gif"
            | "webp"
            | "bmp"
            | "ico"
            | "pdf"
            | "zip"
            | "exe"
            | "dll"
            | "pptx"
            | "xlsx"
            | "docx"
            | "wasm"
            | "mp3"
            | "mp4"
            | "mov"
            | "woff"
            | "woff2"
            | "ttf"
            | "otf"
    ) || bytes.iter().take(8192).any(|&b| b == 0)
}

pub fn list_directory(path: &str) -> Result<Vec<FileEntry>> {
    let root = PathBuf::from(path);
    if !root.is_dir() {
        anyhow::bail!("Path is not a directory: {path}");
    }

    let mut entries = std::fs::read_dir(&root)
        .with_context(|| format!("Failed to read directory: {path}"))?
        .filter_map(|entry| entry.ok())
        .map(|entry| {
            let metadata = entry.metadata().ok();
            let name = entry.file_name().to_string_lossy().into_owned();
            let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
            FileEntry {
                name,
                path: strip_verbatim_prefix(entry.path())
                    .to_string_lossy()
                    .into_owned(),
                is_dir,
            }
        })
        .collect::<Vec<_>>();

    entries.sort_by(|a, b| {
        match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        }
    });

    Ok(entries)
}

pub fn read_text_file(path: &str) -> Result<String> {
    let bytes =
        std::fs::read(path).with_context(|| format!("Failed to read file: {path}"))?;
    if looks_like_binary(path, &bytes) {
        anyhow::bail!(
            "这是二进制/图片文件，不能按文本读取：{path}。若对话中已附带图片，请直接根据图片内容继续；不要再用 read_text_file 打开图片。"
        );
    }
    // 兼容 UTF-8 BOM（Windows 记事本 / Cursor 预览更稳）
    let slice = if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        &bytes[3..]
    } else {
        bytes.as_slice()
    };
    match String::from_utf8(slice.to_vec()) {
        Ok(text) => Ok(text),
        Err(_) => {
            // 少数 ANSI/GBK 文本：有损转 UTF-8，避免整轮对话卡死
            Ok(String::from_utf8_lossy(slice).into_owned())
        }
    }
}

pub fn write_text_file(path: &str, content: &str) -> Result<()> {
    if let Some(parent) = Path::new(path).parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create parent directory for {path}"))?;
    }
    // 写入 UTF-8 BOM，避免 Windows 下中文乱码
    let mut bytes = vec![0xEF, 0xBB, 0xBF];
    bytes.extend_from_slice(content.as_bytes());
    std::fs::write(path, bytes).with_context(|| format!("Failed to write file: {path}"))
}

/// 写前读旧内容，写后返回是否新建 + unified diff（供会话内改码卡展示）。
pub fn write_text_file_with_diff(
    path: &str,
    content: &str,
) -> Result<crate::diff_text::WriteFileDiff> {
    let path_obj = Path::new(path);
    let created = !path_obj.exists();
    let old = if created {
        String::new()
    } else {
        read_text_file(path).unwrap_or_default()
    };
    write_text_file(path, content)?;
    let display = path_obj
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(path);
    let diff = crate::diff_text::unified_line_diff(&old, content, display);
    Ok(crate::diff_text::WriteFileDiff { created, diff })
}

pub fn absolutize(path: &str) -> Result<String> {
    let canonical = std::fs::canonicalize(path).with_context(|| format!("Invalid path: {path}"))?;
    Ok(strip_verbatim_prefix(canonical)
        .to_string_lossy()
        .into_owned())
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DirectoryTreeNode {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub children: Option<Vec<DirectoryTreeNode>>,
}

pub fn build_tree(path: &str, depth: u32) -> Result<DirectoryTreeNode> {
    let root = PathBuf::from(path);
    build_node(&root, depth)
}

const MAX_CHILDREN_PER_DIR: usize = 120;

fn build_node(path: &Path, depth: u32) -> Result<DirectoryTreeNode> {
    let metadata = std::fs::metadata(path)?;
    let name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned());

    let mut node = DirectoryTreeNode {
        name,
        path: strip_verbatim_prefix(path.to_path_buf())
            .to_string_lossy()
            .into_owned(),
        is_dir: metadata.is_dir(),
        children: None,
    };

    if metadata.is_dir() && depth > 0 {
        let mut children = list_directory(path.to_string_lossy().as_ref())?
            .into_iter()
            .filter(|entry| !should_skip(&entry.name))
            .take(MAX_CHILDREN_PER_DIR)
            .filter_map(|entry| build_node(Path::new(&entry.path), depth - 1).ok())
            .collect::<Vec<_>>();
        children.sort_by(|a, b| match (a.is_dir, b.is_dir) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
        });
        node.children = Some(children);
    }

    Ok(node)
}

fn should_skip(name: &str) -> bool {
    matches!(
        name,
        "node_modules" | ".git" | "target" | "dist" | ".next" | "__pycache__" | ".venv" | "venv"
    ) || name.starts_with('.')
}
