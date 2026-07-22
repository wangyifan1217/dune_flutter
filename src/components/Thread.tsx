import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { ChatMessage } from "../types/agent";

const STARTER_PROMPTS = [
  { title: "分析代码", detail: "解释这个项目的结构和关键模块", prompt: "帮我分析这个项目的代码结构和关键模块。" },
  { title: "实现功能", detail: "描述需求后开始开发", prompt: "我想实现一个新功能，请先帮我梳理实现方案：" },
  { title: "定位问题", detail: "粘贴报错或说明异常现象", prompt: "帮我定位并修复这个问题：" },
  { title: "审阅代码", detail: "检查改动与潜在风险", prompt: "请审阅当前项目的代码改动，并指出风险和改进建议。" },
];

function extractOpenableUrls(content: string): string[] {
  const matches = content.match(/https?:\/\/[^\s`*<>|"')\]]+/g) ?? [];
  return [
    ...new Set(
      matches.map((url) => url.replace(/[，。；：）】,.]+$/u, "")),
    ),
  ].slice(0, 6);
}

function isLikelyFilePath(path: string, urls: string[]): boolean {
  if (!path || path.includes("://") || path.startsWith("//")) return false;
  // 域名片段，如 .com.cn/weather/... 或 www.example.com/a.html
  if (/^\.?[a-z0-9-]+(?:\.[a-z0-9-]+)+[\\/]/i.test(path)) return false;
  if (urls.some((url) => url.includes(path))) return false;
  return /\.[A-Za-z0-9]{1,12}$/.test(path);
}

function extractGeneratedPaths(content: string): string[] {
  const urls = extractOpenableUrls(content);
  // 先挖掉 URL，避免把 https://... 拆成 s:/、//www.weather 这类假路径
  const masked = content.replace(/https?:\/\/[^\s`*<>|"')\]]+/g, (url) =>
    " ".repeat(url.length),
  );
  const matches = [
    ...(masked.match(
      /(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\r\n`*<>|?"]+?\.[A-Za-z0-9]{1,12}/g,
    ) ?? []),
    ...(masked.match(
      /(?:\.{1,2}[\\/]|[\\/]|(?:[\w-]+[\\/]))[^\s`*<>|?"]+?\.[A-Za-z0-9]{1,12}/g,
    ) ?? []),
  ];
  return [
    ...new Set(
      matches
        .map((path) => path.replace(/[，。；：）】]+$/u, ""))
        .filter((path) => isLikelyFilePath(path, urls)),
    ),
  ]
    .filter(
      (path, _i, all) =>
        !all.some((other) => other !== path && other.endsWith(path)),
    )
    .slice(0, 8);
}

interface ThreadProps {
  messages: ChatMessage[];
  busy?: boolean;
  progress?: string;
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

export function Thread({ messages, busy = false, progress }: ThreadProps) {
  if (messages.length === 0) {
    return (
      <div className="thread-empty">
        <img className="hero-logo" src="/nova-build-logo.png" alt="Nova Build" />
        <h1>今天想做什么？</h1>
        <p>从下面开始，或直接输入你的需求</p>
        <div className="starter-prompts">
          {STARTER_PROMPTS.map((item) => (
            <button
              type="button"
              className="starter-prompt"
              key={item.title}
              onClick={() =>
                window.dispatchEvent(
                  new CustomEvent<string>("nova:prompt-suggestion", { detail: item.prompt }),
                )
              }
            >
              <strong>{item.title}</strong>
              <span>{item.detail}</span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="thread">
      {messages.map((message) => {
        if (message.role === "user") {
          return (
            <div key={message.id} className="msg msg-user">
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
                          📄 {attachment.name}
                        </span>
                      ),
                    )}
                  </div>
                ) : null}
                {message.content ? <div>{message.content}</div> : null}
              </div>
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
        return (
          <div key={message.id} className="msg msg-assistant">
            <div className="msg-label">
              Nova Build
              {message.status === "streaming" ? <i className="live" /> : null}
            </div>
            <div className="md">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {message.content}
              </ReactMarkdown>
            </div>
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
                      title={`用系统默认程序打开 ${path}`}
                      onClick={() => {
                        if (confirm(`用系统默认程序打开此文件？\n${path}`)) {
                          void invoke("open_generated_file", { path });
                        }
                      }}
                    >
                      ↗ 打开 {path}
                    </button>
                  ))}
                  {urls.map((url) => (
                    <button
                      key={url}
                      type="button"
                      title={`在浏览器打开 ${url}`}
                      onClick={() => {
                        void invoke("open_url", { url }).catch((error) => {
                          window.alert(`无法打开链接：${String(error)}`);
                        });
                      }}
                    >
                      🌐 打开 {url}
                    </button>
                  ))}
                </div>
              );
            })()}
          </div>
        );
      })}
      {busy ? <ProgressIndicator progress={progress} /> : null}
    </div>
  );
}
