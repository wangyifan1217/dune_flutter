import { useEffect, useState } from "react";
import type { McpEnvVar, McpServerConfig } from "../types/agent";

interface McpSettingsModalProps {
  open: boolean;
  servers: McpServerConfig[];
  onClose: () => void;
  onSave: (servers: McpServerConfig[]) => void;
}

type Transport = "stdio" | "http";

interface DraftServer {
  name: string;
  transport: Transport;
  command: string;
  argsText: string;
  url: string;
  envText: string;
}

const emptyDraft = (): DraftServer => ({
  name: "",
  transport: "stdio",
  command: "npx",
  argsText: "-y @modelcontextprotocol/server-filesystem",
  url: "https://",
  envText: "",
});

function parseEnv(text: string): McpEnvVar[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const i = line.indexOf("=");
      if (i <= 0) return { name: line, value: "" };
      return { name: line.slice(0, i).trim(), value: line.slice(i + 1).trim() };
    })
    .filter((e) => e.name);
}

function envToText(env?: McpEnvVar[]): string {
  return (env ?? []).map((e) => `${e.name}=${e.value}`).join("\n");
}

function toConfig(d: DraftServer): McpServerConfig | null {
  const name = d.name.trim();
  if (!name) return null;
  if (d.transport === "http") {
    const url = d.url.trim();
    if (!url) return null;
    // Agent 侧当前以 command 承载；HTTP 先记到 command，args 标记类型
    return {
      name,
      command: url,
      args: ["__transport=http"],
      env: parseEnv(d.envText),
    };
  }
  const command = d.command.trim();
  if (!command) return null;
  return {
    name,
    command,
    args: d.argsText.split(/\s+/).filter(Boolean),
    env: parseEnv(d.envText),
  };
}

function fromConfig(s: McpServerConfig): DraftServer {
  const isHttp = (s.args ?? []).includes("__transport=http");
  return {
    name: s.name,
    transport: isHttp ? "http" : "stdio",
    command: isHttp ? "npx" : s.command,
    argsText: isHttp ? "" : (s.args ?? []).join(" "),
    url: isHttp ? s.command : "https://",
    envText: envToText(s.env),
  };
}

function summarize(s: McpServerConfig): string {
  if ((s.args ?? []).includes("__transport=http")) return s.command;
  const args = (s.args ?? []).join(" ");
  return args ? `${s.command} ${args}` : s.command;
}

export function McpSettingsModal({
  open,
  servers,
  onClose,
  onSave,
}: McpSettingsModalProps) {
  const [list, setList] = useState<McpServerConfig[]>(servers);
  const [adding, setAdding] = useState(false);
  const [editIndex, setEditIndex] = useState<number | null>(null);
  const [draft, setDraft] = useState<DraftServer>(emptyDraft());

  useEffect(() => {
    if (open) {
      setList(servers);
      setAdding(false);
      setEditIndex(null);
      setDraft(emptyDraft());
    }
  }, [open, servers]);

  if (!open) return null;

  function openAdd() {
    setEditIndex(null);
    setDraft(emptyDraft());
    setAdding(true);
  }

  function openEdit(index: number) {
    setEditIndex(index);
    setDraft(fromConfig(list[index]));
    setAdding(true);
  }

  function commitForm() {
    const cfg = toConfig(draft);
    if (!cfg) return;
    const next =
      editIndex === null
        ? [...list, cfg]
        : list.map((s, i) => (i === editIndex ? cfg : s));
    setList(next);
    setAdding(false);
    setEditIndex(null);
    onSave(next);
  }

  function removeAt(index: number) {
    const next = list.filter((_, i) => i !== index);
    setList(next);
    onSave(next);
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-sheet mcp-modal"
        role="dialog"
        aria-label="MCP 服务器"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="modal-head">
          <div>
            <h2>MCP 服务器</h2>
            <p>连接本地或远程工具。保存后请重连 Agent。</p>
          </div>
          <button type="button" className="icon-x" onClick={onClose}>
            ×
          </button>
        </div>

        {!adding ? (
          <>
            <div className="mcp-list">
              {list.length === 0 && (
                <div className="mcp-empty">还没有 MCP 服务器</div>
              )}
              {list.map((s, index) => (
                <div key={`${s.name}-${index}`} className="mcp-row">
                  <div className="mcp-row-main">
                    <strong>{s.name}</strong>
                    <span className="mcp-row-sub">{summarize(s)}</span>
                  </div>
                  <div className="mcp-row-actions">
                    <button type="button" className="text-btn" onClick={() => openEdit(index)}>
                      编辑
                    </button>
                    <button type="button" className="linkish" onClick={() => removeAt(index)}>
                      删除
                    </button>
                  </div>
                </div>
              ))}
            </div>
            <div className="modal-foot">
              <button type="button" className="primary-btn" onClick={openAdd}>
                + 添加服务器
              </button>
            </div>
          </>
        ) : (
          <div className="mcp-form">
            <label>
              名称
              <input
                value={draft.name}
                placeholder="filesystem"
                onChange={(e) => setDraft({ ...draft, name: e.target.value })}
              />
            </label>

            <div className="transport-tabs">
              <button
                type="button"
                className={draft.transport === "stdio" ? "active" : ""}
                onClick={() => setDraft({ ...draft, transport: "stdio" })}
              >
                stdio
              </button>
              <button
                type="button"
                className={draft.transport === "http" ? "active" : ""}
                onClick={() => setDraft({ ...draft, transport: "http" })}
              >
                Streamable HTTP
              </button>
            </div>

            {draft.transport === "stdio" ? (
              <>
                <label>
                  命令
                  <input
                    value={draft.command}
                    placeholder="npx"
                    onChange={(e) => setDraft({ ...draft, command: e.target.value })}
                  />
                </label>
                <label>
                  参数（空格分隔）
                  <input
                    value={draft.argsText}
                    placeholder="-y @modelcontextprotocol/server-filesystem D:/path"
                    onChange={(e) => setDraft({ ...draft, argsText: e.target.value })}
                  />
                </label>
              </>
            ) : (
              <label>
                URL
                <input
                  value={draft.url}
                  placeholder="https://example.com/mcp"
                  onChange={(e) => setDraft({ ...draft, url: e.target.value })}
                />
              </label>
            )}

            <label>
              环境变量（每行 KEY=VALUE，可选）
              <textarea
                rows={3}
                value={draft.envText}
                placeholder={"API_KEY=sk-...\nDEBUG=1"}
                onChange={(e) => setDraft({ ...draft, envText: e.target.value })}
              />
            </label>

            <div className="modal-foot split">
              <button
                type="button"
                className="text-btn"
                onClick={() => {
                  setAdding(false);
                  setEditIndex(null);
                }}
              >
                取消
              </button>
              <button
                type="button"
                className="primary-btn"
                disabled={!toConfig(draft)}
                onClick={commitForm}
              >
                保存
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
