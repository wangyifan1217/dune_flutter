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

export type ToolCallStatus = "pending" | "running" | "completed" | "failed";

export interface ChatMessage {
  id: string;
  role: "user" | "assistant" | "system";
  content: string;
  status: "pending" | "streaming" | "completed" | "error";
  attachments?: ChatAttachment[];
  /** 结构化消息类型；缺省按普通文本 */
  kind?: "text" | "plan" | "tool" | "error" | "plan-confirm";
  /** plan 类型时的条目列表 */
  planEntries?: string[];
  /** tool 类型：ACP toolCallId，用于 upsert 更新 */
  toolCallId?: string;
  toolTitle?: string;
  toolStatus?: ToolCallStatus;
  toolOutput?: string;
  /** 写文件类工具：edit 会在会话内展示改码卡 */
  toolKind?: "edit" | "other";
  toolPath?: string;
  toolDiff?: string;
  toolCreated?: boolean;
}

/** 对话交互模式（通过提示词前缀约束 Agent 行为） */
export type ChatMode = "agent" | "plan" | "ask";

export const CHAT_MODE_PREFIX: Record<ChatMode, string> = {
  agent: "",
  plan:
    "【规划模式·只读】你现在只能输出实现计划（步骤、风险、验收标准）。严禁：创建/修改/删除文件（包括 plan.md）、执行 shell 命令、调用会改写磁盘的 MCP。计划用对话正文清晰列出即可，不要落盘。规划完成后明确询问用户是否执行，并等待用户确认「按此执行」后再动手。\n\n",
  ask:
    "【问答模式·只读】你只能回答问题与做分析。严禁：创建/修改/删除文件、执行 shell 命令、调用会改写磁盘的工具。可用只读检索与说明。\n\n",
};

/** 去掉模式提示词前缀，得到用户可见正文 */
export function stripChatModePrefix(content: string): string {
  let text = content;
  for (const prefix of Object.values(CHAT_MODE_PREFIX)) {
    if (prefix && text.startsWith(prefix)) {
      text = text.slice(prefix.length);
      break;
    }
  }
  return text;
}

/** 用户 confirm 开始动手时，应从规划切到执行 */
export function textRequestsExecute(text: string): boolean {
  const t = text.trim();
  if (!t) return false;
  if (
    /^(?:按此执行|开始执行|执行吧|可以执行|确认执行|动手(?:吧|做)|开始编码|按计划执行|开干)[.!！。…]*$/u.test(
      t,
    )
  ) {
    return true;
  }
  return /开始执行|按此执行|可以动手|开始改代码|开始编码|退出规划|不要再规划|直接改代码|只改代码/.test(
    t,
  );
}

/** 点「按此执行」或用户确认执行时发给模型的指令（避免空谈退出规划） */
export const EXECUTE_CONFIRMED_PROMPT =
  "【已确认执行】请立即按上文规划开始改代码。禁止再讨论如何退出规划模式或只做计划；可以直接创建与修改文件，按步骤推进。";

/** 助手表示已确认、开始编码时，UI 也应切到执行 */
export function textSuggestsExecuteMode(text: string): boolean {
  return /退出规划模式|开始编码|开始执行|按此(?:计划)?执行|方案已确认.*(?:编码|执行)|动手改代码/.test(
    text,
  );
}

export function isPlanFilePath(path: string): boolean {
  const base = path.split(/[/\\]/).pop()?.toLowerCase() ?? "";
  return (
    base === "plan.md" ||
    base === "plan.markdown" ||
    /^plan[-_.]/i.test(base) ||
    base.endsWith(".plan.md")
  );
}

/** 本轮结束后是否应在会话里插入「是否执行」选择卡 */
export function shouldOfferPlanConfirm(
  messages: ChatMessage[],
  chatMode: ChatMode,
): boolean {
  let lastUser = -1;
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    if (messages[i].role === "user") {
      lastUser = i;
      break;
    }
  }
  if (lastUser < 0) return false;
  const turn = messages.slice(lastUser + 1);
  if (turn.some((m) => m.kind === "plan-confirm")) return false;
  const hasReply = turn.some(
    (m) =>
      m.role === "assistant" &&
      m.kind !== "error" &&
      (m.content.trim().length > 0 ||
        m.kind === "tool" ||
        m.kind === "plan" ||
        Boolean(m.planEntries?.length)),
  );
  if (!hasReply) return false;
  if (chatMode === "plan") return true;
  if (turn.some((m) => m.kind === "plan")) return true;
  if (
    turn.some(
      (m) => m.kind === "tool" && m.toolPath && isPlanFilePath(m.toolPath),
    )
  ) {
    return true;
  }
  const lastText = [...turn]
    .reverse()
    .find((m) => m.role === "assistant" && m.content.trim());
  if (
    lastText &&
    /规划|实现计划|分步|架构|步骤|验收/.test(lastText.content) &&
    /先|建议|方案|计划/.test(lastText.content)
  ) {
    return true;
  }
  return false;
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
