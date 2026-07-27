import { useEffect, useState, type ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { ChatMessage } from "../types/agent";
import { CHAT_MODE_PREFIX } from "../types/agent";
import { IconCopy, IconEdit, IconFile, IconRetry } from "./Icons";
import { looksLikeOpenableFile, MarkdownBody } from "./MarkdownBody";
import { ToolCallCard } from "./ToolCallCard";

export function displayUserContent(content: string): string {
  let text = content;
  for (const prefix of Object.values(CHAT_MODE_PREFIX)) {
    if (prefix && text.startsWith(prefix)) {
      text = text.slice(prefix.length);
      break;
    }
  }
  return text;
}

const STARTER_PROMPTS = [
  {
    title: "做一份 PPT",
    detail: "用内置 PowerPoint 工具生成幻灯片",
    prompt:
      "请使用 PowerPoint MCP 在当前工作区创建一份简洁的汇报幻灯片（.pptx），主题由你根据上下文拟定或先问我确认，并在完成后给出可打开的文件路径。",
  },
  {
    title: "生成 Excel",
    detail: "创建或分析表格",
    prompt:
      "请使用 Excel MCP 帮我处理表格：若需新建请创建 .xlsx 并写入示例结构；若已有附件/路径请先读取再分析。完成后给出文件路径。",
  },
  {
    title: "联网查资料",
    detail: "Fetch 抓取网页再总结",
    prompt:
      "请使用 Fetch 工具抓取以下页面或公开资料并总结要点（如需我补充 URL 请先问我）：",
  },
  {
    title: "分析代码",
    detail: "解释项目结构与关键模块",
    prompt: "帮我分析这个项目的代码结构和关键模块。",
  },
  {
    title: "规划方案",
    detail: "先出计划再动手",
    prompt: "我想实现一个新功能，请先给出实现计划。",
    mode: "plan" as const,
  },
  {
    title: "审阅改动",
    detail: "检查风险与改进点",
    prompt: "请审阅当前项目的代码改动，并指出风险和改进建议。",
  },
];

function extractOpenableUrls(content: string): string[] {
  const matches = content.match(/https?:\/\/[^\s`*<>|"')\]]+/g) ?? [];
  return [
    ...new Set(matches.map((url) => url.replace(/[，。；：）】,.]+$/u, ""))),
  ].slice(0, 6);
}

function isLikelyFilePath(path: string, urls: string[]): boolean {
  if (!looksLikeOpenableFile(path)) return false;
  if (urls.some((url) => url.includes(path))) return false;
  return true;
}

function extractGeneratedPaths(content: string): string[] {
  const urls = extractOpenableUrls(content);
  const masked = content.replace(/https?:\/\/[^\s`*<>|"')\]]+/g, (url) =>
    " ".repeat(url.length),
  );
  const matches = [
    ...(masked.match(
      /(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\r\n`*<>|?"]+?\.[A-Za-z0-9]{1,12}/g,
    ) ?? []),
    ...(masked.match(
      /(?:\.{1,2}[\\/]|[\\/]|(?:[\w.-]+[\\/]))[^\s`*<>|?"']+?\.[A-Za-z0-9]{1,12}/g,
    ) ?? []),
    // 裸文件名（含中文）：测试.docx、报告.xlsx
    ...(masked.match(
      /(?<![\w./\\-])(?:[`"'【「]?)([^\s`"'「」【】:\\/<>|*?]+\.[A-Za-z0-9]{1,12})(?:[`"'」】]?)/gu,
    ) ?? []),
  ];
  return [
    ...new Set(
      matches
        .map((path) =>
          path
            .replace(/^[`'"【「]+|[`'"」】]+$/gu, "")
            .replace(/[，。；：）】]+$/u, "")
            .trim(),
        )
        .filter((path) => isLikelyFilePath(path, urls)),
    ),
  ]
    .filter(
      (path, _i, all) =>
        !all.some((other) => other !== path && other.endsWith(path) && other.length > path.length),
    )
    .slice(0, 8);
}

async function openPath(
  path: string,
  onOpenFile?: (path: string) => void,
  onError?: (message: string) => void,
) {
  if (onOpenFile) {
    onOpenFile(path);
    return;
  }
  try {
    await invoke("open_generated_file", { path });
  } catch (error) {
    onError?.(`无法打开文件：${String(error)}`);
  }
}

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    /* ignore */
  }
}

interface ThreadProps {
  messages: ChatMessage[];
  busy?: boolean;
  progress?: string;
  onApprovePlan?: () => void;
  onRevisePlan?: () => void;
  onStarter?: (prompt: string, mode?: "agent" | "plan" | "ask") => void;
  /** 按消息轮次重试：传入 assistant / error 的 messageId */
  onRetry?: (messageId: string) => void;
  /** 编辑用户消息：回填并进入「从此重发」模式 */
  onEditUser?: (messageId: string, text: string) => void;
  /** 打开可预览文件（右侧面板）；未提供时回退系统打开 */
  onOpenFile?: (path: string) => void;
  onOpenError?: (message: string) => void;
}

function ProgressIndicator({ progress }: { progress?: string }) {
  const [seconds, setSeconds] = useState(0);

  useEffect(() => {
    const startedAt = Date.now();
    const timer = window.setInterval(() => {
      setSeconds(Math.floor((Date.now() - startedAt) / 1000));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [progress]);

  const title = progress?.trim() || "正在处理请求";

  return (
    <div className="msg msg-progress" role="status">
      <i className="live" />
      <div>
        <strong>{title}</strong>
        <span>
          {seconds > 0 ? `已等待 ${seconds} 秒` : "请稍候"}
          {seconds >= 30
            ? " · 若一直无响应，可点终止后重试，并检查 API Key / Base URL"
            : ""}
        </span>
      </div>
    </div>
  );
}

function MessageActions({
  children,
  alwaysVisible = false,
}: {
  children: ReactNode;
  alwaysVisible?: boolean;
}) {
  return (
    <div className={`msg-actions ${alwaysVisible ? "always-visible" : ""}`}>
      {children}
    </div>
  );
}

export function Thread({
  messages,
  busy = false,
  progress,
  onApprovePlan,
  onRevisePlan,
  onStarter,
  onRetry,
  onEditUser,
  onOpenFile,
  onOpenError,
}: ThreadProps) {
  if (messages.length === 0) {
    return (
      <div className="thread-empty">
        <img className="hero-logo" src="/nova-build-logo.png" alt="Nova Build" />
        <h1>今天想做什么？</h1>
        <p>
          选一个场景开始；已内置 PPT / Excel / 联网等工具。输入 <code>/</code> 用技能，
          <code>@</code> 引用文件；可用「记住：…」写入永久记忆
        </p>
        <div className="starter-prompts">
          {STARTER_PROMPTS.map((item) => (
            <button
              type="button"
              className="starter-prompt"
              key={item.title}
              onClick={() => {
                if (onStarter) {
                  onStarter(item.prompt, item.mode);
                  return;
                }
                window.dispatchEvent(
                  new CustomEvent<string>("nova:prompt-suggestion", {
                    detail: item.prompt,
                  }),
                );
              }}
            >
              <strong>{item.title}</strong>
              <span>{item.detail}</span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  const lastPlanId = [...messages].reverse().find((m) => m.kind === "plan")?.id;
  // 已有流式正文时，用消息旁绿点表示生成中，不再在文字下方重复挂「正在生成」条
  const hasStreamingReply = messages.some(
    (m) =>
      m.role === "assistant" &&
      m.status === "streaming" &&
      m.kind !== "tool" &&
      m.kind !== "plan" &&
      m.kind !== "error",
  );
  const showProgress = busy && !hasStreamingReply;

  return (
    <div className="thread">
      {messages.map((message) => {
        if (message.kind === "tool") {
          return <ToolCallCard key={message.id} message={message} />;
        }

        if (message.role === "user") {
          const plain = displayUserContent(message.content);
          return (
            <div key={message.id} className="msg msg-user has-actions">
              <div className="msg-body">
                {message.attachments?.length ? (
                  <div className="message-attachments">
                    {message.attachments.map((attachment) =>
                      attachment.mimeType.startsWith("image/") ? (
                        <img
                          key={attachment.id}
                          src={`data:${attachment.mimeType};base64,${attachment.data}`}
                          alt={attachment.name}
                        />
                      ) : (
                        <span className="message-file" key={attachment.id}>
                          <IconFile size={14} /> {attachment.name}
                        </span>
                      ),
                    )}
                  </div>
                ) : null}
                {message.content ? <div>{plain}</div> : null}
              </div>
              <MessageActions>
                <button
                  type="button"
                  onClick={() => void copyText(plain)}
                  title="复制"
                  aria-label="复制"
                >
                  <IconCopy size={14} />
                </button>
                {onEditUser && !busy ? (
                  <button
                    type="button"
                    onClick={() => onEditUser(message.id, plain)}
                    title="编辑并从此重发"
                    aria-label="编辑并从此重发"
                  >
                    <IconEdit size={14} />
                  </button>
                ) : null}
              </MessageActions>
            </div>
          );
        }

        if (message.kind === "error" || (message.role === "system" && message.status === "error")) {
          return (
            <div key={message.id} className="msg msg-error">
              <div className="msg-error-body">
                <strong>出错了</strong>
                <p>{message.content}</p>
              </div>
              {onRetry && !busy ? (
                <button
                  type="button"
                  className="settings-ghost-btn msg-error-retry"
                  onClick={() => onRetry(message.id)}
                >
                  重试本轮
                </button>
              ) : null}
            </div>
          );
        }

        if (message.role === "system") {
          return (
            <div key={message.id} className="msg msg-tool">
              {message.content}
            </div>
          );
        }

        if (message.kind === "plan") {
          const entries =
            message.planEntries?.length
              ? message.planEntries
              : message.content
                  .split("\n")
                  .map((l) => l.replace(/^•\s*/, "").trim())
                  .filter(Boolean);
          const isLatest = message.id === lastPlanId && !busy;
          return (
            <div key={message.id} className="msg msg-plan">
              <div className="msg-label">
                <span className="plan-badge">规划</span>
                Nova Build
              </div>
              <div className="plan-card">
                <ol className="plan-steps">
                  {entries.map((step, i) => (
                    <li key={`${message.id}-${i}`}>{step}</li>
                  ))}
                </ol>
                {isLatest ? (
                  <div className="plan-actions">
                    <button
                      type="button"
                      className="primary-btn"
                      onClick={onApprovePlan}
                    >
                      按此执行
                    </button>
                    <button type="button" className="text-btn" onClick={onRevisePlan}>
                      修订计划
                    </button>
                  </div>
                ) : null}
              </div>
            </div>
          );
        }

        return (
          <div key={message.id} className="msg msg-assistant has-actions">
            <div className="msg-label">
              Nova Build
              {message.status === "streaming" ? <i className="live" /> : null}
            </div>
            <MarkdownBody
              content={message.content}
              onOpenFile={(path) => void openPath(path, onOpenFile, onOpenError)}
            />
            {(() => {
              const paths = extractGeneratedPaths(message.content);
              const urls = extractOpenableUrls(message.content);
              if (paths.length === 0 && urls.length === 0) return null;
              return (
                <div className="generated-files">
                  {paths.map((path) => (
                    <button
                      key={path}
                      type="button"
                      className="generated-file-chip"
                      title={`预览 ${path}`}
                      onClick={() => void openPath(path, onOpenFile, onOpenError)}
                    >
                      <IconFile size={13} />
                      <span>{path.split(/[/\\]/).pop() ?? path}</span>
                    </button>
                  ))}
                  {urls.map((url) => (
                    <button
                      key={url}
                      type="button"
                      className="generated-file-chip"
                      title={`在浏览器打开 ${url}`}
                      onClick={() => {
                        void invoke("open_url", { url }).catch((error) => {
                          onOpenError?.(`无法打开链接：${String(error)}`);
                        });
                      }}
                    >
                      打开链接
                    </button>
                  ))}
                </div>
              );
            })()}
            {message.status !== "streaming" ? (
              <MessageActions alwaysVisible={message.status === "error"}>
                <button
                  type="button"
                  onClick={() => void copyText(message.content)}
                  title="复制"
                  aria-label="复制"
                >
                  <IconCopy size={14} />
                </button>
                {onRetry && !busy ? (
                  <button
                    type="button"
                    onClick={() => onRetry(message.id)}
                    title="重试本轮"
                    aria-label="重试本轮"
                  >
                    <IconRetry size={14} />
                  </button>
                ) : null}
              </MessageActions>
            ) : null}
          </div>
        );
      })}
      {showProgress ? <ProgressIndicator progress={progress} /> : null}
    </div>
  );
}
