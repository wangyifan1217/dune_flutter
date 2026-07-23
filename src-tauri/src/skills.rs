//! Grok / Nova Build Skills（SKILL.md），存放于 ~/.grok/skills 与项目 .grok/skills。
//! Agent 进程会自动发现，无需 Node / 额外环境。

use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillInfo {
    pub id: String,
    pub name: String,
    pub description: String,
    pub scope: String,
    pub path: String,
}

fn user_skills_dir() -> PathBuf {
    let home = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".grok").join("skills")
}

fn project_skills_dir(workspace: Option<&str>) -> Option<PathBuf> {
    let w = workspace?.trim();
    if w.is_empty() {
        return None;
    }
    Some(Path::new(w).join(".grok").join("skills"))
}

fn parse_frontmatter(content: &str) -> (String, String) {
    let mut name = String::new();
    let mut description = String::new();
    let trimmed = content.trim_start();
    if !trimmed.starts_with("---") {
        return (name, description);
    }
    let rest = &trimmed[3..];
    let Some(end) = rest.find("---") else {
        return (name, description);
    };
    let yaml = &rest[..end];
    for line in yaml.lines() {
        let line = line.trim();
        if let Some(v) = line.strip_prefix("name:") {
            name = v.trim().trim_matches('"').trim_matches('\'').to_string();
        } else if let Some(v) = line.strip_prefix("description:") {
            let v = v.trim();
            if let Some(q) = v.strip_prefix('>') {
                description = q.trim().to_string();
            } else {
                description = v.trim_matches('"').trim_matches('\'').to_string();
            }
        }
    }
    // multi-line description: fold following indented lines after description: >
    if description.is_empty() {
        let mut collecting = false;
        let mut parts = Vec::new();
        for line in yaml.lines() {
            let t = line.trim_end();
            if t.trim_start().starts_with("description:") {
                collecting = true;
                if let Some(v) = t.trim_start().strip_prefix("description:") {
                    let v = v.trim().trim_start_matches('>').trim();
                    if !v.is_empty() {
                        parts.push(v.to_string());
                    }
                }
                continue;
            }
            if collecting {
                if line.starts_with(' ') || line.starts_with('\t') {
                    parts.push(line.trim().to_string());
                } else if line.trim().is_empty() {
                    continue;
                } else {
                    break;
                }
            }
        }
        if !parts.is_empty() {
            description = parts.join(" ");
        }
    }
    (name, description)
}

fn read_skill_dir(dir: &Path, scope: &str, out: &mut Vec<SkillInfo>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let skill_md = path.join("SKILL.md");
        if !skill_md.is_file() {
            continue;
        }
        let id = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("skill")
            .to_string();
        let content = fs::read_to_string(&skill_md).unwrap_or_default();
        let (mut name, description) = parse_frontmatter(&content);
        if name.is_empty() {
            name = id.clone();
        }
        out.push(SkillInfo {
            id,
            name,
            description,
            scope: scope.to_string(),
            path: path.to_string_lossy().into_owned(),
        });
    }
    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
}

pub fn list_skills(workspace: Option<&str>) -> Vec<SkillInfo> {
    let mut out = Vec::new();
    read_skill_dir(&user_skills_dir(), "user", &mut out);
    if let Some(dir) = project_skills_dir(workspace) {
        read_skill_dir(&dir, "project", &mut out);
    }
    out
}

fn sanitize_id(raw: &str) -> anyhow::Result<String> {
    let id = raw
        .trim()
        .to_ascii_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    if id.is_empty() {
        anyhow::bail!("技能名称无效");
    }
    if id.contains("..") {
        anyhow::bail!("技能名称非法");
    }
    Ok(id)
}

pub fn create_skill(
    workspace: Option<&str>,
    scope: &str,
    name: &str,
    description: &str,
) -> anyhow::Result<SkillInfo> {
    let id = sanitize_id(name)?;
    let root = if scope == "project" {
        project_skills_dir(workspace).ok_or_else(|| anyhow::anyhow!("请先打开项目再创建项目级 Skill"))?
    } else {
        user_skills_dir()
    };
    fs::create_dir_all(&root)?;
    let dir = root.join(&id);
    if dir.exists() {
        anyhow::bail!("已存在同名 Skill：{id}");
    }
    fs::create_dir_all(&dir)?;
    let desc = if description.trim().is_empty() {
        format!("Skill `{id}` for Nova Build / Grok agent")
    } else {
        description.trim().to_string()
    };
    let body = format!(
        "---\nname: {id}\ndescription: {desc}\n---\n\n# {name}\n\n在此编写该技能的使用说明、步骤与约束。\n\n## 何时使用\n\n- …\n\n## 步骤\n\n1. …\n"
    );
    let skill_md = dir.join("SKILL.md");
    fs::write(&skill_md, body)?;
    Ok(SkillInfo {
        id: id.clone(),
        name: name.trim().to_string(),
        description: desc,
        scope: if scope == "project" {
            "project".into()
        } else {
            "user".into()
        },
        path: dir.to_string_lossy().into_owned(),
    })
}

pub fn delete_skill(path: &str) -> anyhow::Result<()> {
    let path = Path::new(path);
    if !path.is_dir() {
        anyhow::bail!("Skill 目录不存在");
    }
    // 安全：必须是 …/skills/<id>
    let parent = path
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str())
        .unwrap_or("");
    if parent != "skills" {
        anyhow::bail!("只能删除 skills 目录下的技能");
    }
    if !path.join("SKILL.md").is_file() {
        anyhow::bail!("不是有效的 Skill 目录");
    }
    fs::remove_dir_all(path)?;
    Ok(())
}

pub fn read_skill_markdown(path: &str) -> anyhow::Result<String> {
    let skill_md = Path::new(path).join("SKILL.md");
    Ok(fs::read_to_string(skill_md)?)
}

pub fn write_skill_markdown(path: &str, content: &str) -> anyhow::Result<()> {
    let skill_md = Path::new(path).join("SKILL.md");
    if !skill_md.is_file() && !Path::new(path).is_dir() {
        anyhow::bail!("Skill 不存在");
    }
    if let Some(parent) = skill_md.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(skill_md, content)?;
    Ok(())
}

pub fn skills_folder_path(workspace: Option<&str>, scope: &str) -> anyhow::Result<PathBuf> {
    let dir = if scope == "project" {
        project_skills_dir(workspace)
            .ok_or_else(|| anyhow::anyhow!("请先打开项目"))?
    } else {
        user_skills_dir()
    };
    fs::create_dir_all(&dir)?;
    Ok(dir)
}
