import { useEffect, useRef, useState, type ComponentType } from "react";
import { invoke } from "@tauri-apps/api/core";
import type {
  AgentStatus,
  AppSettings,
  McpServerConfig,
  ModelEntry,
} from "../types/agent";
import { normalizeSettings } from "../types/agent";
import {
  MCP_PRESETS,
  mergeRecommendedMcpServers,
  presetAlreadyAdded,
  type McpPreset,
} from "../constants/mcpPresets";
import { ConfirmDialog } from "./ConfirmDialog";
import {
  IconAgent,
  IconChevronLeft,
  IconCube,
  IconGeneral,
  IconList,
  IconMemory,
  IconPlus,
  IconSparkles,
  IconX,
} from "./Icons";
import type { SkillInfo } from "./SkillsModal";

export type SettingsTab =
  | "general"
  | "models"
  | "mcp"
  | "skills"
  | "memory"
  | "agent"
  | "shortcuts";

interface SettingsModalProps {
  open: boolean;
  settings: AppSettings | null;
  status: AgentStatus;
  busy: boolean;
  workspace?: string | null;
  initialTab?: SettingsTab;
  /** Bump when Skills modal closes so the list refreshes */
  skillsRefreshKey?: number;
  onClose: () => void;
  onSave: (s: AppSettings) => Promise<void>;
  onOpenSkills: (create?: boolean) => void;
  onOpenMemory: () => void;
  onOpenFolder: () => void;
  onReconnect: () => void;
  onDisconnect: () => void;
}

type NavIcon = ComponentType<{ size?: number }>;

const NAV: Array<{ id: SettingsTab; label: string; Icon: NavIcon }> = [
  { id: "general", label: "通用", Icon: IconGeneral },
  { id: "models", label: "模型", Icon: IconCube },
  { id: "mcp", label: "工具与 MCP", Icon: IconSparkles },
  { id: "skills", label: "Skills", Icon: IconList },
  { id: "memory", label: "记忆", Icon: IconMemory },
  { id: "agent", label: "Agent", Icon: IconAgent },
  { id: "shortcuts", label: "快捷键", Icon: IconList },
];

function summarizeMcp(s: McpServerConfig): string {
  if ((s.args ?? []).includes("__transport=http")) return s.command;
  const args = (s.args ?? []).join(" ");
  return args ? `${s.command} ${args}` : s.command;
}

function initialLetter(name: string) {
  return (name.trim()[0] || "M").toUpperCase();
}

