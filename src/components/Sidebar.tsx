import { useEffect, useMemo, useState } from "react";
import type { ThreadSession } from "../types/codex";
import { workspaceGroupName } from "../hooks/useSessions";
import {
  IconChevronRight,
  IconLogout,
  IconPlus,
  IconSearch,
  IconSettings,
  IconX,
} from "./Icons";

interface SidebarProps {
  sessions: ThreadSession[];
  activeId: string | null;
  busyBySession: Record<string, boolean>;
  error?: string | null;
  authUser?: string;
  settingsOpen?: boolean;
  onNew: () => void;
  onOpenSettings: () => void;
  onLogout?: () => void;
  onSelectSession: (id: string) => void;
  onRemoveSession: (id: string) => void;
  onDismissError?: () => void;
}

function displayGroupName(key: string) {
  return key === "local" ? "本地" : key;
}

export function Sidebar({
  sessions,
  activeId,
  busyBySession,
  error,
  authUser,
  settingsOpen,
  onNew,
  onOpenSettings,
  onLogout,
  onSelectSession,
  onRemoveSession,
  onDismissError,
}: SidebarProps) {
  const [query, setQuery] = useState("");
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  const groups = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = sessions.filter((s) =>
      q ? s.title.toLowerCase().includes(q) : true,
    );
    const map = new Map<string, ThreadSession[]>();
    for (const s of filtered) {
      const key = workspaceGroupName(s.workspace);
      const list = map.get(key) ?? [];
      list.push(s);
      map.set(key, list);
    }
    // 组内、组间都按最近更新置顶
    for (const list of map.values()) {
      list.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
    }
    return Array.from(map.entries()).sort(([a, listA], [b, listB]) => {
      if (a === "local" && b !== "local") return 1;
      if (b === "local" && a !== "local") return -1;
      const ta = listA[0]?.updatedAt ?? 0;
      const tb = listB[0]?.updatedAt ?? 0;
      if (tb !== ta) return tb - ta;
      return a.localeCompare(b, "zh-CN");
    });
  }, [sessions, query]);

  const initials = (authUser || "N").trim().slice(0, 1).toUpperCase();

  useEffect(() => {
    if (!activeId) return;
    const safe =
      typeof CSS !== "undefined" && typeof CSS.escape === "function"
        ? CSS.escape(activeId)
        : activeId.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    const el = document.querySelector(`[data-session-id="${safe}"]`);
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [activeId, groups]);

  return (
    <aside className="sidebar agents-sidebar">
      <div className="sidebar-top-row">
        <div className="sidebar-search-wrap">
          <span className="sidebar-search-ico" aria-hidden>
            <IconSearch size={15} />
          </span>
          <input
            className="sidebar-search"
            value={query}
            placeholder="搜索对话"
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
      </div>

      <button type="button" className="new-agent-btn" onClick={onNew}>
        <span className="new-agent-plus" aria-hidden>
          <IconPlus size={14} />
        </span>
        <span className="new-agent-label">新建对话</span>
        <kbd>Ctrl+N</kbd>
      </button>

      <div className="sidebar-main">
        <div className="agent-groups">
          {groups.length === 0 && <div className="empty-hint">还没有对话</div>}
          {groups.map(([group, list]) => {
            const isCollapsed = collapsed[group] ?? false;
            return (
              <div key={group} className="agent-group">
                <button
                  type="button"
                  className="agent-group-head"
                  onClick={() =>
                    setCollapsed((prev) => ({ ...prev, [group]: !isCollapsed }))
                  }
                >
                  <span className={`chev ${isCollapsed ? "" : "open"}`}>
                    <IconChevronRight size={14} />
                  </span>
                  <span className="agent-group-name">{displayGroupName(group)}</span>
                  <span className="agent-group-count">{list.length}</span>
                </button>
                {!isCollapsed && (
                  <div className="thread-list">
                    {list.map((s) => {
                      const running = Boolean(busyBySession[s.id]);
                      return (
                        <button
                          key={s.id}
                          type="button"
                          data-session-id={s.id}
                          className={`thread-item ${s.id === activeId ? "active" : ""}`}
                          onClick={() => onSelectSession(s.id)}
                        >
                          {running ? <span className="thread-dot live" /> : null}
                          <span className="thread-item-title">{s.title}</span>
                          <span
                            className="thread-item-x"
                            onClick={(e) => {
                              e.stopPropagation();
                              onRemoveSession(s.id);
                            }}
                          >
                            <IconX size={14} />
                          </span>
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {error ? (
        <div className="error-box" role="alert">
          <span className="error-box-text">{error}</span>
          {onDismissError ? (
            <button
              type="button"
              className="error-box-close"
              aria-label="关闭错误提示"
              title="关闭"
              onClick={onDismissError}
            >
              <IconX size={14} />
            </button>
          ) : null}
        </div>
      ) : null}

      <div className="sidebar-profile">
        <div className="profile-avatar" aria-hidden>
          {initials}
        </div>
        <div className="profile-meta">
          <div className="profile-name" title={authUser}>
            {authUser || "Nova 用户"}
          </div>
          <div className="profile-plan">已登录</div>
        </div>
        <div className="profile-actions">
          <button
            type="button"
            className={`icon-ghost ${settingsOpen ? "active" : ""}`}
            title="设置"
            onClick={onOpenSettings}
          >
            <IconSettings size={16} />
          </button>
          {onLogout ? (
            <button type="button" className="icon-ghost" title="退出登录" onClick={onLogout}>
              <IconLogout size={16} />
            </button>
          ) : null}
        </div>
      </div>
    </aside>
  );
}
