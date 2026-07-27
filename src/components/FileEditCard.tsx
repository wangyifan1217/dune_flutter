import { useEffect, useState } from "react";
import type { ChatMessage, ToolCallStatus } from "../types/agent";

const STATUS_LABEL: Record<ToolCallStatus, string> = {
  pending: "等待中",
  running: "进行中",
  completed: "已完成",
  failed: "失败",
};

interface FileEditCardProps {
  message: ChatMessage;
  onOpenFile?: (path: string) => void;
}

export function FileEditCard({ message, onOpenFile }: FileEditCardProps) {
  const status: ToolCallStatus = message.toolStatus ?? "running";
  const path = message.toolPath || message.toolTitle || "文件";
  const fileName = path.split(/[/\\]/).pop() ?? path;
  const created = Boolean(message.toolCreated);
  const diff = message.toolDiff?.trim() ?? "";
  const [open, setOpen] = useState(status !== "completed" ? true : Boolean(diff));

  useEffect(() => {
    if (diff && status === "completed") setOpen(true);
  }, [diff, status]);

  const headline = created ? `已创建 ${fileName}` : `已编辑 ${fileName}`;

  return (
    <div className={`msg msg-file-edit status-${status}`}>
      <div className="file-edit-head">
        <span className={`file-edit-status ${status}`} aria-hidden>
          {status === "running" || status === "pending" ? (
            <i className="tool-spin" />
          ) : status === "failed" ? (
            "!"
          ) : (
            "✓"
          )}
        </span>
        <div className="file-edit-meta">
          <button
            type="button"
            className="file-edit-title"
            title={path}
            onClick={() => onOpenFile?.(path)}
            disabled={!onOpenFile}
          >
            {headline}
          </button>
          <span className="file-edit-path" title={path}>
            {path}
          </span>
        </div>
        <span className="file-edit-badge">{STATUS_LABEL[status]}</span>
        {diff ? (
          <button
            type="button"
            className={`file-edit-toggle ${open ? "open" : ""}`}
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? "收起" : "查看改动"}
          </button>
        ) : null}
      </div>
      {open && diff ? (
        <pre className="file-edit-diff" aria-label="代码改动">
          {diff.split("\n").map((line, i) => {
            let cls = "diff-line";
            if (line.startsWith("+") && !line.startsWith("+++")) cls += " add";
            else if (line.startsWith("-") && !line.startsWith("---")) cls += " del";
            else if (line.startsWith("@@")) cls += " hunk";
            else if (line.startsWith("---") || line.startsWith("+++")) cls += " meta";
            return (
              <span key={`${i}-${line.slice(0, 12)}`} className={cls}>
                {line || " "}
              </span>
            );
          })}
        </pre>
      ) : null}
      {open && !diff && (status === "running" || status === "pending") ? (
        <div className="file-edit-pending">正在写入文件…</div>
      ) : null}
    </div>
  );
}
