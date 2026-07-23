import { useEffect, useRef, useState } from "react";
import type { ChatAttachment, ModelEntry } from "../types/agent";
import { ModelPicker } from "./ModelPicker";

interface ComposerProps {
  busy: boolean;
  connected: boolean;
  projectName: string;
  modelId: string;
  models: ModelEntry[];
  askApproval: boolean;
  empty: boolean;
  onAskApprovalChange: (value: boolean) => void;
  onModelChange: (modelId: string) => void;
  onManageModels: () => void;
  onPickProject: () => void;
  onClearProject: () => void;
  onSend: (text: string, attachments: ChatAttachment[]) => Promise<void>;
  onStop?: () => void;
  onAddFiles: (files: File[]) => void;
  attachments: ChatAttachment[];
  onRemoveAttachment: (id: string) => void;
}

export function Composer({
  busy,
  connected,
  projectName,
  modelId,
  models,
  askApproval,
  empty,
  onAskApprovalChange,
  onModelChange,
  onManageModels,
  onPickProject,
  onClearProject,
  onSend,
  onStop,
  onAddFiles,
  attachments,
  onRemoveAttachment,
}: ComposerProps) {
  const [value, setValue] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

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

  async function submit() {
    const text = value.trim();
    if ((!text && attachments.length === 0) || busy) return;
    setValue("");
    await onSend(text, attachments);
  }

  /** 处理粘贴事件：文本插入到光标位置，图片作为附件 */
  async function handlePaste(e: React.ClipboardEvent<HTMLTextAreaElement>) {
    const clipboardData = e.clipboardData;

    // 优先处理图片粘贴（截图）
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

    // 文本：优先用事件里的数据；WebView2 有时为空，再走 Tauri 剪贴板
    let pastedText = clipboardData?.getData("text/plain") ?? "";
    if (!pastedText) {
      e.preventDefault();
      try {
        const { readText } = await import(
          "@tauri-apps/plugin-clipboard-manager"
        );
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

  return (
    <div className={`composer-dock ${empty ? "floating" : ""}`}>
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
        <div className="project-control">
          <button type="button" className="project-pick" onClick={onPickProject}>
            <span className="nav-ico">📁</span>
            {projectName === "未打开项目" ? "选择项目" : projectName}
          </button>
          {projectName !== "未打开项目" ? (
            <button
              type="button"
              className="project-clear"
              title="移除当前项目"
              aria-label="移除当前项目"
              onClick={onClearProject}
            >
              ×
            </button>
          ) : null}
        </div>

        {attachments.length > 0 ? (
          <div className="attachment-list" aria-label="待发送附件">
            {attachments.map((attachment) => (
              <div className="attachment-card" key={attachment.id}>
                {attachment.mimeType.startsWith("image/") ? (
                  <img
                    src={`data:${attachment.mimeType};base64,${attachment.data}`}
                    alt={attachment.name}
                  />
                ) : (
                  <span className="attachment-icon">📄</span>
                )}
                <span className="attachment-name" title={attachment.name}>
                  {attachment.name}
                </span>
                <button
                  type="button"
                  className="attachment-remove"
                  aria-label={`移除 ${attachment.name}`}
                  onClick={() => onRemoveAttachment(attachment.id)}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        ) : null}

        <textarea
          ref={textareaRef}
          rows={empty ? 2 : 3}
          value={value}
          disabled={busy}
          placeholder={connected ? "随便做什么" : "输入消息开始对话，或选择项目"}
          onChange={(e) => setValue(e.target.value)}
          onPaste={handlePaste}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void submit();
            }
          }}
        />

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
              className="attach-button"
              title="添加文件（也可直接拖入）"
              onClick={() => fileInputRef.current?.click()}
            >
              ＋ 添加附件
            </button>
            <button
              type="button"
              className={`tool-chip ${askApproval ? "warn" : "ok"}`}
              onClick={() => onAskApprovalChange(!askApproval)}
              title={askApproval ? "每次操作需批准" : "自动批准"}
            >
              {askApproval ? "需要批准" : "代我批准"}
              <span className="chev">▾</span>
            </button>
            <ModelPicker
              modelId={modelId}
              models={models}
              onChange={onModelChange}
              onManage={onManageModels}
            />
          </div>
          {busy ? (
            <button
              type="button"
              className="send-round stop"
              onClick={() => onStop?.()}
              aria-label="终止回答"
              title="终止回答"
            >
              ■
            </button>
          ) : (
            <button
              type="button"
              className="send-round"
              disabled={!value.trim() && attachments.length === 0}
              onClick={() => void submit()}
              aria-label="发送"
            >
              ↑
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
