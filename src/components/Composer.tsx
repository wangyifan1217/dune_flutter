import { invoke } from "@tauri-apps/api/core";
import { useEffect, useMemo, useRef, useState } from "react";
import type {
  ChatAttachment,
  ChatMode,
  DirectoryTreeNode,
  ModelEntry,
} from "../types/agent";
import { CHAT_MODE_PREFIX } from "../types/agent";
import { IconArrowUp, IconFile, IconPlus, IconStop, IconX } from "./Icons";
import { ModelPicker } from "./ModelPicker";
import type { SkillInfo } from "./SkillsModal";

interface ComposerProps {
  busy: boolean;
  modelId: string;
  models: ModelEntry[];
  askApproval: boolean;
  empty: boolean;
  chatMode: ChatMode;
  tree: DirectoryTreeNode | null;
  queuedText?: string | null;
  onChatModeChange: (mode: ChatMode) => void;
  onAskApprovalChange: (value: boolean) => void;
  onModelChange: (modelId: string) => void;
  onManageModels: () => void;
  onOpenSkills: () => void;
  onOpenFile?: (path: string) => void;
  onSend: (text: string, attachments: ChatAttachment[]) => Promise<void>;
  onQueue?: (text: string, attachments: ChatAttachment[]) => void;
  onCancelQueue?: () => void;
  onStop?: () => void;
  onAddFiles: (files: File[]) => void;
  attachments: ChatAttachment[];
  onRemoveAttachment: (id: string) => void;
  /** 编辑模式提示；非空时显示可取消的编辑条 */
  editingHint?: string | null;
  onCancelEdit?: () => void;
  /** 有待批准权限时，替代「运行中」提示 */
  awaitingPermission?: boolean;
  hasWorkspace?: boolean;
  onPickWorkspace?: () => void;
}

type ContextFile = { id: string; name: string; path: string };

function flattenFiles(node: DirectoryTreeNode | null, acc: string[] = []): string[] {
  if (!node) return acc;
  if (!node.isDir) {
    acc.push(node.path);
    return acc;
  }
  for (const child of node.children ?? []) {
    flattenFiles(child, acc);
  }
  return acc;
}

type MentionMode = "skill" | "file" | null;

const MODE_OPTIONS: Array<{ id: ChatMode; label: string; tip: string }> = [
  { id: "agent", label: "执行", tip: "可改文件、跑命令、调用 Office / 联网等工具" },
  { id: "plan", label: "规划", tip: "只出计划（只读），确认后再执行" },
  { id: "ask", label: "问答", tip: "只分析回答（只读），不改代码不写文件" },
];

