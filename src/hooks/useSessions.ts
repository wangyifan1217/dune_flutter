import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { ChatMessage } from "../types/agent";
import type { ThreadSession } from "../types/codex";

function titleFromMessages(messages: ChatMessage[]): string {
  const first = messages.find((m) => m.role === "user");
  if (!first) return "新对话";
  const t = first.content.trim().replace(/\s+/g, " ");
  return t.length > 36 ? `${t.slice(0, 36)}…` : t;
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

export function useSessions() {
  const [sessions, setSessions] = useState<ThreadSession[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const skipFirstSave = useRef(true);

  // 启动时从磁盘加载；若无则迁移 localStorage
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
        setSessions(list);
        setActiveId(data.activeId ?? list[0]?.id ?? null);
      } catch {
        if (cancelled) return;
        const list = loadLocalFallback();
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

  // 持久化到磁盘（永久保存）
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
      // 兜底：仍写 localStorage
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

  const createSession = useCallback(() => {
    const next: ThreadSession = {
      id: crypto.randomUUID(),
      title: "新对话",
      createdAt: Date.now(),
      updatedAt: Date.now(),
      messages: [],
    };
    setSessions((prev) => [next, ...prev]);
    setActiveId(next.id);
    return next.id;
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

  const clearActive = useCallback(() => {
    if (activeId) setMessages(activeId, () => []);
  }, [activeId, setMessages]);

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
    clearActive,
    removeSession,
  };
}
