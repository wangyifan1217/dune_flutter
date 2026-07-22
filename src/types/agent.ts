export interface ModelEntry {
  /** new-api / 上游模型 ID，例如 deepseek-v4-pro */
  id: string;
  /** 显示名，可空则用 id */
  label: string;
}

export interface McpEnvVar {
  name: string;
  value: string;
}

export interface McpServerConfig {
  name: string;
  command: string;
  args?: string[];
  env?: McpEnvVar[];
}

export interface AppSettings {
  /** Agent CLI 可执行文件（历史字段名 grokCommand，与 Rust 一致） */
  grokCommand: string;
  grokArgs: string[];
  autoApprovePermissions: boolean;
  /** new-api Base URL，多模型共用 */
  apiBaseUrl: string;
  /** new-api Key，多模型共用一把 */
  apiKey: string;
  /** 当前会话选用的模型 id */
  modelId: string;
  /** 用户配置的可选模型列表 */
  models: ModelEntry[];
  mcpServers: McpServerConfig[];
}

export interface AgentStatus {
  connected: boolean;
  sessionId?: string | null;
  workspace?: string | null;
  message: string;
}

export interface ChatMessage {
  id: string;
  role: "user" | "assistant" | "system";
  content: string;
  status: "pending" | "streaming" | "completed" | "error";
  attachments?: ChatAttachment[];
}

export interface ChatAttachment {
  id: string;
  name: string;
  mimeType: string;
  size: number;
  encoding: "base64" | "utf8";
  /** Base64 binary payload or UTF-8 text-file contents. */
  data: string;
}

export interface FileEntry {
  name: string;
  path: string;
  isDir: boolean;
}

export interface DirectoryTreeNode {
  name: string;
  path: string;
  isDir: boolean;
  children?: DirectoryTreeNode[];
}

export interface SessionUpdateEvent {
  threadId: string;
  sessionId: string;
  update: Record<string, unknown>;
}

function asModels(raw: unknown, modelId: string): ModelEntry[] {
  if (Array.isArray(raw)) {
    return raw
      .map((item) => {
        if (!item || typeof item !== "object") return null;
        const o = item as Record<string, unknown>;
        const id = String(o.id ?? "").trim();
        if (!id) return null;
        return { id, label: String(o.label ?? "").trim() || id };
      })
      .filter((m): m is ModelEntry => Boolean(m));
  }
  // 旧存档只有 modelId：自动纳入列表
  if (modelId.trim()) {
    return [{ id: modelId.trim(), label: modelId.trim() }];
  }
  return [];
}

/** 兼容旧存档里的 novaCommand / 无 models 字段 */
export function normalizeSettings(raw: Record<string, unknown> | AppSettings): AppSettings {
  const r = raw as Record<string, unknown>;
  const modelId = String(r.modelId ?? "").trim();
  let models = asModels(r.models, modelId);
  // 当前选中的模型不在列表里时补上
  if (modelId && !models.some((m) => m.id === modelId)) {
    models = [...models, { id: modelId, label: modelId }];
  }
  const active =
    modelId && models.some((m) => m.id === modelId)
      ? modelId
      : models[0]?.id ?? "";

  return {
    grokCommand: String(r.grokCommand ?? r.novaCommand ?? "grok"),
    grokArgs: (Array.isArray(r.grokArgs)
      ? r.grokArgs
      : Array.isArray(r.novaArgs)
        ? r.novaArgs
        : ["agent", "stdio"]) as string[],
    autoApprovePermissions: Boolean(r.autoApprovePermissions ?? true),
    apiBaseUrl: String(r.apiBaseUrl ?? ""),
    apiKey: String(r.apiKey ?? ""),
    modelId: active,
    models,
    mcpServers: (Array.isArray(r.mcpServers) ? r.mcpServers : []) as McpServerConfig[],
  };
}

export function modelLabelOf(models: ModelEntry[], modelId: string): string {
  const hit = models.find((m) => m.id === modelId);
  if (hit) return hit.label || hit.id;
  return modelId.trim() || "选择模型";
}
