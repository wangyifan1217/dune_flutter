import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useCallback, useEffect, useRef, useState } from "react";
import { Composer } from "./components/Composer";
import { FilePreview } from "./components/FilePreview";
import { McpSettingsModal } from "./components/McpSettingsModal";
import {
  PermissionBanner,
  type PermissionRequest,
} from "./components/PermissionBanner";
import { RightPanel, type GitChange } from "./components/RightPanel";
import { Sidebar } from "./components/Sidebar";
import { Thread } from "./components/Thread";
import { useAgent } from "./hooks/useAgent";
import { useSessions } from "./hooks/useSessions";
import type { ChatAttachment } from "./types/agent";
import type { LeftMode, RightTab } from "./types/codex";
import "./App.css";

const MAX_BINARY_BYTES = 10 * 1024 * 1024;
const MAX_TEXT_FILE_BYTES = 512 * 1024;
const TEXT_FILE_EXTENSIONS = new Set([
  "txt", "md", "json", "csv", "ts", "tsx", "js", "jsx", "css", "html",
  "xml", "yaml", "yml", "toml", "rs", "py", "java", "go", "c", "cpp",
  "h", "hpp", "sql", "sh",
]);

interface NativeDroppedFile {
  name: string;
  mimeType: string;
  size: number;
  encoding: "base64" | "utf8";
  data: string;
}

function isSupportedTextFile(file: File) {
  const extension = file.name.split(".").pop()?.toLowerCase() ?? "";
  return file.type.startsWith("text/") || TEXT_FILE_EXTENSIONS.has(extension);
}

async function toAttachment(file: File): Promise<ChatAttachment> {
  const isText = isSupportedTextFile(file);
  const limit = isText ? MAX_TEXT_FILE_BYTES : MAX_BINARY_BYTES;
  if (file.size > limit) {
    throw new Error(
      `${file.name} 超过${isText ? "文本文件 512 KB" : "文件 10 MB"}限制。`,
    );
  }

  const data = isText
    ? await file.text()
    : await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () => reject(new Error(`无法读取 ${file.name}`));
        reader.onload = () => {
          const [, encoded = ""] = String(reader.result).split(",", 2);
          resolve(encoded);
        };
        reader.readAsDataURL(file);
      });
  return {
    id: crypto.randomUUID(),
    name: file.name,
    mimeType: file.type || (isText ? "text/plain" : "application/octet-stream"),
    size: file.size,
    encoding: isText ? "utf8" : "base64",
    data,
  };
}

