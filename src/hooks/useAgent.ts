import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type {
  AgentStatus,
  AppSettings,
  ChatAttachment,
  ChatMessage,
  DirectoryTreeNode,
  SessionUpdateEvent,
  ToolCallStatus,
} from "../types/agent";
import { normalizeSettings, textSuggestsExecuteMode, isPlanFilePath } from "../types/agent";
import type { ActivityItem, DiffHunk } from "../types/codex";
import { extractDiffsFromText } from "../lib/diffs";

type StreamPart =
  | { kind: "text"; text: string; messageId?: string }
  | {
      kind: "tool";
      toolCallId: string;
      title: string;
      status: ToolCallStatus;
      output?: string;
      toolKind?: "edit" | "other";
      toolPath?: string;
      toolDiff?: string;
      toolCreated?: boolean;
    }
  | { kind: "plan"; text: string };

function localizeToolText(input: string): string {
  return input
    .replace(/\bpending\b/gi, "等待中")
    .replace(/\bin_progress\b/gi, "进行中")
    .replace(/\bcompleted\b/gi, "已完成")
    .replace(/\bupdated\b/gi, "已更新")
    .replace(/\bcancelled\b/gi, "已取消")
    .replace(/\bfailed\b/gi, "失败")
    .replace(/\bTool\b/g, "工具")
    .replace(/\btool\b/g, "工具")
    .replace(/\bfound (\d+) matches?\b/gi, "找到 $1 处匹配")
    .replace(/\bgrep\b/gi, "搜索");
}

function looksLikeEditTool(title: string, kind?: string, path?: string, hasContent?: boolean): boolean {
  const blob = `${kind ?? ""} ${title}`.toLowerCase();
  // 明确排除读/列目录类
  if (
    /\b(read|list|ls|glob|grep|search|find|stat|dir)\b/.test(blob) ||
    /读取|列出|浏览|搜索|查看目录|读文件|list_dir|list_directory|read_file|read_text/.test(
      blob,
    )
  ) {
    return false;
  }
  if (
    /\b(write|edit|create|overwrite|save)\b/.test(blob) ||
    /写入|编辑|创建|保存|修改文件|写文件/.test(title) ||
    /write_text_file|write_file|fs\/write/.test(blob)
  ) {
    return true;
  }
  // 带路径且带写入内容的常见写文件形态（不能仅凭 path，读目录也有 path）
  if (path && hasContent) return true;
  return false;
}

function extractPathFromToolUpdate(update: Record<string, unknown>): string | undefined {
  const locations = update.locations as Array<{ path?: string }> | undefined;
  if (locations?.[0]?.path) return locations[0].path;
  const rawInput = update.rawInput as Record<string, unknown> | undefined;
  if (typeof rawInput?.path === "string") return rawInput.path;
  if (typeof update.path === "string") return update.path;
  return undefined;
}

function extractDiffFromText(text: string): string | undefined {
  if (!text.trim()) return undefined;
  // JSON result from fs/write_text_file
  try {
    const parsed = JSON.parse(text) as { diff?: string; path?: string };
    if (typeof parsed?.diff === "string" && parsed.diff.trim()) return parsed.diff;
  } catch {
    /* not json */
  }
  const fence = text.match(/```diff\s*([\s\S]*?)```/i);
  if (fence?.[1]?.trim()) return fence[1].trim();
  if (/^---\s/m.test(text) && /^\+\+\+\s/m.test(text)) return text.trim();
  return undefined;
}

function extractCreatedFlag(text: string | undefined): boolean | undefined {
  if (!text) return undefined;
  try {
    const parsed = JSON.parse(text) as { created?: boolean };
    if (typeof parsed?.created === "boolean") return parsed.created;
  } catch {
    /* ignore */
  }
  if (/\(created\)/i.test(text) || /已创建/.test(text)) return true;
  if (/\(updated\)/i.test(text) || /已更新|已编辑/.test(text)) return false;
  return undefined;
}

function mapToolStatus(raw?: string): ToolCallStatus {
  const s = (raw ?? "pending").toLowerCase();
  if (s.includes("fail") || s.includes("error") || s.includes("cancel")) return "failed";
  if (s.includes("complete") || s === "done" || s === "success") return "completed";
  if (s.includes("progress") || s.includes("running") || s === "updated") return "running";
  if (s.includes("pending")) return "pending";
  return "running";
}