export function Composer({
  busy,
  modelId,
  models,
  askApproval,
  empty,
  chatMode,
  tree,
  queuedText = null,
  onChatModeChange,
  onAskApprovalChange,
  onModelChange,
  onManageModels,
  onOpenSkills,
  onOpenFile,
  onSend,
  onQueue,
  onCancelQueue,
  onStop,
  onAddFiles,
  attachments,
  onRemoveAttachment,
  editingHint = null,
  onCancelEdit,
  awaitingPermission = false,
  hasWorkspace = false,
  onPickWorkspace,
}: ComposerProps) {
  const [value, setValue] = useState("");
  const [mention, setMention] = useState<MentionMode>(null);
  const [mentionQuery, setMentionQuery] = useState("");
  const [skills, setSkills] = useState<SkillInfo[]>([]);
  const [contextFiles, setContextFiles] = useState<ContextFile[]>([]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const fileOptions = useMemo(() => {
    const all = flattenFiles(tree).slice(0, 200);
    const q = mentionQuery.toLowerCase();
    return q ? all.filter((p) => p.toLowerCase().includes(q)) : all.slice(0, 40);
  }, [tree, mentionQuery]);

  const skillOptions = useMemo(() => {
    const q = mentionQuery.toLowerCase();
    return skills.filter((s) =>
      q ? s.name.toLowerCase().includes(q) || s.description?.toLowerCase().includes(q) : true,
    );
  }, [skills, mentionQuery]);

  useEffect(() => {
    const preventBrowserNavigation = (event: DragEvent) => {
      if (event.dataTransfer?.types.includes("Files")) event.preventDefault();
    };
    window.addEventListener("dragover", preventBrowserNavigation);
    window.addEventListener("drop", preventBrowserNavigation);
    return () => {
      window.removeEventListener("dragover", preventBrowserNavigation);
      window.removeEventListener("drop", preventBrowserNavigation);
    };
  }, []);

  useEffect(() => {
    const applySuggestion = (event: Event) => {
      const text = (event as CustomEvent<string>).detail;
      if (!text) return;
      setValue(text);
      requestAnimationFrame(() => textareaRef.current?.focus());
    };
    window.addEventListener("nova:prompt-suggestion", applySuggestion);
    return () => window.removeEventListener("nova:prompt-suggestion", applySuggestion);
  }, []);

  useEffect(() => {
    void invoke<SkillInfo[]>("list_skills")
      .then(setSkills)
      .catch(() => setSkills([]));
  }, []);

  async function submit(raw?: string) {
    let text = (raw ?? value).trim();
    if (!text && attachments.length === 0 && contextFiles.length === 0) return;

    // 把引用文件路径补进提示，方便 Agent 定位
    if (contextFiles.length > 0) {
      const refs = contextFiles
        .map((f) => `- ${f.path}`)
        .join("\n");
      const block = `【引用文件】\n${refs}\n\n`;
      if (!text.includes("【引用文件】")) {
        text = `${block}${text}`;
      }
    }

    const prefix = CHAT_MODE_PREFIX[chatMode];
    if (prefix && !text.startsWith(prefix.trim().slice(0, 6))) {
      text = `${prefix}${text}`;
    }
    if (busy) {
      onQueue?.(text, attachments);
      setValue("");
      setMention(null);
      setContextFiles([]);
      return;
    }
    setValue("");
    setMention(null);
    setContextFiles([]);
    requestAnimationFrame(() => textareaRef.current?.focus());
    await onSend(text, attachments);
  }

  function addContextFile(path: string) {
    const name = path.split(/[/\\]/).pop() ?? path;
    setContextFiles((prev) => {
      if (prev.some((f) => f.path === path)) return prev;
      return [...prev, { id: crypto.randomUUID(), name, path }];
    });
    insertToken(`@${name}`, "@");
  }

  function detectMention(next: string, caret: number) {
    const before = next.slice(0, caret);
    const skillMatch = before.match(/(?:^|\s)\/([^\s]*)$/);
    const fileMatch = before.match(/(?:^|\s)@([^\s]*)$/);
    if (skillMatch) {
      setMention("skill");
      setMentionQuery(skillMatch[1] ?? "");
      return;
    }
    if (fileMatch) {
      setMention("file");
      setMentionQuery(fileMatch[1] ?? "");
      return;
    }
    setMention(null);
    setMentionQuery("");
  }

  function insertToken(token: string, trigger: "/" | "@") {
    const textarea = textareaRef.current;
    if (!textarea) {
      setValue((v) => `${v}${token} `);
      return;
    }
    const caret = textarea.selectionStart;
    const before = value.slice(0, caret);
    const after = value.slice(caret);
    const replaced = before.replace(
      new RegExp(`(?:^|\\s)\\${trigger}[^\\s]*$`),
      (m) => `${m.match(/^\s/) ? m[0] : ""}${token}`,
    );
    const next = `${replaced} ${after}`;
    setValue(next);
    setMention(null);
    requestAnimationFrame(() => {
      const pos = replaced.length + 1;
      textarea.focus();
      textarea.selectionStart = pos;
      textarea.selectionEnd = pos;
    });
  }

  async function handlePaste(e: React.ClipboardEvent<HTMLTextAreaElement>) {
    const clipboardData = e.clipboardData;
    const items = clipboardData?.items;
    if (items) {
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (item.type.startsWith("image/")) {
          e.preventDefault();
          const file = item.getAsFile();
          if (file) {
            onAddFiles([file]);
            return;
          }
        }
      }
    }

    let pastedText = clipboardData?.getData("text/plain") ?? "";
    if (!pastedText) {
      e.preventDefault();
      try {
        const { readText } = await import("@tauri-apps/plugin-clipboard-manager");
        pastedText = await readText();
      } catch {
        return;
      }
    }
    if (!pastedText) return;

    e.preventDefault();
    const textarea = textareaRef.current;
    if (!textarea) return;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const before = value.slice(0, start);
    const after = value.slice(end);
    const newValue = before + pastedText + after;
    setValue(newValue);
    requestAnimationFrame(() => {
      textarea.selectionStart = start + pastedText.length;
      textarea.selectionEnd = start + pastedText.length;
    });
  }

  const placeholder =
    chatMode === "plan"
      ? "描述目标，先生成实现计划（只读，不会改文件）…"
      : chatMode === "ask"
        ? "提问或分析代码（只读）…"
        : "描述任务，输入 / 选技能，@ 引用文件";

  return (
    <div className="composer-dock">
      {!hasWorkspace ? (
        <div className="composer-queue composer-workspace-hint" role="status">
          <span>选一个项目后，才能改代码、审 Git、用 @ 引用文件</span>
          <button type="button" className="linkish" onClick={onPickWorkspace}>
            选择项目
          </button>
        </div>
      ) : null}
      {editingHint ? (
        <div className="composer-queue composer-edit" role="status">
          <span>{editingHint}</span>
          <button
            type="button"
            className="linkish"
            onClick={() => {
              onCancelEdit?.();
              setValue("");
            }}
          >
            取消编辑
          </button>
        </div>
      ) : queuedText ? (
        <div className="composer-queue" role="status">
          <span>
            下一条将在完成后发送：
            <em>{queuedText.replace(/\s+/g, " ").slice(0, 80)}</em>
          </span>
          <button type="button" className="linkish" onClick={onCancelQueue}>
            取消
          </button>
        </div>
      ) : awaitingPermission ? (
        <div className="composer-queue composer-permission-wait" role="status">
          <span>等待你的批准 — 请先处理上方的权限请求</span>
        </div>
      ) : busy ? (
        <div className="composer-queue quiet" role="status">
          <span>Agent 运行中 — 可继续输入，Enter 将排队发送</span>
        </div>
      ) : null}
      <div
        className="composer-card"
        onDragOverCapture={(e) => {
          if (e.dataTransfer.types.includes("Files")) e.preventDefault();
        }}
        onDropCapture={(e) => {
          if (!e.dataTransfer.types.includes("Files")) return;
          e.preventDefault();
          e.stopPropagation();
          onAddFiles(Array.from(e.dataTransfer.files));
        }}
      >
        {(attachments.length > 0 || contextFiles.length > 0) && (
          <div className="composer-context" aria-label="上下文文件">
            {contextFiles.map((file) => (
              <div className="context-chip" key={file.id} title={file.path}>
                <button
                  type="button"
                  className="context-chip-main"
                  onClick={() => onOpenFile?.(file.path)}
                >
                  <IconFile size={13} />
                  <span>{file.name}</span>
                </button>
                <button
                  type="button"
                  className="context-chip-x"
                  aria-label={`移除 ${file.name}`}
                  onClick={() =>
                    setContextFiles((prev) => prev.filter((f) => f.id !== file.id))
                  }
                >
                  <IconX size={12} />
                </button>
              </div>
            ))}
            {attachments.map((attachment) => (
              <div className="context-chip attachment" key={attachment.id}>
                {attachment.mimeType.startsWith("image/") ? (
                  <img
                    src={`data:${attachment.mimeType};base64,${attachment.data}`}
                    alt={attachment.name}
                  />
                ) : (
                  <IconFile size={13} />
                )}
                <span className="context-chip-name" title={attachment.name}>
                  {attachment.name}
                </span>
                <button
                  type="button"
                  className="context-chip-x"
                  aria-label={`移除 ${attachment.name}`}
                  onClick={() => onRemoveAttachment(attachment.id)}
                >
                  <IconX size={12} />
                </button>
              </div>
            ))}
          </div>
        )}

        <div className="composer-input-wrap">
          <textarea
            ref={textareaRef}
            rows={empty ? 3 : 3}
            value={value}
            placeholder={placeholder}
            onChange={(e) => {
              const next = e.target.value;
              setValue(next);
              detectMention(next, e.target.selectionStart);
            }}
            onPaste={handlePaste}
            onKeyDown={(e) => {
              if (e.key === "Tab" && empty && !value.trim()) {
                e.preventDefault();
                onChatModeChange("plan");
                return;
              }
              if (e.key === "Escape") {
                setMention(null);
                return;
              }
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                void submit();
              }
            }}
          />

          {mention === "skill" ? (
            <div className="mention-popover">
              <div className="mention-title">技能</div>
              {skillOptions.length === 0 ? (
                <button type="button" className="mention-item" onClick={onOpenSkills}>
                  管理技能…
                </button>
              ) : (
                skillOptions.slice(0, 8).map((s) => (
                  <button
                    key={`${s.scope}-${s.name}`}
                    type="button"
                    className="mention-item"
                    onClick={() => insertToken(`/${s.name}`, "/")}
                  >
                    <strong>/{s.name}</strong>
                    <span>{s.description || s.scope}</span>
                  </button>
                ))
              )}
            </div>
          ) : null}

          {mention === "file" ? (
            <div className="mention-popover">
              <div className="mention-title">引用文件</div>
              {fileOptions.length === 0 ? (
                <div className="empty-hint">没有可引用的文件，先打开项目</div>
              ) : (
                fileOptions.slice(0, 10).map((path) => {
                  const name = path.split(/[/\\]/).pop() ?? path;
                  return (
                    <button
                      key={path}
                      type="button"
                      className="mention-item"
                      onClick={() => addContextFile(path)}
                    >
                      <strong>@{name}</strong>
                      <span>{path}</span>
                    </button>
                  );
                })
              )}
            </div>
          ) : null}
        </div>

        <div className="composer-toolbar">
          <div className="toolbar-left">
            <input
              ref={fileInputRef}
              type="file"
              hidden
              multiple
              onChange={(e) => {
                onAddFiles(Array.from(e.currentTarget.files ?? []));
                e.currentTarget.value = "";
              }}
            />
            <button
              type="button"
              className="attach-plus"
              title="添加附件（也可拖入窗口或粘贴图片；文本≤512KB，其它≤10MB）"
              onClick={() => fileInputRef.current?.click()}
            >
              <IconPlus size={16} />
            </button>
            <button
              type="button"
              className="attach-plus soft"
              title="引用项目文件（也可输入 @）"
              onClick={() => {
                if (!hasWorkspace) {
                  onPickWorkspace?.();
                  return;
                }
                setMention("file");
                setMentionQuery("");
                textareaRef.current?.focus();
                const v = value;
                if (!/(?:^|\s)@$/.test(v.slice(-2)) && !v.endsWith("@")) {
                  const next = v && !/\s$/.test(v) ? `${v} @` : `${v}@`;
                  setValue(next);
                }
              }}
            >
              <IconFile size={15} />
            </button>
            <div className="mode-segment" role="tablist" aria-label="对话模式">
              {MODE_OPTIONS.map((opt) => (
                <button
                  key={opt.id}
                  type="button"
                  role="tab"
                  title={opt.tip}
                  aria-selected={chatMode === opt.id}
                  className={chatMode === opt.id ? "active" : ""}
                  onClick={() => onChatModeChange(opt.id)}
                >
                  {opt.label}
                </button>
              ))}
            </div>
            <ModelPicker
              modelId={modelId}
              models={models}
              onChange={onModelChange}
              onManage={onManageModels}
            />
          </div>
          <div className="toolbar-right">
            <button
              type="button"
              className={`tool-chip quiet ${askApproval ? "warn" : "ok"}`}
              onClick={() => onAskApprovalChange(!askApproval)}
              title={askApproval ? "每次操作需批准" : "自动批准工具权限"}
            >
              {askApproval ? "需批准" : "自动批准"}
            </button>
            {busy ? (
              <button
                type="button"
                className="send-round stop"
                onClick={() => onStop?.()}
                aria-label="终止回答"
                title="终止回答"
              >
                <IconStop size={14} />
              </button>
            ) : (
              <button
                type="button"
                className="send-round"
                disabled={!value.trim() && attachments.length === 0 && contextFiles.length === 0}
                onClick={() => void submit()}
                aria-label="发送"
              >
                <IconArrowUp size={16} />
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
