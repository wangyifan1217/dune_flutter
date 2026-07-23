import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AgentStatus, AppSettings, DirectoryTreeNode, ModelEntry } from "../types/agent";
import { normalizeSettings } from "../types/agent";
import type { LeftMode, ThreadSession } from "../types/codex";
import type { MemoryEntry } from "../types/memory";
import { FileTree } from "./FileTree";

interface SidebarProps {
  mode: LeftMode;
  sessions: ThreadSession[];
  activeId: string | null;
  busyBySession: Record<string, boolean>;
  tree: DirectoryTreeNode | null;
  status: AgentStatus;
  settings: AppSettings | null;
  busy: boolean;
  error?: string | null;
  rightOpen: boolean;
  mcpOpen?: boolean;
  skillsOpen?: boolean;
  authUser?: string;
  onMode: (mode: LeftMode) => void;
  onNew: () => void;
  onToggleRight: () => void;
  onOpenMcp: () => void;
  onOpenSkills: () => void;
  onLogout?: () => void;
  onSelectSession: (id: string) => void;
  onRemoveSession: (id: string) => void;
  onOpenFolder: () => void;
  onShowProjectFiles: () => void;
  onOpenFile?: (path: string) => void;
  onReconnect: () => void;
  onDisconnect: () => void;
  onSaveSettings: (s: AppSettings) => Promise<void>;
}