function extractToolOutput(content: unknown): string {
  if (!content) return "";
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) {
    // 单对象：优先抽出 diff / text
    if (typeof content === "object" && content) {
      const row = content as Record<string, unknown>;
      if (typeof row.diff === "string") return JSON.stringify(row);
      if (typeof row.text === "string") return row.text;
    }
    try {
      return JSON.stringify(content, null, 2);
    } catch {
      return String(content);
    }
  }
  return content
    .map((c) => {
      if (!c || typeof c !== "object") return "";
      const row = c as Record<string, unknown>;
      if (typeof row.text === "string") return row.text;
      if (row.content && typeof row.content === "object") {
        const inner = row.content as { text?: string; diff?: string };
        if (typeof inner.diff === "string") {
          return JSON.stringify({ diff: inner.diff, path: row.path });
        }
        return inner.text ?? "";
      }
      if (typeof row.type === "string" && row.type === "diff") {
        if (typeof row.diff === "string") return row.diff as string;
        // ACP diff content：用 oldText/newText 拼不出完整 unified 时，至少保留 JSON
        try {
          return JSON.stringify(row, null, 2);
        } catch {
          return "";
        }
      }
      if (typeof row.diff === "string") return row.diff;
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function parseUpdate(update: Record<string, unknown>): StreamPart | null {
  const sessionUpdate = update.sessionUpdate;
  if (sessionUpdate === "agent_message_chunk") {
    const content = update.content as { text?: string } | undefined;
    const text = content?.text;
    if (!text) return null;
    return {
      kind: "text",
      text,
      messageId: typeof update.messageId === "string" ? update.messageId : undefined,
    };
  }
  if (sessionUpdate === "tool_call" || sessionUpdate === "tool_call_update") {
    const kindStr = typeof update.kind === "string" ? update.kind : undefined;
    const title =
      (typeof update.title === "string" && update.title) ||
      kindStr ||
      "工具调用";
    const toolCallId =
      (typeof update.toolCallId === "string" && update.toolCallId) ||
      (typeof update.tool_call_id === "string" && update.tool_call_id) ||
      `title:${title}`;
    const output = extractToolOutput(update.content);
    const status =
      sessionUpdate === "tool_call"
        ? mapToolStatus((update.status as string | undefined) ?? "pending")
        : mapToolStatus(update.status as string | undefined);
    const rawInput = update.rawInput as Record<string, unknown> | undefined;
    const toolPath = extractPathFromToolUpdate(update);
    const hasContent =
      typeof rawInput?.content === "string" ||
      Boolean(output && extractDiffFromText(output));
    const toolDiff = output ? extractDiffFromText(output) : undefined;
    const toolCreated = extractCreatedFlag(output);
    const toolKind: "edit" | "other" = looksLikeEditTool(
      title,
      kindStr,
      toolPath,
      hasContent,
    )
      ? "edit"
      : "other";
    return {
      kind: "tool",
      toolCallId,
      title,
      status,
      output: output || undefined,
      toolKind,
      toolPath,
      toolDiff,
      toolCreated,
    };
  }
  if (sessionUpdate === "plan") {
    const entries = update.entries as
      | Array<{ content?: string; priority?: string; status?: string }>
      | undefined;
    if (!entries?.length) return null;
    return {
      kind: "plan",
      text: entries
        .map((e) => {
          const status = e.status ? `（${e.status}）` : "";
          return `• ${e.content ?? ""}${status}`;
        })
        .join("\n"),
    };
  }
  return null;
}

function pathsLikelySame(a?: string, b?: string): boolean {
  if (!a || !b) return false;
  if (a === b) return true;
  const na = a.replace(/\\/g, "/").toLowerCase();
  const nb = b.replace(/\\/g, "/").toLowerCase();
  if (na === nb) return true;
  return na.endsWith("/" + nb) || nb.endsWith("/" + na) || na.endsWith(nb) || nb.endsWith(na);
}

function upsertToolMessage(
  prev: ChatMessage[],
  part: Extract<StreamPart, { kind: "tool" }>,
): ChatMessage[] {
  const idx = prev.findIndex(
    (m) => m.kind === "tool" && m.toolCallId === part.toolCallId,
  );
  const title = localizeToolText(part.title);
  const mergeFields = {
    toolKind: part.toolKind ?? (undefined as "edit" | "other" | undefined),
    toolPath: part.toolPath,
    toolDiff: part.toolDiff,
    toolCreated: part.toolCreated,
  };
  if (idx >= 0) {
    const existing = prev[idx];
    const next: ChatMessage = {
      ...existing,
      toolTitle: title || existing.toolTitle,
      toolStatus: part.status,
      toolOutput: part.output
        ? [existing.toolOutput, part.output].filter(Boolean).join("\n")
        : existing.toolOutput,
      content: title,
      status:
        part.status === "failed"
          ? "error"
          : part.status === "completed"
            ? "completed"
            : "streaming",
      toolKind: mergeFields.toolKind ?? existing.toolKind,
      toolPath: mergeFields.toolPath || existing.toolPath,
      toolDiff: mergeFields.toolDiff || existing.toolDiff,
      toolCreated:
        mergeFields.toolCreated !== undefined
          ? mergeFields.toolCreated
          : existing.toolCreated,
    };
    // 从合并后的 output 再抽一次 diff（完成态常带 JSON）
    if (!next.toolDiff && next.toolOutput) {
      next.toolDiff = extractDiffFromText(next.toolOutput);
    }
    // 仅真实写文件（有 diff，或标题/kind 判定为写入）才标为 edit；有路径不等于编辑（读目录也会带 path）
    if (next.toolDiff) {
      next.toolKind = "edit";
    } else if (
      next.toolKind !== "edit" &&
      looksLikeEditTool(next.toolTitle ?? "", undefined, next.toolPath, false)
    ) {
      next.toolKind = "edit";
    }
    // 若最终不是 edit，避免残留「已编辑」展示所需字段被误用
    if (next.toolKind !== "edit") {
      next.toolDiff = undefined;
    }
    const copy = [...prev];
    copy[idx] = next;
    return copy;
  }

  const toolDiff = part.toolDiff;
  const toolPath = part.toolPath;
  let toolKind = part.toolKind ?? "other";
  if (toolDiff) toolKind = "edit";

  // 同一轮同一文件多次写入 → 合并到上一张改码卡，避免叠四张
  if (toolKind === "edit" && toolPath) {
    let lastUserIdx = -1;
    for (let i = prev.length - 1; i >= 0; i -= 1) {
      if (prev[i].role === "user") {
        lastUserIdx = i;
        break;
      }
    }
    for (let i = prev.length - 1; i > lastUserIdx; i -= 1) {
      const m = prev[i];
      if (m.kind === "tool" && m.toolKind === "edit" && pathsLikelySame(m.toolPath, toolPath)) {
        const copy = [...prev];
        copy[i] = {
          ...m,
          toolTitle: title || m.toolTitle,
          toolStatus: part.status,
          toolOutput: part.output
            ? [m.toolOutput, part.output].filter(Boolean).join("\n")
            : m.toolOutput,
          content: title,
          status:
            part.status === "failed"
              ? "error"
              : part.status === "completed"
                ? "completed"
                : "streaming",
          toolPath: toolPath || m.toolPath,
          toolDiff: toolDiff || m.toolDiff,
          toolCreated:
            part.toolCreated !== undefined ? part.toolCreated : m.toolCreated,
          toolCallId: part.toolCallId || m.toolCallId,
        };
        return copy;
      }
    }
  }

  return [
    ...prev,
    {
      id: crypto.randomUUID(),
      role: "assistant",
      content: title,
      status:
        part.status === "failed"
          ? "error"
          : part.status === "completed"
            ? "completed"
            : "streaming",
      kind: "tool",
      toolCallId: part.toolCallId,
      toolTitle: title,
      toolStatus: part.status,
      toolOutput: part.output,
      toolKind,
      toolPath,
      toolDiff,
      toolCreated: part.toolCreated,
    },
  ];
}

function finalizeOpenTools(prev: ChatMessage[]): ChatMessage[] {
  return prev.map((m) => {
    if (m.kind !== "tool") return m;
    if (m.toolStatus === "completed" || m.toolStatus === "failed") return m;
    return {
      ...m,
      toolStatus: "completed" as const,
      status: "completed" as const,
    };
  });
}

interface Options {
  activeSessionId: string | null;
  setMessages: (
    sessionId: string,
    updater: (prev: ChatMessage[]) => ChatMessage[],
  ) => void;
  /** 检测到规划产物/规划意图时，切到「规划」模式 */
  onEnterPlanMode?: (threadId: string) => void;
  /** 检测到确认执行/退出规划时，切到「执行」模式 */
  onEnterAgentMode?: (threadId: string) => void;
}

function textSuggestsPlanMode(text: string): boolean {
  return /进入规划模式|先做规划|先进行规划|切换到规划|规划模式|理清架构后再|先出(?:一份)?计划|只输出计划|等你确认后再(?:动手|执行)|等你确认「?按此执行/.test(
    text,
  );
}

export function useAgent({
  activeSessionId,
  setMessages,
  onEnterPlanMode,
  onEnterAgentMode,
}: Options) {
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [status, setStatus] = useState<AgentStatus>({
    connected: false,
    message: "未连接",
  });
  const [tree, setTree] = useState<DirectoryTreeNode | null>(null);
  const [controlBusy, setControlBusy] = useState(false);
  const [busyBySession, setBusyBySession] = useState<Record<string, boolean>>({});
  const [progressBySession, setProgressBySession] = useState<Record<string, string>>({});
  const [lastError, setLastError] = useState<string | null>(null);
  const [diffs, setDiffs] = useState<DiffHunk[]>([]);
  const [activity, setActivity] = useState<ActivityItem[]>([]);
  const streamMsgIds = useRef(new Map<string, string | null>());
  const streamBuffers = useRef(new Map<string, string>());
  const streamFlushTimers = useRef(new Map<string, number>());
  const cancelledSessions = useRef(new Set<string>());
  const enterPlanModeRef = useRef(onEnterPlanMode);
  enterPlanModeRef.current = onEnterPlanMode;
  const enterAgentModeRef = useRef(onEnterAgentMode);
  enterAgentModeRef.current = onEnterAgentMode;
  const busy = controlBusy || Boolean(activeSessionId && busyBySession[activeSessionId]);

  const requestPlanMode = useCallback((threadId: string) => {
    enterPlanModeRef.current?.(threadId);
  }, []);

  const requestAgentMode = useCallback((threadId: string) => {
    enterAgentModeRef.current?.(threadId);
  }, []);

  const flushStreamBuffer = useCallback(
    (threadId: string) => {
      const timer = streamFlushTimers.current.get(threadId);
      if (timer != null) {
        window.clearTimeout(timer);
        streamFlushTimers.current.delete(threadId);
      }
      const chunk = streamBuffers.current.get(threadId) ?? "";
      streamBuffers.current.set(threadId, "");
      if (!chunk) return;
      setMessages(threadId, (prev) => {
        const streamMsgId = streamMsgIds.current.get(threadId);

        // 优先按本轮流式 id 原地追加；若其后已插入工具/规划，则改在末尾新开气泡（总结文字在改码卡下方）
        let targetIdx =
          streamMsgId != null
            ? prev.findIndex((m) => m.id === streamMsgId)
            : -1;

        if (targetIdx >= 0) {
          const interrupted = prev
            .slice(targetIdx + 1)
            .some((m) => m.kind === "tool" || m.kind === "plan");
          if (interrupted) {
            targetIdx = -1;
          }
        }

        if (targetIdx < 0) {
          // 只接「位于末尾之后」的流式正文：从最后往前找，遇到 tool/plan 就停
          for (let i = prev.length - 1; i >= 0; i -= 1) {
            const m = prev[i];
            if (m.role === "user") break;
            if (m.kind === "tool" || m.kind === "plan" || m.kind === "error") break;
            if (
              m.role === "assistant" &&
              (m.status === "streaming" || m.kind === "text" || !m.kind)
            ) {
              targetIdx = i;
              break;
            }
          }
        }

        if (targetIdx >= 0) {
          const existing = prev[targetIdx];
          const nextContent = existing.content + chunk;
          const copy = [...prev];
          copy[targetIdx] = {
            ...existing,
            content: nextContent,
            status: "streaming",
            kind: "text",
          };
          streamMsgIds.current.set(threadId, existing.id);
          if (textSuggestsExecuteMode(nextContent)) {
            requestAgentMode(threadId);
          } else if (textSuggestsPlanMode(nextContent)) {
            requestPlanMode(threadId);
          }
          return copy;
        }

        const id = crypto.randomUUID();
        streamMsgIds.current.set(threadId, id);
        if (textSuggestsExecuteMode(chunk)) {
          requestAgentMode(threadId);
        } else if (textSuggestsPlanMode(chunk)) {
          requestPlanMode(threadId);
        }
        return [
          ...prev,
          {
            id,
            role: "assistant",
            content: chunk,
            status: "streaming",
            kind: "text",
          },
        ];
      });
    },
    [setMessages, requestPlanMode, requestAgentMode],
  );

  const scheduleStreamFlush = useCallback(
    (threadId: string) => {
      if (streamFlushTimers.current.has(threadId)) return;
      const timer = window.setTimeout(() => {
        streamFlushTimers.current.delete(threadId);
        flushStreamBuffer(threadId);
      }, 48);
      streamFlushTimers.current.set(threadId, timer);
    },
    [flushStreamBuffer],
  );

  const setSessionBusy = useCallback((sessionId: string, isBusy: boolean) => {
    setBusyBySession((prev) => ({ ...prev, [sessionId]: isBusy }));
  }, []);

  const clearSessionBusy = useCallback((sessionId: string) => {
    setBusyBySession((prev) => {
      if (!(sessionId in prev)) return prev;
      const next = { ...prev };
      delete next[sessionId];
      return next;
    });
    setProgressBySession((prev) => {
      if (!(sessionId in prev)) return prev;
      const next = { ...prev };
      delete next[sessionId];
      return next;
    });
    cancelledSessions.current.delete(sessionId);
  }, []);

  const refreshSettings = useCallback(async () => {
    const next = await invoke<AppSettings>("get_settings");
    const normalized = normalizeSettings(next as unknown as Record<string, unknown>);
    setSettings(normalized);
    return normalized;
  }, []);

  const refreshStatus = useCallback(async () => {
    const next = await invoke<AgentStatus>("get_agent_status");
    setStatus(next);
    return next;
  }, []);

  const refreshTree = useCallback(async (path: string) => {
    const next = await invoke<DirectoryTreeNode>("get_workspace_tree", { path });
    setTree(next);
    return next;
  }, []);

  const workspaceRef = useRef<string | null>(null);
  useEffect(() => {
    workspaceRef.current = status.workspace ?? null;
  }, [status.workspace]);

  // 工作区在、文件树丢了（重连/热更新/状态回写）时自动补树；清空项目时同步清树
  useEffect(() => {
    const ws = status.workspace;
    if (!ws) {
      setTree(null);
      return;
    }
    void refreshTree(ws).catch((error) => {
      setLastError(`读取文件夹失败：${String(error)}`);
    });
  }, [status.workspace, refreshTree]);

  useEffect(() => {
    let alive = true;
    const cleanups: UnlistenFn[] = [];
    let refreshTimer: ReturnType<typeof setTimeout> | null = null;

    void refreshSettings().catch((e) => alive && setLastError(String(e)));
    void refreshStatus().catch((e) => alive && setLastError(String(e)));

    const scheduleTreeRefresh = () => {
      const path = workspaceRef.current;
      if (!path) return;
      if (refreshTimer) clearTimeout(refreshTimer);
      // 连续写多个文件时合并刷新，避免文件树抖动
      refreshTimer = setTimeout(() => {
        void refreshTree(path).catch(() => undefined);
      }, 300);
    };

    const attach = async () => {
      const u1 = await listen<AgentStatus>("agent://status", (event) => {
        if (alive) setStatus(event.payload);
      });
      if (!alive) return u1();
      cleanups.push(u1);

      const uWorkspace = await listen<{ path?: string }>(
        "agent://workspace-changed",
        () => {
          if (alive) scheduleTreeRefresh();
        },
      );
      if (!alive) return uWorkspace();
      cleanups.push(uWorkspace);

      const uFileEdited = await listen<{
        threadId?: string;
        path?: string;
        created?: boolean;
        diff?: string;
      }>("agent://file-edited", (event) => {
        if (!alive) return;
        const { threadId, path, created, diff } = event.payload;
        if (!threadId || !path || !diff) return;
        streamMsgIds.current.set(threadId, null);
        if (isPlanFilePath(path)) {
          requestPlanMode(threadId);
        }
        setMessages(threadId, (prev) => {
          // 同路径改码卡合并更新（多次写同一文件只留一张，diff 用最新）
          const idx = [...prev]
            .map((m, i) => ({ m, i }))
            .reverse()
            .find(
              ({ m }) =>
                m.kind === "tool" &&
                m.toolKind === "edit" &&
                pathsLikelySame(m.toolPath, path),
            )?.i;
          if (idx != null) {
            const copy = [...prev];
            copy[idx] = {
              ...copy[idx],
              toolKind: "edit",
              toolPath: path,
              toolDiff: diff,
              toolCreated: created,
              toolStatus: "completed",
              status: "completed",
              toolTitle: created ? `已创建 ${path}` : `已编辑 ${path}`,
              content: created ? `已创建 ${path}` : `已编辑 ${path}`,
            };
            return copy;
          }
          return [
            ...prev,
            {
              id: crypto.randomUUID(),
              role: "assistant",
              content: created ? `已创建 ${path}` : `已编辑 ${path}`,
              status: "completed",
              kind: "tool",
              toolCallId: `file-edit:${path}:${Date.now()}`,
              toolTitle: created ? `已创建 ${path}` : `已编辑 ${path}`,
              toolStatus: "completed",
              toolKind: "edit",
              toolPath: path,
              toolDiff: diff,
              toolCreated: created,
            },
          ];
        });
        setDiffs((prev) =>
          [
            {
              id: crypto.randomUUID(),
              path,
              summary: created ? "文件已创建" : "文件已更新",
              content: diff,
            },
            ...prev,
          ].slice(0, 50),
        );
      });
      if (!alive) return uFileEdited();
      cleanups.push(uFileEdited);

      const u2 = await listen<SessionUpdateEvent>("agent://session-update", (event) => {
        if (!alive) return;
        const threadId = event.payload.threadId;
        if (!threadId) return;
        const part = parseUpdate(event.payload.update);
        if (!part) return;
        if (part.kind === "tool") {
          // 工具插入后，后续正文应出现在改码卡下方，不要再合并进工具前的气泡
          streamMsgIds.current.set(threadId, null);
          if (part.toolPath && isPlanFilePath(part.toolPath)) {
            requestPlanMode(threadId);
          }
          setProgressBySession((prev) => ({
            ...prev,
            [threadId]:
              part.toolKind === "edit" && part.toolPath
                ? `正在编辑：${part.toolPath.split(/[/\\]/).pop()}`
                : `正在执行工具：${localizeToolText(part.title)}`,
          }));
          setMessages(threadId, (prev) => upsertToolMessage(prev, part));

          const text = `${localizeToolText(part.title)}${part.status ? ` · ${part.status}` : ""}`;
          setActivity((prev) =>
            [{ id: crypto.randomUUID(), text, at: Date.now() }, ...prev].slice(0, 100),
          );
          const found = extractDiffsFromText(
            [part.title, part.output].filter(Boolean).join("\n"),
          );
          if (found.length) {
            setDiffs((prev) => [...found, ...prev].slice(0, 50));
          }
          return;
        }

        if (part.kind === "text") {
          // 进度只在首段文字时更新，避免每 token 触发整树重渲染
          setProgressBySession((prev) => {
            if (prev[threadId] === "模型正在生成回复") return prev;
            return { ...prev, [threadId]: "模型正在生成回复" };
          });
          streamBuffers.current.set(
            threadId,
            (streamBuffers.current.get(threadId) ?? "") + part.text,
          );
          if (part.messageId) {
            const existing = streamMsgIds.current.get(threadId);
            if (!existing) streamMsgIds.current.set(threadId, part.messageId);
          }
          scheduleStreamFlush(threadId);
          return;
        }

        if (part.kind === "plan") {
          requestPlanMode(threadId);
          const entries = part.text
            .split("\n")
            .map((line) => line.replace(/^•\s*/, "").trim())
            .filter(Boolean);
          setMessages(threadId, (prev) => {
            // 同一轮对话只保留一张规划卡，后续更新原地覆盖（避免 in_progress→completed 叠出两份）
            let lastUserIdx = -1;
            for (let i = prev.length - 1; i >= 0; i -= 1) {
              if (prev[i].role === "user") {
                lastUserIdx = i;
                break;
              }
            }
            let planIdx = -1;
            for (let i = prev.length - 1; i > lastUserIdx; i -= 1) {
              if (prev[i].kind === "plan") {
                planIdx = i;
                break;
              }
            }
            if (planIdx >= 0) {
              const copy = [...prev];
              copy[planIdx] = {
                ...copy[planIdx],
                content: part.text,
                planEntries: entries,
                status: "completed",
              };
              return copy;
            }
            return [
              ...prev,
              {
                id: crypto.randomUUID(),
                role: "assistant",
                content: part.text,
                status: "completed",
                kind: "plan",
                planEntries: entries,
              },
            ];
          });
          setActivity((prev) =>
            [
              {
                id: crypto.randomUUID(),
                text: `计划\n${part.text}`,
                at: Date.now(),
              },
              ...prev,
            ].slice(0, 100),
          );
          return;
        }
      });
      if (!alive) return u2();
      cleanups.push(u2);

      const u3 = await listen<{ threadId?: string; stage?: string }>(
        "agent://request-progress",
        (event) => {
          const { threadId, stage } = event.payload;
          if (!alive || !threadId || !stage) return;
          setProgressBySession((prev) => ({ ...prev, [threadId]: stage }));
        },
      );
      if (!alive) return u3();
      cleanups.push(u3);
    };

    void attach();
    return () => {
      alive = false;
      if (refreshTimer) clearTimeout(refreshTimer);
      cleanups.forEach((fn) => fn());
    };
  }, [refreshSettings, refreshStatus, refreshTree, setMessages, scheduleStreamFlush, requestPlanMode]);

  const openWorkspace = useCallback(
    async (path: string) => {
      setLastError(null);
      // 先快速登记工作区，立刻解除“卡死”感
      try {
        const next = await invoke<AgentStatus>("set_workspace", { path });
        setStatus(next);
        if (!next.connected && next.message.includes("失败")) {
          setLastError(next.message);
        }
      } catch (error) {
        setLastError(String(error));
        throw error;
      }

      // 文件树后台加载，不挡 UI
      const treePath = path;
      void refreshTree(treePath).catch((error) => {
        setLastError(`读取文件夹失败：${String(error)}`);
      });
    },
    [refreshTree],
  );

  const reconnect = useCallback(async () => {
    setControlBusy(true);
    setLastError(null);
    try {
      setStatus(await invoke<AgentStatus>("reconnect_agent"));
    } catch (error) {
      setLastError(String(error));
    } finally {
      setControlBusy(false);
    }
  }, []);

  const connectDefaultAgent = useCallback(async (_threadId: string) => {
    // 仅标记“可对话”，真正启动 grok 在首次 send_prompt；不要把会话打成 busy，
    // 否则空对话也会出现「正在分析」并卡住观感。
    setLastError(null);
    try {
      setStatus(await invoke<AgentStatus>("connect_default_agent"));
      return true;
    } catch (error) {
      setLastError(String(error));
      return false;
    }
  }, []);

  const disconnect = useCallback(async () => {
    try {
      setStatus(await invoke<AgentStatus>("disconnect_agent"));
    } catch (error) {
      setLastError(String(error));
    }
  }, []);

  const clearWorkspace = useCallback(async () => {
    setControlBusy(true);
    setLastError(null);
    try {
      setStatus(await invoke<AgentStatus>("clear_workspace"));
      setTree(null);
    } catch (error) {
      setLastError(String(error));
      throw error;
    } finally {
      setControlBusy(false);
    }
  }, []);

  const cancelMessage = useCallback(
    async (threadId: string) => {
      if (!threadId || !busyBySession[threadId]) return;
      cancelledSessions.current.add(threadId);
      flushStreamBuffer(threadId);
      setProgressBySession((prev) => ({
        ...prev,
        [threadId]: "正在终止当前回答",
      }));
      try {
        await invoke("cancel_prompt", { threadId });
      } catch (error) {
        setLastError(`终止失败：${String(error)}`);
      } finally {
        setMessages(threadId, (prev) => {
          const withTools = finalizeOpenTools(prev);
          const last = withTools[withTools.length - 1];
          if (last?.role === "assistant" && last.status === "streaming") {
            const content = last.content.trim()
              ? `${last.content}\n\n（已终止）`
              : "（已终止）";
            return [
              ...withTools.slice(0, -1),
              { ...last, content, status: "completed" },
            ];
          }
          return [
            ...withTools,
            {
              id: crypto.randomUUID(),
              role: "system",
              content: "已终止当前回答",
              status: "completed",
              kind: "error",
            },
          ];
        });
        setSessionBusy(threadId, false);
        setProgressBySession((prev) => {
          const next = { ...prev };
          delete next[threadId];
          return next;
        });
      }
    },
    [busyBySession, setMessages, setSessionBusy, flushStreamBuffer],
  );

  const saveSettings = useCallback(async (next: AppSettings) => {
    const saved = await invoke<AppSettings>("update_runtime_settings", {
      settings: next,
    });
    setSettings(normalizeSettings(saved ?? next));
  }, []);

  const sendMessage = useCallback(
    async (
      threadId: string,
      text: string,
      attachments: ChatAttachment[] = [],
      history: ChatMessage[] = [],
      agentText?: string,
    ) => {
      const trimmed = text.trim();
      const promptText = (agentText ?? text).trim();
      if (!threadId || (!trimmed && attachments.length === 0)) return false;
      streamMsgIds.current.set(threadId, null);
      streamBuffers.current.set(threadId, "");
      const pendingTimer = streamFlushTimers.current.get(threadId);
      if (pendingTimer != null) {
        window.clearTimeout(pendingTimer);
        streamFlushTimers.current.delete(threadId);
      }
      const assistantId = crypto.randomUUID();
      streamMsgIds.current.set(threadId, assistantId);
      setProgressBySession((prev) => ({
        ...prev,
        [threadId]: attachments.some(
          (attachment) =>
            attachment.mimeType ===
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
          ? "正在准备 Excel 表格内容"
          : attachments.length > 0
            ? "正在准备附件内容"
            : "正在启动 Agent…",
      }));
      setMessages(threadId, (prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          role: "user",
          content: trimmed,
          status: "completed",
          attachments,
        },
        {
          id: assistantId,
          role: "assistant",
          content: "",
          status: "streaming",
          kind: "text",
        },
      ]);
      setSessionBusy(threadId, true);
      setLastError(null);
      try {
        // 「记住：xxx」写入永久记忆
        const rememberMatch = trimmed.match(
          /(?:^|\n)\s*(?:记住|请记住|永久记住)[:：]\s*(.+)$/m,
        );
        if (rememberMatch?.[1]?.trim()) {
          try {
            await invoke("add_memory", {
              content: rememberMatch[1].trim(),
              source: "chat",
            });
          } catch {
            /* 重复记忆等可忽略 */
          }
        }
        const historyPayload = history
          .filter((m) => m.role === "user" || m.role === "assistant")
          .filter((m) => m.kind !== "tool" && m.kind !== "error" && m.kind !== "plan-confirm")
          .filter((m) => m.content.trim().length > 0)
          .slice(-16)
          .map((m) => ({ role: m.role, content: m.content }));
        await invoke("send_prompt", {
          threadId,
          text: promptText || trimmed,
          attachments,
          history: historyPayload,
        });
        flushStreamBuffer(threadId);
        if (cancelledSessions.current.has(threadId)) {
          return false;
        }
        setMessages(threadId, (prev) => {
          const withTools = finalizeOpenTools(prev);
          // 完成本轮所有仍在 streaming 的助手正文（不只最后一条，避免中途拆开的气泡一直挂着）
          let lastUserIdx = -1;
          for (let i = withTools.length - 1; i >= 0; i -= 1) {
            if (withTools[i].role === "user") {
              lastUserIdx = i;
              break;
            }
          }
          let changed = false;
          const next = withTools.map((m, i) => {
            if (i <= lastUserIdx) return m;
            if (
              m.role === "assistant" &&
              m.status === "streaming" &&
              m.kind !== "tool" &&
              m.kind !== "plan" &&
              m.kind !== "error"
            ) {
              changed = true;
              return { ...m, status: "completed" as const };
            }
            return m;
          });
          // 去掉本轮空占位
          const cleaned = next.filter((m, i) => {
            if (i <= lastUserIdx) return true;
            if (
              m.role === "assistant" &&
              m.kind === "text" &&
              !m.content.trim()
            ) {
              changed = true;
              return false;
            }
            return true;
          });
          // 合并本轮连续且全文相同的助手气泡（历史拆开残留）
          const lastUserInCleaned = cleaned.reduce(
            (acc, m, i) => (m.role === "user" ? i : acc),
            -1,
          );
          const merged: ChatMessage[] = [];
          for (let i = 0; i < cleaned.length; i += 1) {
            const m = cleaned[i];
            const prevMsg = merged[merged.length - 1];
            if (
              i > lastUserInCleaned &&
              prevMsg &&
              m.role === "assistant" &&
              prevMsg.role === "assistant" &&
              m.kind !== "tool" &&
              m.kind !== "plan" &&
              m.kind !== "error" &&
              prevMsg.kind !== "tool" &&
              prevMsg.kind !== "plan" &&
              prevMsg.kind !== "error" &&
              m.content.trim() &&
              m.content.trim() === prevMsg.content.trim()
            ) {
              changed = true;
              continue;
            }
            merged.push(m);
          }
          const last = merged[merged.length - 1];
          if (last?.role === "assistant" && last.content.trim()) {
            const found = extractDiffsFromText(last.content);
            if (found.length) {
              setDiffs((d) => [...found, ...d].slice(0, 50));
            }
          }
          return changed ? merged : withTools;
        });
        // 任务结束后再兜底刷新一次，覆盖非 ACP 直写路径
        if (workspaceRef.current) {
          await refreshTree(workspaceRef.current).catch(() => undefined);
        }
      } catch (error) {
        if (cancelledSessions.current.has(threadId)) {
          return false;
        }
        flushStreamBuffer(threadId);
        const msg = String(error);
        setLastError(msg);
        setMessages(threadId, (prev) => {
          let next = finalizeOpenTools(prev);
          const last = next[next.length - 1];
          if (
            last?.role === "assistant" &&
            last.status === "streaming" &&
            last.kind === "text" &&
            !last.content.trim()
          ) {
            next = next.slice(0, -1);
          } else if (last?.role === "assistant" && last.status === "streaming") {
            next = [...next.slice(0, -1), { ...last, status: "completed" }];
          }
          return [
            ...next,
            {
              id: crypto.randomUUID(),
              role: "system",
              content: msg,
              status: "error",
              kind: "error",
            },
          ];
        });
        return false;
      } finally {
        const wasCancelled = cancelledSessions.current.delete(threadId);
        if (!wasCancelled) {
          setSessionBusy(threadId, false);
          setProgressBySession((prev) => {
            const next = { ...prev };
            delete next[threadId];
            return next;
          });
        }
      }
      return true;
    },
    [setMessages, setSessionBusy, refreshTree, flushStreamBuffer],
  );

  return {
    settings,
    status,
    tree,
    busy,
    busyBySession,
    progressBySession,
    lastError,
    clearError: () => setLastError(null),
    diffs,
    activity,
    openWorkspace,
    reconnect,
    connectDefaultAgent,
    disconnect,
    clearWorkspace,
    saveSettings,
    sendMessage,
    cancelMessage,
    clearSessionBusy,
  };
}
