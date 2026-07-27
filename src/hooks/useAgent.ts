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
import { normalizeSettings } from "../types/agent";
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
        const inner = row.content as { text?: string };
        return inner.text ?? "";
      }
      if (typeof row.type === "string" && row.type === "diff") {
        try {
          return JSON.stringify(row, null, 2);
        } catch {
          return "";
        }
      }
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
    const title =
      (typeof update.title === "string" && update.title) ||
      (typeof update.kind === "string" && update.kind) ||
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
    return { kind: "tool", toolCallId, title, status, output: output || undefined };
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

function upsertToolMessage(
  prev: ChatMessage[],
  part: Extract<StreamPart, { kind: "tool" }>,
): ChatMessage[] {
  const idx = prev.findIndex(
    (m) => m.kind === "tool" && m.toolCallId === part.toolCallId,
  );
  const title = localizeToolText(part.title);
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
    };
    const copy = [...prev];
    copy[idx] = next;
    return copy;
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
}

export function useAgent({ activeSessionId, setMessages }: Options) {
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
  const cancelledSessions = useRef(new Set<string>());
  const busy = controlBusy || Boolean(activeSessionId && busyBySession[activeSessionId]);

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

      const u2 = await listen<SessionUpdateEvent>("agent://session-update", (event) => {
        if (!alive) return;
        const threadId = event.payload.threadId;
        if (!threadId) return;
        const part = parseUpdate(event.payload.update);
        if (!part) return;
        if (part.kind === "tool") {
          setProgressBySession((prev) => ({
            ...prev,
            [threadId]: `正在执行工具：${localizeToolText(part.title)}`,
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
          setProgressBySession((prev) => ({
            ...prev,
            [threadId]: "模型正在生成回复",
          }));
        }

        if (part.kind === "text") {
          setMessages(threadId, (prev) => {
            const last = prev[prev.length - 1];
            const streamMsgId = streamMsgIds.current.get(threadId);
            const sameStream =
              last?.role === "assistant" &&
              last.status === "streaming" &&
              last.kind !== "plan" &&
              last.kind !== "tool" &&
              (!part.messageId ||
                !streamMsgId ||
                part.messageId === streamMsgId);
            if (part.messageId) streamMsgIds.current.set(threadId, part.messageId);
            if (sameStream && last) {
              return [
                ...prev.slice(0, -1),
                { ...last, content: last.content + part.text },
              ];
            }
            return [
              ...prev,
              {
                id: part.messageId ?? crypto.randomUUID(),
                role: "assistant",
                content: part.text,
                status: "streaming",
                kind: "text",
              },
            ];
          });
          return;
        }

        if (part.kind === "plan") {
          const entries = part.text
            .split("\n")
            .map((line) => line.replace(/^•\s*/, "").trim())
            .filter(Boolean);
          setMessages(threadId, (prev) => {
            const last = prev[prev.length - 1];
            if (last?.kind === "plan" && last.status === "streaming") {
              return [
                ...prev.slice(0, -1),
                {
                  ...last,
                  content: part.text,
                  planEntries: entries,
                  status: "completed",
                },
              ];
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
  }, [refreshSettings, refreshStatus, refreshTree, setMessages]);

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
    [busyBySession, setMessages, setSessionBusy],
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
    ) => {
      const trimmed = text.trim();
      if (!threadId || (!trimmed && attachments.length === 0)) return false;
      streamMsgIds.current.set(threadId, null);
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
          .filter((m) => m.kind !== "tool" && m.kind !== "error")
          .filter((m) => m.content.trim().length > 0)
          .slice(-16)
          .map((m) => ({ role: m.role, content: m.content }));
        await invoke("send_prompt", {
          threadId,
          text: trimmed,
          attachments,
          history: historyPayload,
        });
        if (cancelledSessions.current.has(threadId)) {
          return false;
        }
        setMessages(threadId, (prev) => {
          const withTools = finalizeOpenTools(prev);
          const last = withTools[withTools.length - 1];
          if (
            last?.role === "assistant" &&
            last.status === "streaming" &&
            last.kind !== "tool"
          ) {
            const completed = { ...last, status: "completed" as const };
            const found = extractDiffsFromText(completed.content);
            if (found.length) {
              setDiffs((d) => [...found, ...d].slice(0, 50));
            }
            return [...withTools.slice(0, -1), completed];
          }
          return withTools;
        });
        // 任务结束后再兜底刷新一次，覆盖非 ACP 直写路径
        if (workspaceRef.current) {
          await refreshTree(workspaceRef.current).catch(() => undefined);
        }
      } catch (error) {
        if (cancelledSessions.current.has(threadId)) {
          return false;
        }
        const msg = String(error);
        setLastError(msg);
        setMessages(threadId, (prev) => [
          ...finalizeOpenTools(prev),
          {
            id: crypto.randomUUID(),
            role: "system",
            content: msg,
            status: "error",
            kind: "error",
          },
        ]);
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
    [setMessages, setSessionBusy, refreshTree],
  );

  return {
    settings,
    status,
    tree,
    busy,
    busyBySession,
    progressBySession,
    lastError,
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
