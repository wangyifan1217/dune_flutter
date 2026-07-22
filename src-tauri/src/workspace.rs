use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Serialize;

use crate::models::FileEntry;

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
                path: entry.path().to_string_lossy().into_owned(),
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
    // 兼容 UTF-8 BOM（Windows 记事本 / Cursor 预览更稳）
    let slice = if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        &bytes[3..]
    } else {
        bytes.as_slice()
    };
    String::from_utf8(slice.to_vec()).with_context(|| format!("File is not valid UTF-8: {path}"))
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

pub fn absolutize(path: &str) -> Result<String> {
    let canonical = std::fs::canonicalize(path).with_context(|| format!("Invalid path: {path}"))?;
    Ok(canonical.to_string_lossy().into_owned())
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
        path: path.to_string_lossy().into_owned(),
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
