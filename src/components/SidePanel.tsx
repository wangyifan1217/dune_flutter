import { useEffect, useState } from "react";
import type { AgentStatus, AppSettings, DirectoryTreeNode, McpServerConfig } from "../types/agent";
import type { ThreadSession } from "../types/codex";
import { FileTree } from "./FileTree";

interface SidePanelProps {
  mode: "threads" | "files" | "settings";
  sessions: ThreadSession[];
  activeId: string | null;
  tree: DirectoryTreeNode | null;
  status: AgentStatus;
  settings: AppSettings | null;
  busy: boolean;
  error?: string | null;
  onSelectSession: (id: string) => void;
  onRemoveSession: (id: string) => void;
  onOpenFolder: () => void;
  onReconnect: () => void;
  onDisconnect: () => void;
  onSaveSettings: (s: AppSettings) => Promise<void>;
}

const defaults = (): AppSettings => ({
  grokCommand: "grok",
  grokArgs: ["agent", "stdio"],
  autoApprovePermissions: true,
  apiBaseUrl: "",
  apiKey: "",
  modelId: "",
  models: [],
  mcpServers: [],
});

const MODEL_PRESETS: { id: string; label: string }[] = [];


function emptyMcp(): McpServerConfig {
  return { name: "", command: "npx", args: ["-y"], env: [] };
}

export function SidePanel({
  mode,
  sessions,
  activeId,
  tree,
  status,
  settings,
  busy,
  error,
  onSelectSession,
  onRemoveSession,
  onOpenFolder,
  onReconnect,
  onDisconnect,
  onSaveSettings,
}: SidePanelProps) {
  const current = { ...defaults(), ...(settings ?? {}) };
  const [draft, setDraft] = useState<AppSettings>(current);
  const [mcpDraft, setMcpDraft] = useState<McpServerConfig[]>(current.mcpServers ?? []);
  const project =
    status.workspace?.split(/[/\\]/).filter(Boolean).pop() ?? "选择项目";

  useEffect(() => {
    const next = { ...defaults(), ...(settings ?? {}) };
    setDraft(next);
    setMcpDraft(next.mcpServers ?? []);
  }, [settings]);

  function saveDraft(patch: Partial<AppSettings>) {
    const next = { ...draft, ...patch, mcpServers: mcpDraft };
    setDraft(next);
    void onSaveSettings(next);
  }

  function saveMcp(list: McpServerConfig[]) {
    setMcpDraft(list);
    void onSaveSettings({ ...draft, mcpServers: list });
  }

  return (
    <aside className="side-panel">
      {mode === "threads" && (
        <>
          <div className="side-head">
            <div>
              <div className="side-kicker">项目</div>
              <div className="side-title" title={status.workspace ?? ""}>
                {project}
              </div>
            </div>
            <button type="button" className="pill" disabled={busy} onClick={onOpenFolder}>
              打开
            </button>
          </div>
          <div className={`status-line ${status.connected ? "on" : "off"}`}>
            <span className="dot" />
            {status.connected ? "Agent 已连接" : "Agent 未连接"}
          </div>
          {error && <div className="error-box">{error}</div>}
          <div className="side-actions">
            <button type="button" disabled={!status.workspace || busy} onClick={onReconnect}>
              重连
            </button>
            <button type="button" disabled={!status.connected || busy} onClick={onDisconnect}>
              断开
            </button>
          </div>
          <div className="side-kicker spaced">对话</div>
          <div className="thread-list">
            {sessions.length === 0 && (
              <div className="empty-hint">还没有对话，点左侧 + 开始</div>
            )}
            {sessions.map((s) => (
              <button
                key={s.id}
                type="button"
                className={`thread-item ${s.id === activeId ? "active" : ""}`}
                onClick={() => onSelectSession(s.id)}
              >
                <span className="thread-item-title">{s.title}</span>
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
            ))}
          </div>
        </>
      )}

      {mode === "files" && (
        <>
          <div className="side-head">
            <div>
              <div className="side-kicker">文件</div>
              <div className="side-title">{project}</div>
            </div>
            <button type="button" className="pill" disabled={busy} onClick={onOpenFolder}>
              打开
            </button>
          </div>
          <div className="files-scroll">
            <FileTree tree={tree} />
          </div>
        </>
      )}

      {mode === "settings" && (
        <div className="settings-scroll">
          <div className="side-kicker">模型</div>
          <div className="model-grid">
            {MODEL_PRESETS.map((m) => (
              <button
                key={m.id}
                type="button"
                className={`model-chip ${draft.modelId === m.id ? "active" : ""}`}
                onClick={() => saveDraft({ modelId: m.id })}
              >
                {m.label}
              </button>
            ))}
          </div>
          <label>
            自定义模型 ID
            <input
              value={draft.modelId}
              placeholder="例如 gpt-4o / claude-sonnet-4"
              onChange={(e) => setDraft({ ...draft, modelId: e.target.value })}
              onBlur={() => saveDraft({ modelId: draft.modelId.trim() })}
            />
          </label>

          <div className="side-kicker spaced">API / new-api</div>
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

          <div className="side-kicker spaced">MCP 服务器</div>
          <p className="hint">像 Codex 一样添加 MCP；改完后点「重连」。</p>
          {mcpDraft.map((server, index) => (
            <div key={index} className="mcp-card">
              <div className="mcp-card-head">
                <strong>{server.name || `服务器 ${index + 1}`}</strong>
                <button
                  type="button"
                  className="linkish"
                  onClick={() => {
                    const next = mcpDraft.filter((_, i) => i !== index);
                    saveMcp(next);
                  }}
                >
                  删除
                </button>
              </div>
              <label>
                名称
                <input
                  value={server.name}
                  placeholder="filesystem"
                  onChange={(e) => {
                    const next = [...mcpDraft];
                    next[index] = { ...server, name: e.target.value };
                    setMcpDraft(next);
                  }}
                  onBlur={() => saveMcp(mcpDraft)}
                />
              </label>
              <label>
                命令
                <input
                  value={server.command}
                  placeholder="npx"
                  onChange={(e) => {
                    const next = [...mcpDraft];
                    next[index] = { ...server, command: e.target.value };
                    setMcpDraft(next);
                  }}
                  onBlur={() => saveMcp(mcpDraft)}
                />
              </label>
              <label>
                参数（空格分隔）
                <input
                  value={(server.args ?? []).join(" ")}
                  placeholder="-y @modelcontextprotocol/server-filesystem D:/path"
                  onChange={(e) => {
                    const next = [...mcpDraft];
                    next[index] = {
                      ...server,
                      args: e.target.value.split(/\s+/).filter(Boolean),
                    };
                    setMcpDraft(next);
                  }}
                  onBlur={() => saveMcp(mcpDraft)}
                />
              </label>
            </div>
          ))}
          <button
            type="button"
            className="pill block"
            onClick={() => saveMcp([...mcpDraft, emptyMcp()])}
          >
            + 添加 MCP
          </button>

          <p className="hint spaced">保存后请点左侧「重连」让模型与 MCP 生效。</p>
        </div>
      )}
    </aside>
  );
}
