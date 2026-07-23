import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useCallback, useEffect, useRef, useState } from "react";
import { Composer } from "./components/Composer";
import { FilePreview } from "./components/FilePreview";
import { McpSettingsModal } from "./components/McpSettingsModal";
import { SkillsModal } from "./components/SkillsModal";
import {
  PermissionBanner,
  type PermissionRequest,
} from "./components/PermissionBanner";
import { RightPanel, type GitChange } from "./components/RightPanel";
import { Sidebar } from "./components/Sidebar";
import { Thread } from "./components/Thread";
import { useAgent } from "./hooks/useAgent";
import { useAuth } from "./hooks/useAuth";
import { useSessions } from "./hooks/useSessions";
import type { ChatAttachment } from "./types/agent";
import type { LeftMode, RightTab } from "./types/codex";
import { LoginPage } from "./components/LoginPage";
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
    ready: authReady,
    session: authSession,
    logout,
    requestSms,
    signInSms,
    createQrSession,
    pollQrStatus,
    signInQr,
  } = useAuth();

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
    clearSessionBusy,
  } = useAgent({
    activeSessionId: activeId,
    setMessages,
  });

  const [leftMode, setLeftMode] = useState<LeftMode>("threads");
  const [rightOpen, setRightOpen] = useState(false);
  const [rightTab, setRightTab] = useState<RightTab>("diff");
  const [mcpOpen, setMcpOpen] = useState(false);
  const [skillsOpen, setSkillsOpen] = useState(false);
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
      // Ctrl+V：仅在未聚焦可编辑控件时，才把粘贴转到会话输入框。
      // 之前连设置里的 Base URL / API Key 输入框也被抢走，导致「框内不能粘贴」。
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "v") {
        const activeEl = document.activeElement as HTMLElement | null;
        const tag = activeEl?.tagName;
        const isEditable =
          tag === "TEXTAREA" ||
          tag === "INPUT" ||
          Boolean(activeEl?.isContentEditable);
        if (isEditable) return;

        e.preventDefault();
        const textarea = document.querySelector(
          ".composer-card textarea",
        ) as HTMLTextAreaElement | null;
        if (!textarea) return;
        textarea.focus();
        void (async () => {
          try {
            const { readText } = await import(
              "@tauri-apps/plugin-clipboard-manager"
            );
            const text = await readText();
            if (!text) return;
            const start = textarea.selectionStart;
            const end = textarea.selectionEnd;
            const next =
              textarea.value.slice(0, start) + text + textarea.value.slice(end);
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
              window.HTMLTextAreaElement.prototype,
              "value",
            )?.set;
            nativeInputValueSetter?.call(textarea, next);
            textarea.dispatchEvent(new Event("input", { bubbles: true }));
            const caret = start + text.length;
            textarea.selectionStart = caret;
            textarea.selectionEnd = caret;
          } catch {
            document.execCommand("paste");
          }
        })();
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

  if (!authReady) {
    return <div className="login-page"><div className="login-card">加载中…</div></div>;
  }

  if (!authSession) {
    return (
      <LoginPage
        onRequestSms={requestSms}
        onSignInSms={signInSms}
        onCreateQr={createQrSession}
        onPollQr={pollQrStatus}
        onSignInQr={signInQr}
      />
    );
  }

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
        skillsOpen={skillsOpen}
        authUser={authSession.displayName || authSession.phone || `用户 ${authSession.userId}`}
        onLogout={() => void logout()}
        onMode={setLeftMode}
        onNew={() => {
          createSession();
          setLeftMode("threads");
        }}
        onToggleRight={() => setRightOpen((v) => !v)}
        onOpenMcp={() => {
          setSkillsOpen(false);
          setMcpOpen(true);
        }}
        onOpenSkills={() => {
          setMcpOpen(false);
          setSkillsOpen(true);
        }}
        onSelectSession={setActiveId}
        onRemoveSession={(id) => {
          void (async () => {
            if (busyBySession[id]) {
              await cancelMessage(id);
            }
            try {
              await invoke("drop_session_agent", { threadId: id });
            } catch {
              /* ignore */
            }
            clearSessionBusy(id);
            removeSession(id);
          })();
        }}
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
                // 其它会话分析中也可切换：新对话下一条起用新模型，运行中的会话不受影响。
                void saveSettings({ ...settings, modelId }).catch((error) =>
                  setLocalError(`切换模型失败：${String(error)}`),
                );
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
        workspace={status.workspace}
        onClose={() => setMcpOpen(false)}
        onSave={(mcpServers) => {
          if (!settings) return;
          void saveSettings({ ...settings, mcpServers });
        }}
      />

      <SkillsModal
        open={skillsOpen}
        workspace={status.workspace}
        onClose={() => setSkillsOpen(false)}
      />
    </div>
  );
}

export default App;
