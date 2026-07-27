import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useCallback, useEffect, useRef, useState } from "react";
import { Composer } from "./components/Composer";
import { GrokSetupModal } from "./components/GrokSetupModal";
import { MemoryModal } from "./components/MemoryModal";
import { ConfirmDialog } from "./components/ConfirmDialog";
import { SettingsModal, type SettingsTab } from "./components/SettingsModal";
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
import type { ChatAttachment, ChatMode } from "./types/agent";
import type { AppSettings } from "./types/agent";
import type { RightTab } from "./types/codex";
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

interface GrokInstallationStatus {
  platform: string;
  installed: boolean;
  command: string | null;
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
    setChatMode,
    bindSessionWorkspace,
    truncateFrom,
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

  const [rightOpen, setRightOpen] = useState(true);
  const [rightTab, setRightTab] = useState<RightTab>("diff");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settingsTab, setSettingsTab] = useState<SettingsTab>("general");
  const [memoryOpen, setMemoryOpen] = useState(false);
  const [skillsOpen, setSkillsOpen] = useState(false);
  const [skillsCreate, setSkillsCreate] = useState(false);
  const [skillsRefreshKey, setSkillsRefreshKey] = useState(0);
  const [logoutConfirmOpen, setLogoutConfirmOpen] = useState(false);
  const [deleteSessionId, setDeleteSessionId] = useState<string | null>(null);
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);
  const [gitChanges, setGitChanges] = useState<GitChange[]>([]);
  const [gitError, setGitError] = useState<string | null>(null);
  const [permission, setPermission] = useState<PermissionRequest | null>(null);
  const [previewPath, setPreviewPath] = useState<string | null>(null);
  const [attachments, setAttachments] = useState<ChatAttachment[]>([]);
  const [queuedSend, setQueuedSend] = useState<{
    text: string;
    attachments: ChatAttachment[];
  } | null>(null);
  const [grokSetupOpen, setGrokSetupOpen] = useState(false);
  const [checkingGrok, setCheckingGrok] = useState(false);
  const [stickToBottom, setStickToBottom] = useState(true);
  const [showJumpBottom, setShowJumpBottom] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const stickToBottomRef = useRef(true);
  const ignoreScrollUntilRef = useRef(0);
  const restoredWorkspace = useRef(false);
  const prevBusyRef = useRef(false);

  const openSkills = useCallback((create = false) => {
    setMemoryOpen(false);
    setSkillsCreate(create);
    setSkillsOpen(true);
  }, []);

  const openSettings = useCallback((tab: SettingsTab = "general") => {
    setMemoryOpen(false);
    setSkillsOpen(false);
    setSkillsCreate(false);
    setSettingsTab(tab);
    setSettingsOpen(true);
  }, []);

  const handleSaveSettings = useCallback(
    async (next: AppSettings) => {
      const prev = settings;
      await saveSettings(next);
      const mcpChanged =
        JSON.stringify(prev?.mcpServers ?? []) !== JSON.stringify(next.mcpServers ?? []);
      const modelChanged = (prev?.modelId ?? "") !== (next.modelId ?? "");
      if (mcpChanged || modelChanged) {
        try {
          await reconnect();
        } catch {
          /* 下次发送仍会按 fingerprint 重建 */
        }
      }
    },
    [settings, saveSettings, reconnect],
  );

  const chatModeRef = useRef(active?.chatMode ?? "agent");
  chatModeRef.current = active?.chatMode ?? "agent";

  const refreshGit = useCallback(async () => {
    if (!status.workspace) {
      setGitChanges([]);
      setGitError(null);
      return;
    }
    try {
      const list = await invoke<GitChange[]>("git_list_changes");
      setGitChanges(list);
      setGitError(null);
    } catch (error) {
      setGitChanges([]);
      setGitError(String(error));
    }
  }, [status.workspace]);

  const checkGrokInstallation = useCallback(async () => {
    setCheckingGrok(true);
    try {
      const result = await invoke<GrokInstallationStatus>("get_grok_installation");
      setGrokSetupOpen(result.platform === "macos" && !result.installed);
    } catch {
      setGrokSetupOpen(false);
    } finally {
      setCheckingGrok(false);
    }
  }, []);

  useEffect(() => {
    if (!authSession) {
      setGrokSetupOpen(false);
      return;
    }
    void checkGrokInstallation();
  }, [authSession, checkGrokInstallation]);

  useEffect(() => {
    if (!sessionsReady) return;
    if (!activeId) createSession(status.workspace);
  }, [activeId, createSession, sessionsReady, status.workspace]);

  useEffect(() => {
    if (!activeId || !status.workspace) return;
    const session = sessions.find((s) => s.id === activeId);
    if (session && !session.workspace) {
      bindSessionWorkspace(activeId, status.workspace);
    }
  }, [activeId, status.workspace, sessions, bindSessionWorkspace]);

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

  const scrollToBottom = useCallback((opts?: { smooth?: boolean }) => {
    const el = scrollRef.current;
    stickToBottomRef.current = true;
    setStickToBottom(true);
    setShowJumpBottom(false);
    if (!el) return;
    ignoreScrollUntilRef.current = Date.now() + 280;
    const behavior: ScrollBehavior = opts?.smooth ? "smooth" : "auto";
    const go = () => {
      el.scrollTo({ top: el.scrollHeight, behavior });
    };
    go();
    requestAnimationFrame(() => {
      go();
      requestAnimationFrame(go);
    });
  }, []);

  useEffect(() => {
    stickToBottomRef.current = stickToBottom;
  }, [stickToBottom]);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    if (!stickToBottomRef.current) {
      setShowJumpBottom(true);
      return;
    }
    ignoreScrollUntilRef.current = Date.now() + 120;
    el.scrollTop = el.scrollHeight;
    setShowJumpBottom(false);
  }, [active?.messages, busy, stickToBottom, progressBySession, permission]);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;

    const onScroll = () => {
      if (Date.now() < ignoreScrollUntilRef.current) return;
      const distance = el.scrollHeight - el.scrollTop - el.clientHeight;
      const nearBottom = distance < 120;
      stickToBottomRef.current = nearBottom;
      setStickToBottom(nearBottom);
      setShowJumpBottom(!nearBottom);
    };
    el.addEventListener("scroll", onScroll, { passive: true });

    const followGrowth = () => {
      if (!stickToBottomRef.current) return;
      ignoreScrollUntilRef.current = Date.now() + 80;
      el.scrollTop = el.scrollHeight;
    };
    const ro = new ResizeObserver(followGrowth);
    const observeChildren = () => {
      for (const child of Array.from(el.children)) {
        ro.observe(child);
      }
    };
    observeChildren();
    const mo = new MutationObserver(() => {
      observeChildren();
      followGrowth();
    });
    mo.observe(el, { childList: true, subtree: true, characterData: true });

    return () => {
      el.removeEventListener("scroll", onScroll);
      ro.disconnect();
      mo.disconnect();
    };
  }, [activeId]);

  useEffect(() => {
    setQueuedSend(null);
    stickToBottomRef.current = true;
    setStickToBottom(true);
    setShowJumpBottom(false);
    setEditingMessageId(null);
    requestAnimationFrame(() => scrollToBottom());
  }, [activeId, scrollToBottom]);

  useEffect(() => {
    if (!permission) return;
    scrollToBottom();
  }, [permission, scrollToBottom]);

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
      const toolCall = params.toolCall as
        | { title?: string; kind?: string }
        | undefined;
      const kind = (toolCall?.kind ?? "").toLowerCase();
      const mode = chatModeRef.current;
      const writeLike =
        /edit|write|delete|move|execute|shell|terminal|create|overwrite/.test(
          kind,
        );
      if ((mode === "ask" || mode === "plan") && writeLike) {
        void invoke("respond_permission", { id, allow: false })
          .then(() => {
            setLocalError(
              `${mode === "ask" ? "问答" : "规划"}模式下已拦截会改写环境的操作，请切换到「执行」模式后再试`,
            );
          })
          .catch(() => undefined);
        return;
      }
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
        createSession(status.workspace);
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
  }, [createSession, status.workspace]);

  function openPreview(path: string) {
    setLocalError(null);
    setPreviewPath(path);
    setRightOpen(true);
    setRightTab("preview");
  }

  async function openExternal(path: string) {
    setLocalError(null);
    try {
      await invoke("open_generated_file", { path });
    } catch (error) {
      setLocalError(`无法打开文件：${String(error)}`);
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
      if (activeId) bindSessionWorkspace(activeId, path);
      setRightOpen(true);
      setRightTab("files");
      void refreshGit();
    } catch (error) {
      setLocalError(String(error));
    }
  }

  async function handleSend(text: string, pendingAttachments: ChatAttachment[]) {
    if (!activeId) return;
    scrollToBottom({ smooth: true });
    setLocalError(null);
    if (!status.connected && !(await connectDefaultAgent(activeId))) return;
    if (status.workspace) bindSessionWorkspace(activeId, status.workspace);

    let history = active?.messages ?? [];
    if (editingMessageId) {
      const idx = history.findIndex((m) => m.id === editingMessageId);
      if (idx >= 0) {
        history = history.slice(0, idx);
        truncateFrom(activeId, editingMessageId);
      }
      setEditingMessageId(null);
    }

    const sent = await sendMessage(
      activeId,
      text,
      pendingAttachments,
      history,
    );
    if (sent) {
      setAttachments([]);
      scrollToBottom();
    }
    await refreshGit();
  }

  useEffect(() => {
    if (prevBusyRef.current && !busy && queuedSend && activeId) {
      const next = queuedSend;
      setQueuedSend(null);
      void handleSend(next.text, next.attachments);
    }
    prevBusyRef.current = busy;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busy]);

  function jumpToBottom() {
    scrollToBottom({ smooth: true });
  }

  /** 按轮次重试：找到目标消息之前最近的 user，截断后重发。 */
  function retryFromMessage(messageId: string) {
    if (!activeId || busy) return;
    const messages = active?.messages ?? [];
    const targetIdx = messages.findIndex((m) => m.id === messageId);
    if (targetIdx < 0) return;
    let userIdx = -1;
    for (let i = targetIdx; i >= 0; i -= 1) {
      if (messages[i]?.role === "user") {
        userIdx = i;
        break;
      }
    }
    if (userIdx < 0) return;
    const user = messages[userIdx];
    const history = messages.slice(0, userIdx);
    truncateFrom(activeId, user.id);
    setEditingMessageId(null);
    scrollToBottom({ smooth: true });
    void (async () => {
      if (!status.connected && !(await connectDefaultAgent(activeId))) return;
      if (status.workspace) bindSessionWorkspace(activeId, status.workspace);
      const sent = await sendMessage(
        activeId,
        user.content,
        user.attachments ?? [],
        history,
      );
      if (sent) setAttachments([]);
      await refreshGit();
    })();
  }

  function startEditUser(messageId: string, text: string) {
    if (busy) return;
    setEditingMessageId(messageId);
    setQueuedSend(null);
    window.dispatchEvent(
      new CustomEvent<string>("nova:prompt-suggestion", { detail: text }),
    );
  }

  async function confirmDeleteSession(id: string) {
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
    setDeleteSessionId(null);
  }

  const projectName =
    status.workspace?.split(/[/\\]/).filter(Boolean).pop() ?? "未打开项目";
  const displayError = localError ?? lastError;
  const askApproval = !(settings?.autoApprovePermissions ?? true);
  const isEmpty = (active?.messages.length ?? 0) === 0;
  const chatMode: ChatMode = active?.chatMode ?? "agent";

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
    <div className="codex-app agents-app">
      <Sidebar
        sessions={sessions}
        activeId={activeId}
        busyBySession={busyBySession}
        error={displayError}
        authUser={authSession.displayName || authSession.phone || `用户 ${authSession.userId}`}
        settingsOpen={settingsOpen}
        onLogout={() => setLogoutConfirmOpen(true)}
        onNew={() => {
          createSession(status.workspace);
        }}
        onOpenSettings={() => openSettings("general")}
        onSelectSession={setActiveId}
        onRemoveSession={(id) => setDeleteSessionId(id)}
      />

      <main className="main-stage">
            <div className="main-topbar">
              <button type="button" className="context-project" onClick={() => void pickFolder()}>
                <span className="context-hash">#</span>
                {status.workspace ? projectName : "选择项目"}
              </button>
              <button type="button" className="context-local" onClick={() => void pickFolder()}>
                本地
                <span className="chev">▾</span>
              </button>
              {status.workspace ? (
                <button
                  type="button"
                  className="context-local"
                  title="移除当前项目"
                  onClick={() => {
                    void clearWorkspace()
                      .then(() => {
                        localStorage.removeItem("nova-desktop.last-workspace");
                      })
                      .catch(() => undefined);
                  }}
                >
                  移除
                </button>
              ) : (
                <span className="workspace-hint" title="未选择项目时，Agent 以用户主目录为工作区">
                  未选项目 · 生成文件在用户目录
                </span>
              )}
            </div>

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
                  onApprovePlan={() => {
                    if (activeId) setChatMode(activeId, "agent");
                    void handleSend(
                      "计划已确认，请按上述步骤开始执行，可以修改文件并运行必要命令。",
                      [],
                    );
                  }}
                  onRevisePlan={() => {
                    if (activeId) setChatMode(activeId, "plan");
                    window.dispatchEvent(
                      new CustomEvent<string>("nova:prompt-suggestion", {
                        detail: "请修订计划：",
                      }),
                    );
                  }}
                  onStarter={(prompt, mode) => {
                    if (activeId && mode) setChatMode(activeId, mode);
                    window.dispatchEvent(
                      new CustomEvent<string>("nova:prompt-suggestion", {
                        detail: prompt,
                      }),
                    );
                  }}
                  onRetry={retryFromMessage}
                  onEditUser={startEditUser}
                  onOpenFile={openPreview}
                  onOpenError={(msg) => setLocalError(msg)}
                />
              </div>

              {showJumpBottom ? (
                <button
                  type="button"
                  className="jump-bottom-btn"
                  onClick={jumpToBottom}
                >
                  ↓ 新消息
                </button>
              ) : null}
            </div>

            <Composer
              busy={busy}
              modelId={settings?.modelId ?? ""}
              models={settings?.models ?? []}
              askApproval={askApproval}
              empty={isEmpty}
              chatMode={chatMode}
              tree={tree}
              queuedText={queuedSend?.text ?? null}
              editingHint={
                editingMessageId
                  ? "编辑中：发送后将替换此条及之后的回复"
                  : null
              }
              onCancelEdit={() => setEditingMessageId(null)}
              awaitingPermission={Boolean(permission)}
              hasWorkspace={Boolean(status.workspace)}
              onPickWorkspace={() => void pickFolder()}
              onChatModeChange={(mode) => {
                if (activeId) setChatMode(activeId, mode);
              }}
              onAskApprovalChange={(ask) => {
                if (!settings) return;
                void handleSaveSettings({
                  ...settings,
                  autoApprovePermissions: !ask,
                });
              }}
              onModelChange={(modelId) => {
                if (!settings || modelId === settings.modelId) return;
                void handleSaveSettings({ ...settings, modelId }).catch((error) =>
                  setLocalError(`切换模型失败：${String(error)}`),
                );
              }}
              onManageModels={() => openSettings("models")}
              onOpenSkills={() => openSkills(true)}
              onOpenFile={openPreview}
              attachments={attachments}
              onAddFiles={(files) => {
                void Promise.all(files.map(toAttachment))
                  .then((next) => setAttachments((current) => [...current, ...next]))
                  .catch((error) => setLocalError(String(error)));
              }}
              onRemoveAttachment={(id) =>
                setAttachments((current) => current.filter((item) => item.id !== id))
              }
              onSend={handleSend}
              onQueue={(text, files) => {
                setQueuedSend({ text, attachments: files });
                setAttachments([]);
              }}
              onCancelQueue={() => setQueuedSend(null)}
              onStop={() => {
                if (!activeId) return;
                setQueuedSend(null);
                void cancelMessage(activeId);
              }}
            />
      </main>

      <RightPanel
        open={rightOpen}
        tab={rightTab}
        tree={tree}
        diffs={diffs}
        gitChanges={gitChanges}
        activity={activity}
        workspace={status.workspace}
        gitError={gitError}
        previewPath={previewPath}
        onTab={(tab) => {
          setRightTab(tab);
          setRightOpen(true);
        }}
        onClose={() => setRightOpen(false)}
        onRefreshGit={() => void refreshGit()}
        onOpenFile={openPreview}
        onClearPreview={() => setPreviewPath(null)}
        onOpenExternal={(path) => void openExternal(path)}
        onPreviewError={(msg) => setLocalError(msg)}
      />

      <SettingsModal
        open={settingsOpen}
        settings={settings}
        status={status}
        busy={busy}
        workspace={status.workspace}
        initialTab={settingsTab}
        skillsRefreshKey={skillsRefreshKey}
        onClose={() => setSettingsOpen(false)}
        onSave={handleSaveSettings}
        onOpenSkills={(create) => openSkills(Boolean(create))}
        onOpenMemory={() => setMemoryOpen(true)}
        onOpenFolder={() => void pickFolder()}
        onReconnect={() => void reconnect()}
        onDisconnect={() => void disconnect()}
      />

      <MemoryModal open={memoryOpen} onClose={() => setMemoryOpen(false)} />

      <SkillsModal
        open={skillsOpen}
        workspace={status.workspace}
        initialCreate={skillsCreate}
        onClose={() => {
          setSkillsOpen(false);
          setSkillsCreate(false);
          setSkillsRefreshKey((k) => k + 1);
        }}
      />

      <ConfirmDialog
        open={logoutConfirmOpen}
        title="退出登录？"
        message="退出后需要重新登录才能继续使用 Nova Build。"
        confirmLabel="退出"
        cancelLabel="取消"
        danger
        onCancel={() => setLogoutConfirmOpen(false)}
        onConfirm={() => {
          setLogoutConfirmOpen(false);
          setSettingsOpen(false);
          setMemoryOpen(false);
          setSkillsOpen(false);
          void logout();
        }}
      />

      <ConfirmDialog
        open={Boolean(deleteSessionId)}
        title="删除对话？"
        message="删除后无法恢复该对话中的消息。"
        confirmLabel="删除"
        cancelLabel="取消"
        danger
        onCancel={() => setDeleteSessionId(null)}
        onConfirm={() => {
          if (deleteSessionId) void confirmDeleteSession(deleteSessionId);
        }}
      />

      <GrokSetupModal
        open={grokSetupOpen}
        checking={checkingGrok}
        onRecheck={checkGrokInstallation}
      />
    </div>
  );
}

export default App;
