import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { ChatMessage } from "../types/agent";
import { CHAT_MODE_PREFIX } from "../types/agent";
import type { ThreadSession } from "../types/codex";

function stripModePrefix(content: string): string {
  let text = content.trim();
  for (const prefix of Object.values(CHAT_MODE_PREFIX)) {
    if (prefix && text.startsWith(prefix)) {
      text = text.slice(prefix.length).trim();
      break;
    }
  }
  const legacy = "请先制定实现计划（Plan），列出步骤与风险，确认后再动手改代码：";
  if (text.startsWith(legacy)) {
    text = text.slice(legacy.length).trim();
  }
  return text;
}

function titleFromMessages(messages: ChatMessage[]): string {
  const first = messages.find((m) => m.role === "user");
  if (!first) return "新对话";
  const t = stripModePrefix(first.content).replace(/\s+/g, " ");
  if (!t) return "新对话";
  return t.length > 28 ? `${t.slice(0, 28)}…` : t;
}

function loadLocalFallback(): ThreadSession[] {
  try {
    const raw = localStorage.getItem("nova-desktop.sessions.v1");
    if (!raw) return [];
    const parsed = JSON.parse(raw) as ThreadSession[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function workspaceGroupName(workspace?: string | null): string {
  if (!workspace) return "local";
  const name = workspace.split(/[/\\]/).filter(Boolean).pop();
  return name || "local";
}

export function useSessions() {
  const [sessions, setSessions] = useState<ThreadSession[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const skipFirstSave = useRef(true);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const data = await invoke<{
          sessions: ThreadSession[];
          activeId?: string | null;
        }>("load_sessions");
        if (cancelled) return;
        let list = Array.isArray(data.sessions) ? data.sessions : [];
        if (list.length === 0) {
          list = loadLocalFallback();
        }
        list = list.map((s) => ({
          ...s,
          workspace:
            (!s.messages || s.messages.length === 0) &&
            (!s.title || s.title === "新对话")
              ? null
              : s.workspace,
          title: titleFromMessages(s.messages),
        }));
        setSessions(list);
        setActiveId(data.activeId ?? list[0]?.id ?? null);
      } catch {
        if (cancelled) return;
        const list = loadLocalFallback().map((s) => ({
          ...s,
          workspace:
            (!s.messages || s.messages.length === 0) &&
            (!s.title || s.title === "新对话")
              ? null
              : s.workspace,
          title: titleFromMessages(s.messages),
        }));
        setSessions(list);
        setActiveId(list[0]?.id ?? null);
      } finally {
        if (!cancelled) setReady(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!ready) return;
    if (skipFirstSave.current) {
      skipFirstSave.current = false;
      return;
    }
    void invoke("save_sessions", {
      sessions,
      activeId,
    }).catch(() => {
      try {
        localStorage.setItem("nova-desktop.sessions.v1", JSON.stringify(sessions));
      } catch {
        /* ignore */
      }
    });
  }, [sessions, activeId, ready]);

  const active = useMemo(
    () => sessions.find((s) => s.id === activeId) ?? null,
    [sessions, activeId],
  );

  const createSession = useCallback((workspace?: string | null) => {
    // 已有空白会话时复用，避免无限点「新建」堆一堆空对话
    let reusedId: string | null = null;
    setSessions((prev) => {
      const empties = prev.filter(
        (s) =>
          (!s.messages || s.messages.length === 0) &&
          (!s.title || s.title === "新对话"),
      );
      if (empties.length > 0) {
        const keep = empties[0];
        reusedId = keep.id;
        const ws =
          workspace !== undefined ? workspace ?? null : keep.workspace ?? null;
        const dropIds = new Set(empties.slice(1).map((s) => s.id));
        return prev
          .filter((s) => !dropIds.has(s.id))
          .map((s) =>
            s.id === keep.id
              ? { ...s, workspace: ws, updatedAt: Date.now() }
              : s,
          );
      }
      const next: ThreadSession = {
        id: crypto.randomUUID(),
        title: "新对话",
        createdAt: Date.now(),
        updatedAt: Date.now(),
        messages: [],
        workspace: workspace ?? null,
        chatMode: "agent",
      };
      reusedId = next.id;
      return [next, ...prev];
    });
    if (reusedId) setActiveId(reusedId);
    return reusedId ?? "";
  }, []);

  const setChatMode = useCallback((sessionId: string, chatMode: "agent" | "plan" | "ask") => {
    setSessions((prev) =>
      prev.map((s) =>
        s.id === sessionId ? { ...s, chatMode, updatedAt: Date.now() } : s,
      ),
    );
  }, []);

  const setMessages = useCallback(
    (sessionId: string, updater: (prev: ChatMessage[]) => ChatMessage[]) => {
      setSessions((prev) =>
        prev.map((s) => {
          if (s.id !== sessionId) return s;
          const messages = updater(s.messages);
          return {
            ...s,
            messages,
            title: titleFromMessages(messages),
            updatedAt: Date.now(),
          };
        }),
      );
    },
    [],
  );

  const bindSessionWorkspace = useCallback(
    (sessionId: string, workspace: string | null) => {
      setSessions((prev) =>
        prev.map((s) =>
          s.id === sessionId ? { ...s, workspace, updatedAt: Date.now() } : s,
        ),
      );
    },
    [],
  );

  const clearActive = useCallback(() => {
    if (activeId) setMessages(activeId, () => []);
  }, [activeId, setMessages]);

  /** 删除 messageId 及其之后的所有消息（用于编辑重发 / 按轮次重试）。 */
  const truncateFrom = useCallback((sessionId: string, messageId: string) => {
    setSessions((prev) =>
      prev.map((s) => {
        if (s.id !== sessionId) return s;
        const idx = s.messages.findIndex((m) => m.id === messageId);
        if (idx < 0) return s;
        const messages = s.messages.slice(0, idx);
        return {
          ...s,
          messages,
          title: titleFromMessages(messages),
          updatedAt: Date.now(),
        };
      }),
    );
  }, []);

  const removeSession = useCallback(
    (id: string) => {
      setSessions((prev) => {
        const next = prev.filter((s) => s.id !== id);
        if (activeId === id) {
          setActiveId(next[0]?.id ?? null);
        }
        return next;
      });
    },
    [activeId],
  );

  return {
    sessions,
    activeId,
    active,
    ready,
    setActiveId,
    createSession,
    setMessages,
    setChatMode,
    bindSessionWorkspace,
    truncateFrom,
    clearActive,
    removeSession,
  };
}
