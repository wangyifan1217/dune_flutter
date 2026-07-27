import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { ConfirmDialog } from "./ConfirmDialog";
import { IconX } from "./Icons";

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
  /** 打开时直接进入新建表单 */
  initialCreate?: boolean;
  onClose: () => void;
}

export function SkillsModal({
  open,
  workspace,
  initialCreate = false,
  onClose,
}: SkillsModalProps) {
  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [scope, setScope] = useState<"user" | "project">("user");
  const [editing, setEditing] = useState<SkillInfo | null>(null);
  const [markdown, setMarkdown] = useState("");
  const [saving, setSaving] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<SkillInfo | null>(null);

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
    setEditing(null);
    setPendingDelete(null);
    setName("");
    setDescription("");
    setScope("user");
    setCreating(initialCreate);
    void refresh();
  }, [open, refresh, workspace, initialCreate]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      e.preventDefault();
      e.stopPropagation();
      if (pendingDelete) {
        setPendingDelete(null);
        return;
      }
      // Escape does not close the modal — only 关闭 / 完成
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [open, pendingDelete]);

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

  async function confirmDelete() {
    const skill = pendingDelete;
    if (!skill) return;
    try {
      await invoke("delete_skill", { path: skill.path });
      if (editing?.path === skill.path) setEditing(null);
      setPendingDelete(null);
      await refresh();
    } catch (e) {
      setError(String(e));
      setPendingDelete(null);
    }
  }

  async function openEdit(skill: SkillInfo) {
    try {
      const md = await invoke<string>("read_skill_markdown", { path: skill.path });
      setEditing(skill);
      setMarkdown(md);
      setCreating(false);
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
            <button
              type="button"
              className="linkish"
              onClick={() => setPendingDelete(s)}
            >
              删除
            </button>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div
      className="modal-backdrop nested-modal"
      role="presentation"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) e.preventDefault();
      }}
    >
      <div
        className="modal-sheet mcp-modal skills-modal"
        role="dialog"
        aria-modal="true"
        aria-label="技能"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="modal-head">
          <div>
            <h2>
              {editing
                ? `编辑技能 · ${editing.name}`
                : creating
                  ? "新建技能"
                  : "技能"}
            </h2>
            <p>
              Agent 会自动读取{" "}
              <code>~/.grok/skills</code>
              {workspace ? " 与项目 .grok/skills" : ""}；新建后开新对话即可生效。
            </p>
          </div>
          <button type="button" className="icon-x" onClick={onClose} aria-label="关闭">
            <IconX size={16} />
          </button>
        </div>

        {error && (
          <p className="hint" style={{ color: "#b42318" }}>
            {error}
          </p>
        )}

        {editing ? (
          <div className="mcp-form">
            <label>
              SKILL.md 内容
              <textarea
                rows={16}
                value={markdown}
                onChange={(e) => setMarkdown(e.target.value)}
                spellCheck={false}
              />
            </label>
            <div className="modal-foot">
              <button type="button" className="text-btn" onClick={() => setEditing(null)}>
                返回列表
              </button>
              <button
                type="button"
                className="primary-btn"
                disabled={saving}
                onClick={() => void saveEdit()}
              >
                {saving ? "保存中…" : "保存"}
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
                  项目（.grok/skills）{!workspace ? " — 请先打开项目" : ""}
                </option>
              </select>
            </label>
            <label>
              名称
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="例如 code-review"
                autoFocus
                onKeyDown={(e) => {
                  if (e.key === "Enter" && name.trim()) void handleCreate();
                }}
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
              <button
                type="button"
                className="text-btn"
                onClick={() => {
                  setCreating(false);
                  setName("");
                  setDescription("");
                }}
              >
                返回列表
              </button>
              <button
                type="button"
                className="primary-btn"
                disabled={saving || !name.trim()}
                onClick={() => void handleCreate()}
              >
                {saving ? "创建中…" : "创建技能"}
              </button>
            </div>
          </div>
        ) : (
          <>
            <div className="mcp-presets">
              {renderGroup("个人技能", userSkills)}
              {renderGroup("项目技能", projectSkills)}
            </div>
            <div className="modal-foot split">
              <div className="modal-foot-left">
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
                    onClick={() =>
                      void invoke("open_skills_folder", { scope: "project" })
                    }
                  >
                    打开项目目录
                  </button>
                ) : null}
              </div>
              <button
                type="button"
                className="primary-btn"
                onClick={() => setCreating(true)}
              >
                + 新建技能
              </button>
            </div>
          </>
        )}
      </div>

      <ConfirmDialog
        open={pendingDelete != null}
        title="删除技能？"
        message={
          pendingDelete
            ? `确定删除技能「${pendingDelete.name}」？此操作不可撤销。`
            : "确定删除该技能？"
        }
        confirmLabel="删除"
        danger
        onCancel={() => setPendingDelete(null)}
        onConfirm={() => void confirmDelete()}
      />
    </div>
  );
}
