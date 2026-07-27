import { useState } from "react";
import type { ChatMessage, ToolCallStatus } from "../types/agent";

const STATUS_LABEL: Record<ToolCallStatus, string> = {
  pending: "等待中",
  running: "进行中",
  completed: "已完成",
  failed: "失败",
};

interface ToolCallCardProps {
  message: ChatMessage;
}

export function ToolCallCard({ message }: ToolCallCardProps) {
  const [open, setOpen] = useState(false);
  const status: ToolCallStatus = message.toolStatus ?? "running";
  const title = message.toolTitle || message.content || "工具调用";
  const output = message.toolOutput?.trim();

  return (
    <div className={`msg msg-tool-card status-${status}`}>
      <button
        type="button"
        className="tool-card-head"
        onClick={() => output && setOpen((v) => !v)}
        disabled={!output}
        aria-expanded={open}
      >
        <span className={`tool-card-status ${status}`} aria-hidden>
          {status === "running" || status === "pending" ? (
            <i className="tool-spin" />
          ) : status === "failed" ? (
            "!"
          ) : (
            "✓"
          )}
        </span>
        <span className="tool-card-title">{title}</span>
        <span className="tool-card-meta">{STATUS_LABEL[status]}</span>
        {output ? (
          <span className={`tool-card-chev ${open ? "open" : ""}`} aria-hidden>
            ▸
          </span>
        ) : null}
      </button>
      {open && output ? <pre className="tool-card-output">{output}</pre> : null}
    </div>
  );
}
