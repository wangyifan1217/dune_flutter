import { invoke } from "@tauri-apps/api/core";
import { useEffect, useRef, useState, type ComponentType, type PointerEvent as ReactPointerEvent } from "react";
import type { ActivityItem, DiffHunk, RightTab } from "../types/codex";
import type { DirectoryTreeNode } from "../types/agent";
import { FileTree } from "./FileTree";
import {
  IconActivity,
  IconDiff,
  IconEye,
  IconFolder,
  IconTerminal,
  IconX,
} from "./Icons";
import { PreviewPane } from "./PreviewPane";
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
  gitError?: string | null;
  previewPath?: string | null;
  onTab: (tab: RightTab) => void;
  onClose: () => void;
  onRefreshGit: () => void;
  onOpenFile?: (path: string) => void;
  onClearPreview?: () => void;
  onOpenExternal?: (path: string) => void;
  onPreviewError?: (message: string) => void;
}

type RailIcon = ComponentType<{ size?: number }>;

const ICON_TABS: Array<{ id: RightTab; label: string; Icon: RailIcon }> = [
  { id: "preview", label: "预览", Icon: IconEye },
  { id: "files", label: "文件", Icon: IconFolder },
  { id: "diff", label: "变更", Icon: IconDiff },
  { id: "terminal", label: "终端", Icon: IconTerminal },
  { id: "activity", label: "活动", Icon: IconActivity },
];

const WIDTH_KEY = "nova.rightPanelWidth";
const WIDTH_MIN = 240;
const WIDTH_DEFAULT = 288;
const WIDTH_DEFAULT_PREVIEW = 560;

function clampWidth(px: number) {
  const max = Math.max(WIDTH_MIN, Math.floor(window.innerWidth * 0.7));
  return Math.min(max, Math.max(WIDTH_MIN, Math.round(px)));
}

function readStoredWidth(): number | null {
  try {
    const raw = localStorage.getItem(WIDTH_KEY);
    if (!raw) return null;
    const n = Number(raw);
    return Number.isFinite(n) ? clampWidth(n) : null;
  } catch {
    return null;
  }
}

export function RightPanel({
  open,
  tab,
  tree,
  diffs,
  gitChanges,
  activity,
  workspace,
  gitError,
  previewPath = null,
  onTab,
  onClose,
  onRefreshGit,
  onOpenFile,
  onClearPreview,
  onOpenExternal,
  onPreviewError,
}: RightPanelProps) {
  const [diffCache, setDiffCache] = useState<Record<string, string>>({});
  const [loadingDiff, setLoadingDiff] = useState<string | null>(null);
  const [panelWidth, setPanelWidth] = useState<number | null>(() => readStoredWidth());
  const [resizing, setResizing] = useState(false);
  const dragRef = useRef<{ startX: number; startW: number } | null>(null);

  useEffect(() => {
    setDiffCache({});
  }, [gitChanges]);

  const effectiveWidth =
    panelWidth ?? (tab === "preview" ? WIDTH_DEFAULT_PREVIEW : WIDTH_DEFAULT);

  function onResizePointerDown(e: ReactPointerEvent<HTMLDivElement>) {
    e.preventDefault();
    dragRef.current = { startX: e.clientX, startW: effectiveWidth };
    setResizing(true);
    e.currentTarget.setPointerCapture(e.pointerId);
  }

  function onResizePointerMove(e: ReactPointerEvent<HTMLDivElement>) {
    if (!dragRef.current) return;
    // 手柄在面板左侧，向左拖 = 变宽
    const next = clampWidth(dragRef.current.startW + (dragRef.current.startX - e.clientX));
    setPanelWidth(next);
  }

  function onResizePointerUp(e: ReactPointerEvent<HTMLDivElement>) {
    if (!dragRef.current) return;
    dragRef.current = null;
    setResizing(false);
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch {
      /* already released */
    }
    setPanelWidth((w) => {
      const saved = w ?? effectiveWidth;
      try {
        localStorage.setItem(WIDTH_KEY, String(saved));
      } catch {
        /* ignore */
      }
      return saved;
    });
  }

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

  const headLabel =
    tab === "diff"
      ? "本地变更"
      : tab === "preview"
        ? "预览"
        : ICON_TABS.find((t) => t.id === tab)?.label ?? tab;

  return (
    <div className={`right-shell ${open ? "open" : ""} ${resizing ? "resizing" : ""}`}>
      <nav className="right-icon-rail" aria-label="右侧面板">
        {ICON_TABS.map((item) => (
          <button
            key={item.id}
            type="button"
            className={`rail-icon ${open && tab === item.id ? "active" : ""}`}
            title={item.label}
            onClick={() => {
              if (open && tab === item.id) onClose();
              else onTab(item.id);
            }}
          >
            <item.Icon size={17} />
          </button>
        ))}
      </nav>

      {open ? (
        <aside
          className={`right-panel ${resizing ? "resizing" : ""}`}
          style={{ width: effectiveWidth }}
        >
          <div
            className="right-resize-handle"
            role="separator"
            aria-orientation="vertical"
            aria-label="拖拽调整右侧面板宽度"
            title="拖拽调整宽度"
            onPointerDown={onResizePointerDown}
            onPointerMove={onResizePointerMove}
            onPointerUp={onResizePointerUp}
            onPointerCancel={onResizePointerUp}
          />
          <div className="right-head">
            <div className="right-head-title">
              <span className="right-local-label">{headLabel}</span>
            </div>
            <button type="button" className="icon-x" onClick={onClose} aria-label="关闭">
              <IconX size={16} />
            </button>
          </div>

          <div
            className={`right-body ${tab === "terminal" || tab === "preview" ? "no-pad" : ""}`}
          >
            {tab === "preview" && (
              <PreviewPane
                path={previewPath}
                onClear={() => onClearPreview?.()}
                onOpenExternal={(p) => onOpenExternal?.(p)}
                onError={onPreviewError}
              />
            )}

            {/* 保持挂载，避免切到预览再回来时丢失展开/懒加载状态 */}
            <div
              className="right-tab-pane"
              hidden={tab !== "files"}
              aria-hidden={tab !== "files"}
            >
              <FileTree
                tree={tree}
                selectedPath={previewPath}
                onOpenFile={onOpenFile}
              />
            </div>

            {tab === "diff" && (
              <div className="diff-list local-changes">
                <div className="diff-toolbar">
                  <button type="button" onClick={onRefreshGit}>
                    刷新
                  </button>
                  <button
                    type="button"
                    className="danger"
                    onClick={() => void rejectAll()}
                    disabled={gitChanges.length === 0}
                  >
                    全部丢弃
                  </button>
                </div>

                {gitError ? (
                  <div className="local-empty-state failed">
                    <div className="local-empty-icon">
                      <IconFolder size={28} />
                    </div>
                    <div className="local-empty-title">无法加载变更</div>
                    <p>{gitError}</p>
                  </div>
                ) : gitChanges.length === 0 && diffs.length === 0 ? (
                  <div className="local-empty-state">
                    <div className="local-empty-icon">
                      <IconFolder size={28} />
                    </div>
                    <div className="local-empty-title">暂无未提交的变更</div>
                  </div>
                ) : null}

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
                        暂存
                      </button>
                      <button
                        type="button"
                        className="danger"
                        onClick={() => void reject(c.path)}
                      >
                        丢弃改动
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
                  <div className="empty-hint">工具调用会显示在这里</div>
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
      ) : null}
    </div>
  );
}