export function Sidebar({
  mode,
  sessions,
  activeId,
  busyBySession,
  tree,
  status,
  settings,
  busy,
  error,
  rightOpen,
  mcpOpen,
  skillsOpen,
  authUser,
  onMode,
  onNew,
  onToggleRight,
  onOpenMcp,
  onOpenSkills,
  onLogout,
  onSelectSession,
  onRemoveSession,
  onOpenFolder,
  onShowProjectFiles,
  onOpenFile,
  onReconnect,
  onDisconnect,
  onSaveSettings,
}: SidebarProps) {
  const [draft, setDraft] = useState<AppSettings>(
    settings ?? normalizeSettings({}),
  );
  const [newModelId, setNewModelId] = useState("");
  const [newModelLabel, setNewModelLabel] = useState("");
  const [memories, setMemories] = useState<MemoryEntry[]>([]);
  const [memoryDraft, setMemoryDraft] = useState("");
  const project =
    status.workspace?.split(/[/\\]/).filter(Boolean).pop() ?? "选择项目";

  useEffect(() => {
    if (settings) setDraft(settings);
  }, [settings]);

  useEffect(() => {
    if (mode !== "memory") return;
    void invoke<MemoryEntry[]>("list_memories")
      .then(setMemories)
      .catch(() => setMemories([]));
  }, [mode]);

  async function refreshMemories() {
    const list = await invoke<MemoryEntry[]>("list_memories");
    setMemories(list);
  }

  async function addMemory() {
    const text = memoryDraft.trim();
    if (!text) return;
    await invoke("add_memory", { content: text, source: "user" });
    setMemoryDraft("");
    await refreshMemories();
  }

  async function removeMemory(id: string) {
    await invoke("delete_memory", { id });
    await refreshMemories();
  }

  async function clearAllMemories() {
    if (!confirm("确定清空全部永久记忆？")) return;
    await invoke("clear_memories");
    await refreshMemories();
  }

  function saveDraft(patch: Partial<AppSettings>) {
    const next = { ...draft, ...patch };
    setDraft(next);
    void onSaveSettings(next);
  }

  function addModel(entry: ModelEntry) {
    const id = entry.id.trim();
    if (!id) return;
    if (draft.models.some((m) => m.id === id)) return;
    const models = [
      ...draft.models,
      { id, label: entry.label.trim() || id },
    ];
    const modelId = draft.modelId || id;
    saveDraft({ models, modelId });
    setNewModelId("");
    setNewModelLabel("");
  }

  function removeModel(id: string) {
    const models = draft.models.filter((m) => m.id !== id);
    const modelId =
      draft.modelId === id ? models[0]?.id ?? "" : draft.modelId;
    saveDraft({ models, modelId });
  }

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <img className="brand-mark" src="/nova-build-logo.png" alt="Nova Build" />
        <span className="brand-name">Nova Build 桌面版</span>
      </div>

      <nav className="sidebar-nav">
        <button type="button" className="nav-item" onClick={onNew}>
          <span className="nav-ico">✎</span>
          新任务
        </button>
        <button
          type="button"
          className={`nav-item ${mode === "threads" ? "active" : ""}`}
          onClick={() => onMode("threads")}
        >
          <span className="nav-ico">◉</span>
          对话
        </button>
        <button
          type="button"
          className={`nav-item ${mode === "memory" ? "active" : ""}`}
          onClick={() => onMode("memory")}
        >
          <span className="nav-ico">✦</span>
          记忆
        </button>
        <button
          type="button"
          className={`nav-item ${mcpOpen ? "active" : ""}`}
          onClick={onOpenMcp}
        >
          <span className="nav-ico">◇</span>
          MCP
        </button>
        <button
          type="button"
          className={`nav-item ${skillsOpen ? "active" : ""}`}
          onClick={onOpenSkills}
        >
          <span className="nav-ico">◎</span>
          Skills
        </button>
        <button
          type="button"
          className={`nav-item ${rightOpen ? "active" : ""}`}
          onClick={onToggleRight}
        >
          <span className="nav-ico">▥</span>
          审阅
        </button>
        <button
          type="button"
          className={`nav-item ${mode === "settings" ? "active" : ""}`}
          onClick={() => onMode("settings")}
        >
          <span className="nav-ico">⚙</span>
          设置
        </button>
      </nav>

      <div className="sidebar-main">
        {mode === "threads" && (
          <>
            <div className="sidebar-label">对话</div>
            <div className="thread-list">
              {sessions.length === 0 && (
                <div className="empty-hint">还没有对话</div>
              )}
              {sessions.map((s) => {
                const lastMessage = s.messages[s.messages.length - 1];
                const state = busyBySession[s.id]
                  ? "running"
                  : lastMessage?.role === "system" && lastMessage.status === "error"
                    ? "error"
                    : lastMessage?.role === "assistant" && lastMessage.status === "completed"
                      ? "completed"
                      : null;
                return (
                  <button
                    key={s.id}
                    type="button"
                    className={`thread-item ${s.id === activeId ? "active" : ""}`}
                    onClick={() => onSelectSession(s.id)}
                  >
                    <span className="thread-item-title">{s.title}</span>
                    {state ? (
                      <span className={`thread-status ${state}`}>
                        {state === "running" ? "分析中" : state === "completed" ? "已完成" : "失败"}
                      </span>
                    ) : null}
                    <span
                      className="thread-item-x"
                      onClick={(e) => {
                        e.stopPropagation();
                        onRemoveSession(s.id);
                      }}
                    >
                      ×
                    </span>
                  </button>
                );
              })}
            </div>
          </>
        )}

        {mode === "files" && (
          <>
            <div className="sidebar-label-row">
              <div className="sidebar-label">文件</div>
              <button type="button" className="text-btn" disabled={busy} onClick={onOpenFolder}>
                打开
              </button>
            </div>
            <div className="files-scroll">
              <FileTree tree={tree} onOpenFile={onOpenFile} />
            </div>
          </>
        )}

        {mode === "memory" && (
          <div className="settings-scroll">
            <div className="sidebar-label">永久记忆</div>
            <p className="hint">
              写入磁盘，重启仍在。每次对话会自动带上这些内容。也可在聊天里发「记住：xxx」。
            </p>
            <label>
              新增一条
              <textarea
                rows={3}
                value={memoryDraft}
                placeholder="例如：我偏好 TypeScript + Tauri；项目用 new-api"
                onChange={(e) => setMemoryDraft(e.target.value)}
              />
            </label>
            <button
              type="button"
              className="text-btn block"
              disabled={!memoryDraft.trim()}
              onClick={() => void addMemory()}
            >
              + 保存记忆
            </button>
            <div className="sidebar-label-row spaced">
              <div className="sidebar-label">已保存 {memories.length}</div>
              <button type="button" className="linkish" onClick={() => void clearAllMemories()}>
                清空
              </button>
            </div>
            <div className="memory-list">
              {memories.length === 0 && (
                <div className="empty-hint">还没有记忆</div>
              )}
              {memories.map((m) => (
                <div key={m.id} className="memory-row">
                  <p>{m.content}</p>
                  <button
                    type="button"
                    className="linkish"
                    onClick={() => void removeMemory(m.id)}
                  >
                    删除
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {mode === "settings" && (
          <div className="settings-scroll">
            <div className="sidebar-label">new-api（共用）</div>
            <p className="hint">一把 Key + Base URL，下面可加多个模型。</p>
            <label>
              Base URL
              <input
                value={draft.apiBaseUrl}
                placeholder="https://your-newapi.com/v1"
                onChange={(e) => setDraft({ ...draft, apiBaseUrl: e.target.value })}
                onBlur={() => saveDraft({ apiBaseUrl: draft.apiBaseUrl.trim() })}
              />
            </label>
            <label>
              API Key
              <input
                type="password"
                value={draft.apiKey}
                placeholder="sk-..."
                onChange={(e) => setDraft({ ...draft, apiKey: e.target.value })}
                onBlur={() => saveDraft({ apiKey: draft.apiKey.trim() })}
              />
            </label>

            <div className="sidebar-label spaced">模型列表</div>
            <p className="hint">
              在下方填写网关里的模型 ID 并添加（须与 new-api 完全一致，注意大小写；保存时会自动对齐）。
              点列表项设为当前模型；会话框只能切换这里已添加的模型。
            </p>
            <div className="settings-model-list">
              {draft.models.length === 0 && (
                <div className="empty-hint">还没有模型，请在下方添加</div>
              )}
              {draft.models.map((m) => (
                <div
                  key={m.id}
                  className={`settings-model-row ${draft.modelId === m.id ? "is-current" : ""}`}
                >
                  <button
                    type="button"
                    className={`settings-model-main ${draft.modelId === m.id ? "active" : ""}`}
                    onClick={() => saveDraft({ modelId: m.id })}
                    title="设为当前模型"
                  >
                    <strong>{m.label || m.id}</strong>
                    <span className="settings-model-id">{m.id}</span>
                    {draft.modelId === m.id ? (
                      <em className="settings-model-badge">当前</em>
                    ) : null}
                  </button>
                  <button
                    type="button"
                    className="linkish"
                    onClick={() => removeModel(m.id)}
                  >
                    删除
                  </button>
                </div>
              ))}
            </div>

            <div className="add-model-box">
              <div className="sidebar-label">添加模型</div>
              <label>
                模型 ID（与网关一致）
                <input
                  value={newModelId}
                  placeholder="例如 gpt-5.6-sol"
                  onChange={(e) => setNewModelId(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      addModel({ id: newModelId, label: newModelLabel });
                    }
                  }}
                />
              </label>
              <label>
                显示名（可选）
                <input
                  value={newModelLabel}
                  placeholder="例如 GPT-5.6"
                  onChange={(e) => setNewModelLabel(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      addModel({ id: newModelId, label: newModelLabel });
                    }
                  }}
                />
              </label>
              <button
                type="button"
                className="text-btn block"
                disabled={!newModelId.trim()}
                onClick={() => addModel({ id: newModelId, label: newModelLabel })}
              >
                + 添加模型
              </button>
            </div>

            <div className="sidebar-label spaced">Agent</div>
            <label>
              命令
              <input
                value={draft.grokCommand}
                placeholder="Agent CLI 或完整路径"
                onChange={(e) => setDraft({ ...draft, grokCommand: e.target.value })}
                onBlur={() => saveDraft({ grokCommand: draft.grokCommand.trim() })}
              />
            </label>
            <p className="hint spaced">改完网关或模型后点底部「重连」。</p>
          </div>
        )}
      </div>

      {error && <div className="error-box">{error}</div>}

      {authUser ? <div className="login-user" title={authUser}>{authUser}</div> : null}

      <div className="sidebar-foot">
        <button
          type="button"
          className="project-chip"
          onClick={() => {
            if (status.workspace) onShowProjectFiles();
            else onOpenFolder();
          }}
          title={status.workspace ? "查看项目文件" : "打开项目"}
        >
          <span className="nav-ico">📁</span>
          <span className="project-name">{project}</span>
        </button>
        <div className="foot-actions">
          {onLogout ? (
            <button type="button" className="text-btn" onClick={onLogout}>
              退出
            </button>
          ) : null}
          <button
            type="button"
            className="text-btn"
            disabled={!status.workspace || busy}
            onClick={onReconnect}
          >
            重连
          </button>
          <span
            className={`conn-dot ${status.connected ? "on" : ""}`}
            title={status.connected ? "已连接" : "未连接"}
          />
          <button
            type="button"
            className="text-btn"
            disabled={!status.connected || busy}
            onClick={onDisconnect}
          >
            断
          </button>
        </div>
      </div>
    </aside>
  );
}