export function SettingsModal({
  open,
  settings,
  status,
  busy,
  workspace,
  initialTab = "general",
  skillsRefreshKey = 0,
  onClose,
  onSave,
  onOpenSkills,
  onOpenMemory,
  onOpenFolder,
  onReconnect,
  onDisconnect,
}: SettingsModalProps) {
  const [tab, setTab] = useState<SettingsTab>(initialTab);
  const [draft, setDraft] = useState<AppSettings>(settings ?? normalizeSettings({}));
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [gatewayCatalog, setGatewayCatalog] = useState<ModelEntry[] | null>(null);
  const [fetchingModels, setFetchingModels] = useState(false);
  const [fetchModelsHint, setFetchModelsHint] = useState<string | null>(null);
  const [mcpAdding, setMcpAdding] = useState(false);
  const [mcpName, setMcpName] = useState("");
  const [mcpCommand, setMcpCommand] = useState("npx");
  const [mcpArgs, setMcpArgs] = useState("");
  const [pendingRemoveMcpName, setPendingRemoveMcpName] = useState<string | null>(
    null,
  );
  const [pendingRemoveModel, setPendingRemoveModel] = useState<string | null>(null);
  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [skillsLoading, setSkillsLoading] = useState(false);
  const [skillsError, setSkillsError] = useState<string | null>(null);

  const draftRef = useRef(draft);
  draftRef.current = draft;
  const saveChainRef = useRef(Promise.resolve());
  const wasOpenRef = useRef(false);

  // Reset form only when modal opens; sync tab if parent asks for another section
  useEffect(() => {
    if (!open) {
      wasOpenRef.current = false;
      return;
    }

    const justOpened = !wasOpenRef.current;
    wasOpenRef.current = true;
    if (!justOpened) return;

    setTab(initialTab);
    setDraft(settings ?? normalizeSettings({}));
    setMcpAdding(false);
    setMcpName("");
    setMcpCommand("npx");
    setMcpArgs("");
    setGatewayCatalog(null);
    setFetchingModels(false);
    setFetchModelsHint(null);
    setSaveError(null);
    setPendingRemoveMcpName(null);
    setPendingRemoveModel(null);
    setSaving(false);
    // Capture settings/initialTab only at open time
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  useEffect(() => {
    if (!open) return;
    // Parent asked to jump to a section while settings is already open
    setTab(initialTab);
  }, [initialTab]); // eslint-disable-line react-hooks/exhaustive-deps -- only follow explicit tab requests

  useEffect(() => {
    if (!open || tab !== "skills") return;
    let cancelled = false;
    setSkillsLoading(true);
    setSkillsError(null);
    void invoke<SkillInfo[]>("list_skills")
      .then((list) => {
        if (!cancelled) setSkills(list);
      })
      .catch((e) => {
        if (!cancelled) {
          setSkills([]);
          setSkillsError(String(e));
        }
      })
      .finally(() => {
        if (!cancelled) setSkillsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [open, tab, workspace, skillsRefreshKey]);

  // 进入「模型」页自动拉网关列表，避免一直停在旧的手动启用列表
  useEffect(() => {
    if (!open || tab !== "models") return;
    if (gatewayCatalog || fetchingModels) return;
    if (!draftRef.current.apiBaseUrl.trim()) return;
    void fetchGatewayModels();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 仅在切换到模型页时自动拉一次
  }, [open, tab]);

  // Only explicit 关闭 — Escape / backdrop must not dismiss
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      if (pendingRemoveMcpName != null || pendingRemoveModel != null) {
        e.preventDefault();
        e.stopPropagation();
        setPendingRemoveMcpName(null);
        setPendingRemoveModel(null);
        return;
      }
      e.preventDefault();
      e.stopPropagation();
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [open, pendingRemoveMcpName, pendingRemoveModel]);

  if (!open) return null;

  async function saveDraft(patch: Partial<AppSettings>) {
    const next = normalizeSettings({ ...draftRef.current, ...patch });
    draftRef.current = next;
    setDraft(next);
    setSaving(true);
    setSaveError(null);

    const task = saveChainRef.current.then(async () => {
      await onSave(next);
    });
    saveChainRef.current = task.catch(() => undefined);

    try {
      await task;
    } catch (error) {
      setSaveError(String(error));
      if (settings) {
        draftRef.current = settings;
        setDraft(settings);
      }
    } finally {
      setSaving(false);
    }
  }

  function setModelEnabled(entry: ModelEntry, enabled: boolean) {
    const id = entry.id.trim();
    if (!id) return;
    const current = draftRef.current.models;
    if (enabled) {
      if (current.some((m) => m.id === id)) return;
      const models = [...current, { id, label: entry.label.trim() || id }];
      const modelId = draftRef.current.modelId || id;
      void saveDraft({ models, modelId });
      return;
    }
    const models = current.filter((m) => m.id !== id);
    const modelId =
      draftRef.current.modelId === id ? models[0]?.id ?? "" : draftRef.current.modelId;
    void saveDraft({ models, modelId });
    setPendingRemoveModel(null);
  }

  function removeModel(id: string) {
    setModelEnabled({ id, label: id }, false);
  }

  async function fetchGatewayModels() {
    const apiBaseUrl = draftRef.current.apiBaseUrl.trim();
    const apiKey = draftRef.current.apiKey.trim();
    if (!apiBaseUrl) {
      setSaveError("请先填写 Base URL");
      return;
    }
    if (fetchingModels) return;

    // 先落盘网关配置，再拉取，避免只改了输入框未 blur
    if (
      apiBaseUrl !== (settings?.apiBaseUrl ?? "") ||
      apiKey !== (settings?.apiKey ?? "")
    ) {
      try {
        await saveDraft({ apiBaseUrl, apiKey });
      } catch {
        return;
      }
    }
    setFetchingModels(true);
    setSaveError(null);
    setFetchModelsHint("正在从网关刷新…");
    try {
      const list = await invoke<ModelEntry[]>("list_gateway_models", {
        apiBaseUrl,
        apiKey,
      });
      // 新数组引用，确保界面有刷新感
      setGatewayCatalog(list.map((m) => ({ ...m })));

      // 丢掉网关上已不存在的「旧模型」；勾选状态只保留仍在列表里的
      const catalogById = new Map(list.map((m) => [m.id, m]));
      const kept = draftRef.current.models
        .map((m) => catalogById.get(m.id))
        .filter((m): m is ModelEntry => Boolean(m))
        .map((m) => ({ id: m.id, label: m.label || m.id }));
      const modelId =
        kept.some((m) => m.id === draftRef.current.modelId)
          ? draftRef.current.modelId
          : kept[0]?.id ?? "";
      if (
        kept.length !== draftRef.current.models.length ||
        modelId !== draftRef.current.modelId ||
        kept.some((m, i) => m.id !== draftRef.current.models[i]?.id)
      ) {
        await saveDraft({ models: kept, modelId });
      }
      const time = new Date().toLocaleTimeString("zh-CN", {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });
      setFetchModelsHint(`已刷新 · 共 ${list.length} 个模型 · ${time}`);
    } catch (error) {
      setGatewayCatalog(null);
      setFetchModelsHint(null);
      setSaveError(String(error));
    } finally {
      setFetchingModels(false);
    }
  }

  function addPreset(preset: McpPreset) {
    if (presetAlreadyAdded(draftRef.current.mcpServers, preset)) return;
    void saveDraft({
      mcpServers: [...draftRef.current.mcpServers, preset.build(workspace)],
    });
  }

  function enableRecommendedSuite() {
    void saveDraft({
      mcpServers: mergeRecommendedMcpServers(
        draftRef.current.mcpServers,
        workspace,
      ),
    });
  }

  function removeMcpByName(name: string) {
    void saveDraft({
      mcpServers: draftRef.current.mcpServers.filter((s) => s.name !== name),
    });
    setPendingRemoveMcpName(null);
  }

  function commitCustomMcp() {
    const name = mcpName.trim();
    const command = mcpCommand.trim();
    if (!name || !command) return;
    if (draftRef.current.mcpServers.some((s) => s.name === name)) {
      setSaveError(`MCP「${name}」已存在`);
      return;
    }
    void saveDraft({
      mcpServers: [
        ...draftRef.current.mcpServers,
        {
          name,
          command,
          args: mcpArgs.split(/\s+/).filter(Boolean),
        },
      ],
    });
    setMcpAdding(false);
    setMcpName("");
    setMcpCommand("npx");
    setMcpArgs("");
  }

  const removeModelLabel =
    pendingRemoveModel != null
      ? draft.models.find((m) => m.id === pendingRemoveModel)?.label ||
        pendingRemoveModel
      : null;

  return (
    <div
      className="modal-backdrop settings-backdrop"
      role="presentation"
      onMouseDown={(e) => {
        // Swallow backdrop presses — must use 关闭
        if (e.target === e.currentTarget) e.preventDefault();
      }}
    >
      <div
        className="modal-sheet settings-shell"
        role="dialog"
        aria-modal="true"
        aria-label="设置"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <aside className="settings-nav">
          <div className="settings-nav-head">
            <button
              type="button"
              className="settings-nav-back"
              onClick={onClose}
              aria-label="关闭设置"
              title="关闭"
            >
              <IconChevronLeft size={18} />
            </button>
            <div className="settings-nav-title">设置</div>
            {saving ? <span className="settings-save-hint">保存中…</span> : null}
          </div>
          <nav className="settings-nav-list">
            {NAV.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`settings-nav-item ${tab === item.id ? "active" : ""}`}
                onClick={() => setTab(item.id)}
              >
                <span className="settings-nav-ico" aria-hidden>
                  <item.Icon size={16} />
                </span>
                {item.label}
              </button>
            ))}
          </nav>
        </aside>

        <section className="settings-pane">
          {saveError ? (
            <div className="settings-banner-error" role="alert">
              {saveError}
              <button
                type="button"
                className="icon-x"
                onClick={() => setSaveError(null)}
              >
                <IconX size={14} />
              </button>
            </div>
          ) : null}

          {tab === "general" && (
            <div className="settings-pane-inner">
              <h2>通用</h2>
              <p className="settings-lead">项目连接、权限与基础行为。</p>

              <div className="settings-section">
                <div className="settings-row-card">
                  <div className="settings-row-text">
                    <strong>自动批准工具权限</strong>
                    <span>关闭后，Agent 执行敏感操作前会征求你确认</span>
                  </div>
                  <button
                    type="button"
                    className={`toggle-switch ${draft.autoApprovePermissions ? "on" : ""}`}
                    role="switch"
                    aria-checked={draft.autoApprovePermissions}
                    disabled={saving}
                    onClick={() =>
                      void saveDraft({
                        autoApprovePermissions: !draftRef.current.autoApprovePermissions,
                      })
                    }
                  >
                    <i />
                  </button>
                </div>

                <div className="settings-row-card">
                  <div className="settings-row-text">
                    <strong>当前项目</strong>
                    <span>{status.workspace || "尚未打开项目文件夹"}</span>
                  </div>
                  <button
                    type="button"
                    className="settings-ghost-btn"
                    onClick={onOpenFolder}
                  >
                    {status.workspace ? "更换" : "打开"}
                  </button>
                </div>

                <div className="settings-row-card">
                  <div className="settings-row-text">
                    <strong>Agent 连接</strong>
                    <span>
                      {status.connected ? "已连接" : status.message || "未连接"}
                    </span>
                  </div>
                  <div className="settings-row-actions">
                    <button
                      type="button"
                      className="settings-ghost-btn"
                      disabled={!status.workspace || busy}
                      onClick={onReconnect}
                    >
                      重连
                    </button>
                    <button
                      type="button"
                      className="settings-ghost-btn"
                      disabled={!status.connected || busy}
                      onClick={onDisconnect}
                    >
                      断开
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {tab === "models" && (
            <div className="settings-pane-inner">
              <h2>模型</h2>
              <p className="settings-lead">
                配置 new-api 网关后，从接口获取模型并勾选要用的项；无需手动填写模型 ID。
              </p>

              <div className="settings-section">
                <div className="settings-section-head">
                  <h3>网关</h3>
                </div>
                <label className="settings-field">
                  Base URL
                  <input
                    value={draft.apiBaseUrl}
                    placeholder="https://your-newapi.com/v1"
                    onChange={(e) => {
                      const apiBaseUrl = e.target.value;
                      const next = { ...draftRef.current, apiBaseUrl };
                      draftRef.current = next;
                      setDraft(next);
                    }}
                    onBlur={() => {
                      const next = draftRef.current.apiBaseUrl.trim();
                      if (next === (settings?.apiBaseUrl ?? "")) return;
                      void saveDraft({ apiBaseUrl: next });
                    }}
                  />
                </label>
                <label className="settings-field">
                  API Key
                  <input
                    type="password"
                    value={draft.apiKey}
                    placeholder="sk-..."
                    onChange={(e) => {
                      const apiKey = e.target.value;
                      const next = { ...draftRef.current, apiKey };
                      draftRef.current = next;
                      setDraft(next);
                    }}
                    onBlur={() => {
                      const next = draftRef.current.apiKey.trim();
                      if (next === (settings?.apiKey ?? "")) return;
                      void saveDraft({ apiKey: next });
                    }}
                  />
                </label>
              </div>

              <div className="settings-section">
                <div className="settings-section-head">
                  <h3>模型列表</h3>
                  <button
                    type="button"
                    className="settings-ghost-btn"
                    disabled={fetchingModels || !draft.apiBaseUrl.trim()}
                    onClick={() => void fetchGatewayModels()}
                  >
                    {fetchingModels ? "刷新中…" : gatewayCatalog ? "刷新列表" : "获取模型列表"}
                  </button>
                </div>

                <p className="settings-hint settings-model-live">
                  会话框当前：
                  <strong>
                    {draft.models.find((m) => m.id === draft.modelId)?.label ||
                      draft.modelId ||
                      "未选择"}
                  </strong>
                  {draft.models.length > 0
                    ? ` · 已启用 ${draft.models.length} 个`
                    : " · 尚未启用任何模型"}
                </p>

                {fetchModelsHint ? (
                  <p
                    className={`settings-hint settings-fetch-hint ${fetchingModels ? "pending" : "ok"}`}
                    role="status"
                  >
                    {fetchModelsHint}
                  </p>
                ) : null}

                {fetchingModels && !gatewayCatalog ? (
                  <div className="settings-empty">正在从网关获取模型…</div>
                ) : gatewayCatalog ? (
                  <>
                    <p className="settings-hint">
                      共 {gatewayCatalog.length} 个可用模型（已去掉网关里不存在的旧项）。勾选后会出现在输入框选择器；点名称设为当前，会话框会立刻更新。
                    </p>
                    <div
                      className={`settings-card-list ${fetchingModels ? "is-refreshing" : ""}`}
                    >
                      {gatewayCatalog.map((m) => {
                        const enabled = draft.models.some((x) => x.id === m.id);
                        const isCurrent = draft.modelId === m.id;
                        return (
                          <div
                            key={m.id}
                            className={`settings-entity-card ${isCurrent ? "active" : ""}`}
                          >
                            <label className="settings-model-check" title="启用此模型">
                              <input
                                type="checkbox"
                                checked={enabled}
                                disabled={saving}
                                onChange={(e) =>
                                  setModelEnabled(m, e.target.checked)
                                }
                              />
                            </label>
                            <div className="settings-entity-avatar">
                              {initialLetter(m.label || m.id)}
                            </div>
                            <button
                              type="button"
                              className="settings-entity-main"
                              disabled={saving || !enabled}
                              onClick={() => {
                                if (!enabled || draftRef.current.modelId === m.id) return;
                                void saveDraft({ modelId: m.id });
                              }}
                            >
                              <strong>{m.label || m.id}</strong>
                              <span>
                                {m.id}
                                {isCurrent ? " · 当前" : enabled ? "" : " · 未启用"}
                              </span>
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  </>
                ) : (
                  <div className="settings-empty">
                    {draft.apiBaseUrl.trim()
                      ? "请点击「获取模型列表」从网关加载，再勾选要用的模型"
                      : "请先填写 Base URL 与 API Key"}
                  </div>
                )}
              </div>
            </div>
          )}

          {tab === "mcp" && (
            <div className="settings-pane-inner">
              <h2>工具与 MCP</h2>
              <p className="settings-lead">
                管理 Agent 可用的 MCP 服务器。推荐工具为应用内置（PPT / Excel / Word / 联网等），无需额外安装。保存后会自动重连 Agent。
              </p>

              <div className="settings-section">
                <div className="settings-section-head">
                  <h3>已启用的 MCP</h3>
                  <button
                    type="button"
                    className="settings-ghost-btn"
                    disabled={saving}
                    onClick={enableRecommendedSuite}
                  >
                    一键启用推荐套件
                  </button>
                </div>
                <div className="settings-card-list">
                  {draft.mcpServers.length === 0 && (
                    <div className="settings-empty">
                      还没有启用 MCP，点上方「一键启用推荐套件」即可打满内置能力
                    </div>
                  )}
                  {draft.mcpServers.map((s) => (
                    <div key={s.name} className="settings-entity-card">
                      <div className="settings-entity-avatar">
                        {initialLetter(s.name)}
                      </div>
                      <div className="settings-entity-main static">
                        <strong>{s.name}</strong>
                        <span>{summarizeMcp(s)}</span>
                      </div>
                      <button
                        type="button"
                        className="linkish"
                        disabled={saving}
                        onClick={() => setPendingRemoveMcpName(s.name)}
                      >
                        移除
                      </button>
                    </div>
                  ))}

                  {!mcpAdding ? (
                    <button
                      type="button"
                      className="settings-entity-card add"
                      onClick={() => {
                        setSaveError(null);
                        setMcpAdding(true);
                      }}
                    >
                      <div className="settings-entity-avatar plus">
                        <IconPlus size={16} />
                      </div>
                      <div className="settings-entity-main static">
                        <strong>新建 MCP 服务器</strong>
                        <span>添加自定义 stdio / 命令行 MCP</span>
                      </div>
                    </button>
                  ) : (
                    <div className="settings-add-box">
                      <label className="settings-field">
                        名称
                        <input
                          value={mcpName}
                          placeholder="my-mcp"
                          onChange={(e) => setMcpName(e.target.value)}
                          autoFocus
                        />
                      </label>
                      <label className="settings-field">
                        命令
                        <input
                          value={mcpCommand}
                          placeholder="npx"
                          onChange={(e) => setMcpCommand(e.target.value)}
                        />
                      </label>
                      <label className="settings-field">
                        参数（空格分隔）
                        <input
                          value={mcpArgs}
                          placeholder="-y @scope/package"
                          onChange={(e) => setMcpArgs(e.target.value)}
                        />
                      </label>
                      <div className="settings-row-actions">
                        <button
                          type="button"
                          className="settings-ghost-btn"
                          onClick={() => {
                            setMcpAdding(false);
                            setMcpName("");
                            setMcpCommand("npx");
                            setMcpArgs("");
                          }}
                        >
                          取消
                        </button>
                        <button
                          type="button"
                          className="settings-primary-btn"
                          disabled={
                            !mcpName.trim() || !mcpCommand.trim() || saving
                          }
                          onClick={commitCustomMcp}
                        >
                          保存
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              </div>

              <div className="settings-section">
                <div className="settings-section-head">
                  <h3>推荐工具</h3>
                </div>
                <div className="settings-card-list">
                  {MCP_PRESETS.map((p) => {
                    const on = presetAlreadyAdded(draft.mcpServers, p);
                    return (
                      <div key={p.id} className="settings-entity-card">
                        <div className="settings-entity-avatar">
                          {initialLetter(p.title)}
                        </div>
                        <div className="settings-entity-main static">
                          <strong>{p.title}</strong>
                          <span>{p.description}</span>
                        </div>
                        <button
                          type="button"
                          className="settings-ghost-btn"
                          disabled={on || saving}
                          onClick={() => addPreset(p)}
                        >
                          {on ? "已添加" : "添加"}
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}

          {tab === "skills" && (
            <div className="settings-pane-inner">
              <h2>Skills</h2>
              <p className="settings-lead">
                用 SKILL.md 扩展 Agent 能力。支持个人目录与项目目录。
              </p>

              <div className="settings-section">
                <div className="settings-section-head">
                  <h3>已安装</h3>
                  <button
                    type="button"
                    className="settings-ghost-btn"
                    onClick={() => onOpenSkills(true)}
                  >
                    新建
                  </button>
                </div>

                {skillsError ? (
                  <div className="settings-banner-error" role="alert">
                    {skillsError}
                  </div>
                ) : null}

                <div className="settings-card-list">
                  {skillsLoading && (
                    <div className="settings-empty">加载中…</div>
                  )}
                  {!skillsLoading && skills.length === 0 && (
                    <div className="settings-empty">
                      还没有技能。点「新建」或在管理页中创建。
                    </div>
                  )}
                  {!skillsLoading &&
                    skills.map((s) => (
                      <div
                        key={`${s.scope}-${s.path}`}
                        className="settings-entity-card"
                      >
                        <div className="settings-entity-avatar">
                          {initialLetter(s.name)}
                        </div>
                        <div className="settings-entity-main static">
                          <strong>{s.name}</strong>
                          <span>
                            {s.description || s.path}
                            {" · "}
                            {s.scope === "project" ? "项目" : "个人"}
                          </span>
                        </div>
                      </div>
                    ))}

                  <button
                    type="button"
                    className="settings-entity-card add"
                    onClick={() => onOpenSkills(false)}
                  >
                    <div className="settings-entity-avatar plus">
                      <IconList size={16} />
                    </div>
                    <div className="settings-entity-main static">
                      <strong>管理 Skills</strong>
                      <span>编辑、删除或打开技能目录</span>
                    </div>
                  </button>
                </div>
              </div>
            </div>
          )}

          {tab === "memory" && (
            <div className="settings-pane-inner">
              <h2>记忆</h2>
              <p className="settings-lead">
                <strong>永久记忆</strong>
                ：写入本机，每次对话自动注入提示词；也可在对话中发送「记住：xxx」。
                <br />
                <strong>MCP Memory</strong>
                ：工具层笔记（需在「工具与 MCP」启用），由 Agent 在任务中主动读写，与永久记忆不是同一存储。
              </p>
              <div className="settings-section">
                <div className="settings-empty-block">
                  <p>查看、新增或清空已保存的永久记忆。</p>
                  <button
                    type="button"
                    className="settings-primary-btn lg"
                    onClick={onOpenMemory}
                  >
                    管理永久记忆
                  </button>
                </div>
              </div>
            </div>
          )}

          {tab === "shortcuts" && (
            <div className="settings-pane-inner">
              <h2>快捷键与隐藏技巧</h2>
              <p className="settings-lead">
                把 Nova Build 打满常用的快捷操作都在这里。
              </p>
              <div className="settings-section">
                <div className="settings-card-list shortcuts-list">
                  {[
                    ["Ctrl + N", "新建对话"],
                    ["Ctrl + O", "打开项目文件夹"],
                    ["Ctrl + `", "打开终端面板"],
                    ["Enter", "发送（Shift+Enter 换行）"],
                    ["Tab（空输入）", "切换到规划模式"],
                    ["Esc", "关闭 / @ 提及弹层"],
                    ["/技能名", "插入 Skill（新对话更易生效）"],
                    ["@文件", "引用项目文件到上下文"],
                    ["记住：内容", "写入永久记忆"],
                    ["拖入窗口", "添加附件（也支持粘贴图片）"],
                  ].map(([keys, desc]) => (
                    <div key={keys} className="settings-entity-card static-row">
                      <kbd className="shortcut-kbd">{keys}</kbd>
                      <span className="shortcut-desc">{desc}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {tab === "agent" && (
            <div className="settings-pane-inner">
              <h2>Agent</h2>
              <p className="settings-lead">配置 Grok Build CLI 启动命令。</p>
              <div className="settings-section">
                <label className="settings-field">
                  命令 / 路径
                  <input
                    value={draft.grokCommand}
                    placeholder="grok 或完整路径"
                    onChange={(e) => {
                      const grokCommand = e.target.value;
                      const next = { ...draftRef.current, grokCommand };
                      draftRef.current = next;
                      setDraft(next);
                    }}
                    onBlur={() => {
                      const next = draftRef.current.grokCommand.trim();
                      if (next === (settings?.grokCommand ?? "")) return;
                      void saveDraft({ grokCommand: next });
                    }}
                  />
                </label>
                <p className="hint">
                  Windows / macOS 安装包均已内置 grok，一般无需另行安装官方 CLI。
                </p>
              </div>
            </div>
          )}
        </section>
      </div>

      <ConfirmDialog
        open={pendingRemoveMcpName != null}
        title="移除 MCP？"
        message={
          pendingRemoveMcpName
            ? `确定移除「${pendingRemoveMcpName}」？新对话才会完全生效。`
            : "确定移除此 MCP？"
        }
        confirmLabel="移除"
        danger
        onCancel={() => setPendingRemoveMcpName(null)}
        onConfirm={() => {
          if (pendingRemoveMcpName) removeMcpByName(pendingRemoveMcpName);
        }}
      />

      <ConfirmDialog
        open={pendingRemoveModel != null}
        title="删除模型？"
        message={
          removeModelLabel
            ? `确定从列表中删除「${removeModelLabel}」？`
            : "确定删除该模型？"
        }
        confirmLabel="删除"
        danger
        onCancel={() => setPendingRemoveModel(null)}
        onConfirm={() => {
          if (pendingRemoveModel) removeModel(pendingRemoveModel);
        }}
      />
    </div>
  );
}