function App() {
  const {
    sessions,
    activeId,
    active,
    setActiveId,
    createSession,
    setMessages,
    removeSession,
    ready: sessionsReady,
  } = useSessions();

  const {
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
  } = useAgent({
    activeSessionId: activeId,
    setMessages,
  });

  const [leftMode, setLeftMode] = useState<LeftMode>("threads");
  const [rightOpen, setRightOpen] = useState(false);
  const [rightTab, setRightTab] = useState<RightTab>("diff");
  const [mcpOpen, setMcpOpen] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);
  const [gitChanges, setGitChanges] = useState<GitChange[]>([]);
  const [permission, setPermission] = useState<PermissionRequest | null>(null);
  const [preview, setPreview] = useState<{ path: string; content: string } | null>(
    null,
  );
  const [attachments, setAttachments] = useState<ChatAttachment[]>([]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const restoredWorkspace = useRef(false);

  const refreshGit = useCallback(async () => {
    if (!status.workspace) {
      setGitChanges([]);
      return;
    }
    try {
      const list = await invoke<GitChange[]>("git_list_changes");
      setGitChanges(list);
    } catch {
      setGitChanges([]);
    }
  }, [status.workspace]);

  useEffect(() => {
    if (!sessionsReady) return;
    if (!activeId) createSession();
  }, [activeId, createSession, sessionsReady]);

  const addDroppedPaths = useCallback(async (paths: string[]) => {
    try {
      const files = await invoke<NativeDroppedFile[]>("read_dropped_files", { paths });
      setAttachments((current) => [
        ...current,
        ...files.map((file) => ({ ...file, id: crypto.randomUUID() })),
      ]);
    } catch (error) {
      setLocalError(`无法添加拖入的文件：${String(error)}`);
    }
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .onDragDropEvent((event) => {
        if (event.payload.type === "drop") {
          void addDroppedPaths(event.payload.paths);
        }
      })
      .then((cleanup) => {
        unlisten = cleanup;
      })
      .catch(() => undefined);
    return () => unlisten?.();
  }, [addDroppedPaths]);

  useEffect(() => {
    if (restoredWorkspace.current) return;
    restoredWorkspace.current = true;
    const path = localStorage.getItem("nova-desktop.last-workspace");
    if (!path) return;
    void openWorkspace(path).catch(() => {
      localStorage.removeItem("nova-desktop.last-workspace");
    });
  }, [openWorkspace]);

  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [active?.messages, busy]);

  useEffect(() => {
    void refreshGit();
  }, [refreshGit, busy, status.connected]);

  useEffect(() => {
    const unsubs: Array<() => void> = [];
    void listen<{
      id?: number | string;
      title?: string;
      params?: Record<string, unknown>;
    }>("agent://permission-request", (event) => {
      const id = event.payload.id;
      if (id === undefined || id === null) return;
      const params = event.payload.params ?? {};
      const toolCall = params.toolCall as { title?: string } | undefined;
      setPermission({
        id,
        title: event.payload.title ?? toolCall?.title ?? "工具权限请求",
        detail: JSON.stringify(params, null, 2),
      });
    }).then((u) => unsubs.push(u));
    return () => unsubs.forEach((u) => u());
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "n") {
        e.preventDefault();
        createSession();
        setLeftMode("threads");
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "o") {
        e.preventDefault();
        void pickFolder();
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "`") {
        e.preventDefault();
        setRightOpen(true);
        setRightTab("terminal");
      }
      // Ctrl+V 全局后备：自动聚焦输入框以确保粘贴生效
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "v") {
        // 如果当前焦点不在输入框内，强制聚焦到 textarea
        const activeEl = document.activeElement;
        const isTextarea =
          activeEl?.tagName === "TEXTAREA" ||
          (activeEl as HTMLElement)?.isContentEditable;
        if (!isTextarea) {
          e.preventDefault();
          const textarea = document.querySelector(
            ".composer-card textarea",
          ) as HTMLTextAreaElement | null;
          if (textarea) {
            textarea.focus();
            // 延迟一帧让 focus 生效，然后由 textarea 的 onPaste 处理
            requestAnimationFrame(() => {
              // 通过 execCommand 触发粘贴（对 WebView2 兼容性更好）
              document.execCommand("paste");
            });
          }
        }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [createSession]);

  async function openFile(path: string) {
    setLocalError(null);
    try {
      const content = await invoke<string>("read_workspace_file", { path });
      setPreview({ path, content });
      setLeftMode("threads");
    } catch (error) {
      setLocalError(`无法打开文件：${String(error)}`);
      setLeftMode("files");
    }
  }

  async function pickFolder() {
    setLocalError(null);
    try {
      const selected = await open({
        directory: true,
        multiple: false,
        title: "选择项目文件夹",
      });
      const path = Array.isArray(selected) ? selected[0] : selected;
      if (!path || typeof path !== "string") return;
      await openWorkspace(path);
      localStorage.setItem("nova-desktop.last-workspace", path);
      setRightOpen(true);
      setRightTab("files");
      // Git 刷新放到后台，避免选完项目再卡一轮
      void refreshGit();
    } catch (error) {
      setLocalError(String(error));
    }
  }

  const projectName =
    status.workspace?.split(/[/\\]/).filter(Boolean).pop() ?? "未打开项目";
  const displayError = localError ?? lastError;
  const askApproval = !(settings?.autoApprovePermissions ?? true);
  const isEmpty = (active?.messages.length ?? 0) === 0;

  return (
    <div className="codex-app">
      <Sidebar
        mode={leftMode}
        sessions={sessions}
        activeId={activeId}
        busyBySession={busyBySession}
        tree={tree}
        status={status}
        settings={settings}
        busy={busy}
        error={displayError}
        rightOpen={rightOpen}
        mcpOpen={mcpOpen}
        onMode={setLeftMode}
        onNew={() => {
          createSession();
          setLeftMode("threads");
        }}
        onToggleRight={() => setRightOpen((v) => !v)}
        onOpenMcp={() => setMcpOpen(true)}
        onSelectSession={setActiveId}
        onRemoveSession={removeSession}
        onOpenFolder={() => void pickFolder()}
        onShowProjectFiles={() => {
          setRightOpen(true);
          setRightTab("files");
        }}
        onOpenFile={(path) => void openFile(path)}
        onReconnect={() => void reconnect()}
        onDisconnect={() => void disconnect()}
        onSaveSettings={saveSettings}
      />

      <main className="main-stage">
        {preview ? (
          <FilePreview
            path={preview.path}
            content={preview.content}
            onBack={() => setPreview(null)}
          />
        ) : (
          <>
            <div className="main-body">
              <PermissionBanner
                request={permission}
                onDone={() => setPermission(null)}
                onError={(msg) => setLocalError(msg)}
              />

              <div className={`thread-scroll ${isEmpty ? "empty" : ""}`} ref={scrollRef}>
                <Thread
                  messages={active?.messages ?? []}
                  busy={busy}
                  progress={activeId ? progressBySession[activeId] : undefined}
                />
              </div>
            </div>

            <Composer
              busy={busy}
              connected={status.connected}
              projectName={projectName}
              modelId={settings?.modelId ?? ""}
              models={settings?.models ?? []}
              askApproval={askApproval}
              empty={isEmpty}
              onAskApprovalChange={(ask) => {
                if (!settings) return;
                void saveSettings({
                  ...settings,
                  autoApprovePermissions: !ask,
                });
              }}
              onModelChange={(modelId) => {
                if (!settings || modelId === settings.modelId) return;
                if (Object.values(busyBySession).some(Boolean)) {
                  setLocalError("有任务正在执行，请等待完成后再切换模型。");
                  return;
                }
                void (async () => {
                  await saveSettings({ ...settings, modelId });
                  // 模型由 Agent 启动环境读取。必须销毁已有 ACP 会话，
                  // 否则 Agent 可能继续沿用旧模型。
                  await disconnect();
                  if (status.workspace) {
                    await reconnect();
                  } else if (activeId) {
                    await connectDefaultAgent(activeId);
                  }
                })().catch((error) => setLocalError(`切换模型失败：${String(error)}`));
              }}
              onManageModels={() => setLeftMode("settings")}
              onPickProject={() => void pickFolder()}
              onClearProject={() => {
                void clearWorkspace()
                  .then(() => {
                    localStorage.removeItem("nova-desktop.last-workspace");
                    setLeftMode("threads");
                  })
                  .catch(() => undefined);
              }}
              attachments={attachments}
              onAddFiles={(files) => {
                void Promise.all(files.map(toAttachment))
                  .then((next) => setAttachments((current) => [...current, ...next]))
                  .catch((error) => setLocalError(String(error)));
              }}
              onRemoveAttachment={(id) =>
                setAttachments((current) => current.filter((item) => item.id !== id))
              }
              onSend={async (text, pendingAttachments) => {
                if (!activeId) return;
                if (!status.connected && !(await connectDefaultAgent(activeId))) return;
                const history = active?.messages ?? [];
                const sent = await sendMessage(
                  activeId,
                  text,
                  pendingAttachments,
                  history,
                );
                if (sent) setAttachments([]);
                await refreshGit();
              }}
              onStop={() => {
                if (!activeId) return;
                void cancelMessage(activeId);
              }}
            />
          </>
        )}
      </main>

      <RightPanel
        open={rightOpen}
        tab={rightTab}
        tree={tree}
        diffs={diffs}
        gitChanges={gitChanges}
        activity={activity}
        workspace={status.workspace}
        onTab={setRightTab}
        onClose={() => setRightOpen(false)}
        onRefreshGit={() => void refreshGit()}
        onOpenFile={(path) => void openFile(path)}
      />

      <McpSettingsModal
        open={mcpOpen}
        servers={settings?.mcpServers ?? []}
        onClose={() => setMcpOpen(false)}
        onSave={(mcpServers) => {
          if (!settings) return;
          void saveSettings({ ...settings, mcpServers });
        }}
      />
    </div>
  );
}

export default App;
