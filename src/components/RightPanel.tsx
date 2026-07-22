import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import type { ActivityItem, DiffHunk, RightTab } from "../types/codex";
import type { DirectoryTreeNode } from "../types/agent";
import { FileTree } from "./FileTree";
import { TerminalView } from "./TerminalView";

export interface GitChange {
  path: string;
  status: string;
  diff: string;
}

interface RightPanelProps {
  open: boolean;
  tab: RightTab;
  tree: DirectoryTreeNode | null;
  diffs: DiffHunk[];
  gitChanges: GitChange[];
  activity: ActivityItem[];
  workspace?: string | null;
  onTab: (tab: RightTab) => void;
  onClose: () => void;
  onRefreshGit: () => void;
  onOpenFile?: (path: string) => void;
}

export function RightPanel({
  open,
  tab,
  tree,
  diffs,
  gitChanges,
  activity,
  workspace,
  onTab,
  onClose,
  onRefreshGit,
  onOpenFile,
}: RightPanelProps) {
  const [diffCache, setDiffCache] = useState<Record<string, string>>({});
  const [loadingDiff, setLoadingDiff] = useState<string | null>(null);

  useEffect(() => {
    setDiffCache({});
  }, [gitChanges]);

  if (!open) return null;

  async function accept(path: string) {
    await invoke("git_accept_change", { path });
    onRefreshGit();
  }

  async function reject(path: string) {
    await invoke("git_reject_change", { path });
    onRefreshGit();
  }

  async function rejectAll() {
    await invoke("git_reject_all");
    onRefreshGit();
  }

  async function loadDiff(path: string) {
    if (diffCache[path] || loadingDiff === path) return;
    setLoadingDiff(path);
    try {
      const text = await invoke<string>("git_file_diff", { path });
      setDiffCache((prev) => ({ ...prev, [path]: text }));
    } catch (error) {
      setDiffCache((prev) => ({ ...prev, [path]: String(error) }));
    } finally {
      setLoadingDiff(null);
    }
  }

  return (
    <aside className="right-panel">
      <div className="right-head">
        <div className="tabs">
          {(
            [
              ["files", "文件"],
              ["diff", "审阅"],
              ["terminal", "终端"],
              ["activity", "活动"],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              className={tab === id ? "active" : ""}
              onClick={() => onTab(id)}
            >
              {label}
            </button>
          ))}
        </div>
        <button type="button" className="icon-x" onClick={onClose}>
          ×
        </button>
      </div>

      <div className={`right-body ${tab === "terminal" ? "no-pad" : ""}`}>
        {tab === "files" && <FileTree tree={tree} onOpenFile={onOpenFile} />}

        {tab === "diff" && (
          <div className="diff-list">
            <div className="diff-toolbar">
              <button type="button" onClick={onRefreshGit}>
                刷新
              </button>
              <button type="button" className="danger" onClick={() => void rejectAll()}>
                全部拒绝
              </button>
            </div>

            {gitChanges.length === 0 && diffs.length === 0 && (
              <div className="empty-hint">暂无改动。Agent 改文件后点刷新。</div>
            )}

            {gitChanges.map((c) => (
              <details
                key={c.path}
                className="diff-card"
                onToggle={(e) => {
                  if ((e.target as HTMLDetailsElement).open) {
                    void loadDiff(c.path);
                  }
                }}
              >
                <summary>
                  <div className="diff-summary-row">
                    <strong>{c.path}</strong>
                    <span>{c.status}</span>
                  </div>
                </summary>
                <div className="diff-actions">
                  <button type="button" onClick={() => void accept(c.path)}>
                    接受 (git add)
                  </button>
                  <button type="button" className="danger" onClick={() => void reject(c.path)}>
                    拒绝 (还原)
                  </button>
                </div>
                <pre>
                  {diffCache[c.path] ||
                    c.diff ||
                    (loadingDiff === c.path ? "加载 diff 中…" : "展开后加载 diff")}
                </pre>
              </details>
            ))}

            {gitChanges.length === 0 &&
              diffs.map((d) => (
                <details key={d.id} className="diff-card">
                  <summary>
                    <div className="diff-summary-row">
                      <strong>{d.path}</strong>
                      <span>{d.summary}</span>
                    </div>
                  </summary>
                  <pre>{d.content}</pre>
                </details>
              ))}
          </div>
        )}

        {tab === "terminal" && (
          <TerminalView active={open && tab === "terminal"} cwd={workspace} />
        )}

        {tab === "activity" && (
          <div className="activity-list">
            {activity.length === 0 && (
              <div className="empty-hint">工具调用与计划会显示在这里</div>
            )}
            {activity.map((a) => (
              <div key={a.id} className="activity-item">
                {a.text}
              </div>
            ))}
          </div>
        )}
      </div>
    </aside>
  );
}
