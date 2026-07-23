import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface SkillInfo {
  id: string;
  name: string;
  description: string;
  scope: "user" | "project" | string;
  path: string;
}

interface SkillsModalProps {
  open: boolean;
  workspace?: string | null;
  onClose: () => void;
}

export function SkillsModal({ open, workspace, onClose }: SkillsModalProps) {
  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [scope, setScope] = useState<"user" | "project">("user");
  const [editing, setEditing] = useState<SkillInfo | null>(null);
  const [markdown, setMarkdown] = useState("");
  const [saving, setSaving] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const list = await invoke<SkillInfo[]>("list_skills");
      setSkills(list);
      setError(null);
    } catch (e) {
      setError(String(e));
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    setCreating(false);
    setEditing(null);
    void refresh();
  }, [open, refresh, workspace]);

  if (!open) return null;

  const userSkills = skills.filter((s) => s.scope === "user");
  const projectSkills = skills.filter((s) => s.scope === "project");

  async function handleCreate() {
    if (!name.trim()) return;
    setSaving(true);
    try {
      await invoke("create_skill", {
        scope,
        name: name.trim(),
        description: description.trim(),
      });
      setName("");
      setDescription("");
      setCreating(false);
      await refresh();
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(skill: SkillInfo) {
    if (!confirm(`删除技能「${skill.name}」？`)) return;
    try {
      await invoke("delete_skill", { path: skill.path });
      if (editing?.path === skill.path) setEditing(null);
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  async function openEdit(skill: SkillInfo) {
    try {
      const md = await invoke<string>("read_skill_markdown", { path: skill.path });
      setEditing(skill);
      setMarkdown(md);
      setError(null);
    } catch (e) {
      setError(String(e));
    }
  }

  async function saveEdit() {
    if (!editing) return;
    setSaving(true);
    try {
      await invoke("write_skill_markdown", {
        path: editing.path,
        content: markdown,
      });
      setEditing(null);
      await refresh();
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  }

  function renderGroup(title: string, list: SkillInfo[]) {
    return (
      <div className="mcp-preset-group">
        <div className="mcp-preset-label">{title}</div>
        {list.length === 0 && <div className="mcp-empty">暂无</div>}
        {list.map((s) => (
          <div key={`${s.scope}-${s.path}`} className="mcp-preset-row">
            <div className="mcp-preset-main">
              <strong>{s.name}</strong>
              <span>{s.description || s.path}</span>
            </div>
            <button type="button" className="text-btn" onClick={() => void openEdit(s)}>
              编辑
            </button>
            <button type="button" className="linkish" onClick={() => void handleDelete(s)}>
              删除
            </button>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-sheet mcp-modal"
        role="dialog"
        aria-label="Skills"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="modal-head">
          <div>
            <h2>Skills</h2>
            <p>
              Agent 自动读取{" "}
              <code>~/.grok/skills</code>
              {workspace ? " 与项目 .grok/skills" : ""}；新建后开新对话即可生效。
            </p>
          </div>
          <button type="button" className="icon-x" onClick={onClose}>
            ×
          </button>
        </div>

        {error && <p className="hint" style={{ color: "#b42318" }}>{error}</p>}

        {editing ? (
          <div className="mcp-form">
            <div className="sidebar-label">编辑 {editing.name}</div>
            <textarea
              rows={16}
              value={markdown}
              onChange={(e) => setMarkdown(e.target.value)}
              spellCheck={false}
            />
            <div className="modal-foot">
              <button type="button" className="text-btn" onClick={() => setEditing(null)}>
                取消
              </button>
              <button type="button" className="primary-btn" disabled={saving} onClick={() => void saveEdit()}>
                保存
              </button>
            </div>
          </div>
        ) : creating ? (
          <div className="mcp-form">
            <label>
              作用域
              <select
                value={scope}
                onChange={(e) => setScope(e.target.value as "user" | "project")}
              >
                <option value="user">个人（~/.grok/skills）</option>
                <option value="project" disabled={!workspace}>
                  项目（.grok/skills）
                </option>
              </select>
            </label>
            <label>
              名称
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="例如 code-review"
              />
            </label>
            <label>
              简介
              <input
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="何时使用该技能"
              />
            </label>
            <div className="modal-foot">
              <button type="button" className="text-btn" onClick={() => setCreating(false)}>
                取消
              </button>
              <button
                type="button"
                className="primary-btn"
                disabled={saving || !name.trim()}
                onClick={() => void handleCreate()}
              >
                创建
              </button>
            </div>
          </div>
        ) : (
          <>
            <div className="mcp-presets">
              {renderGroup("个人 Skills", userSkills)}
              {renderGroup("项目 Skills", projectSkills)}
            </div>
            <div className="modal-foot">
              <button
                type="button"
                className="text-btn"
                onClick={() => void invoke("open_skills_folder", { scope: "user" })}
              >
                打开个人目录
              </button>
              {workspace ? (
                <button
                  type="button"
                  className="text-btn"
                  onClick={() => void invoke("open_skills_folder", { scope: "project" })}
                >
                  打开项目目录
                </button>
              ) : null}
              <button type="button" className="primary-btn" onClick={() => setCreating(true)}>
                + 新建 Skill
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
