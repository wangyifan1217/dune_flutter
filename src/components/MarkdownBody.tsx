import { invoke } from "@tauri-apps/api/core";
import { useState, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface MarkdownBodyProps {
  content: string;
  onOpenFile?: (path: string) => void;
}

/** 常见可打开扩展名（须含字母，避免把 V1.0 / 版本号当成文件） */
const OPENABLE_EXT =
  /(?:docx|xlsx|pptx|pdf|txt|md|markdown|csv|json|html?|css|js|jsx|ts|tsx|py|rs|go|java|c|cpp|h|hpp|xml|ya?ml|toml|sql|sh|log|png|jpe?g|gif|webp|svg|zip)$/i;

/** 会话里可点击打开的文件名/路径（含中文名如 测试.docx） */
export function looksLikeOpenableFile(raw: string): boolean {
  const path = raw.trim().replace(/^[`'"]+|[`'"]+$/g, "");
  if (!path || path.includes("://") || path.startsWith("//")) return false;
  if (path.length > 260) return false;
  // 标题/版本号：文档概要 (V1.0)、v1.2.3
  if (/[（(]\s*[vV]?\d+(?:\.\d+){0,3}\s*[）)]?$/.test(path)) return false;
  if (/^[vV]?\d+(?:\.\d+){1,3}$/.test(path)) return false;
  // 排除纯域名
  if (
    /^\.?[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(path) &&
    !path.includes("/") &&
    !path.includes("\\")
  ) {
    return false;
  }
  const base = path.split(/[/\\]/).pop() ?? path;
  const dot = base.lastIndexOf(".");
  if (dot <= 0) return false;
  const ext = base.slice(dot + 1);
  // 扩展名必须含字母，且在白名单内（拒绝 .0 / .1 等）
  if (!/[A-Za-z]/.test(ext)) return false;
  return OPENABLE_EXT.test(ext);
}

function isHttpUrl(href: string): boolean {
  return /^https?:\/\//i.test(href.trim());
}

function CodeBlock({
  className,
  children,
}: {
  className?: string;
  children?: ReactNode;
}) {
  const [copied, setCopied] = useState(false);
  const lang = /language-([\w+-]+)/.exec(className ?? "")?.[1] ?? "";
  const text = String(children ?? "").replace(/\n$/, "");

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1200);
    } catch {
      /* ignore */
    }
  }

  return (
    <div className="md-codeblock">
      <div className="md-codeblock-bar">
        <span className="md-codeblock-lang">{lang || "code"}</span>
        <button type="button" className="md-codeblock-copy" onClick={() => void copy()}>
          {copied ? "已复制" : "复制"}
        </button>
      </div>
      <pre>
        <code className={className}>{text}</code>
      </pre>
    </div>
  );
}

export function MarkdownBody({ content, onOpenFile }: MarkdownBodyProps) {
  return (
    <div className="md">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          pre: ({ children }) => <>{children}</>,
          a: ({ href, children }) => {
            const url = (href ?? "").trim();
            if (url && isHttpUrl(url)) {
              return (
                <button
                  type="button"
                  className="md-ext-link"
                  title={`在浏览器打开 ${url}`}
                  onClick={() => {
                    void invoke("open_url", { url }).catch(() => undefined);
                  }}
                >
                  {children}
                </button>
              );
            }
            if (url && onOpenFile && looksLikeOpenableFile(url)) {
              return (
                <button
                  type="button"
                  className="md-file-link"
                  title={`打开 ${url}`}
                  onClick={() => onOpenFile(url)}
                >
                  {children}
                </button>
              );
            }
            // 无法处理的 href：显示为普通文本，避免假链接
            return <span className="md-dead-link">{children}</span>;
          },
          code: ({ className, children, ...props }) => {
            const text = String(children ?? "").replace(/\n$/, "");
            const isBlock = Boolean(className) || text.includes("\n");
            if (!isBlock) {
              if (onOpenFile && looksLikeOpenableFile(text)) {
                return (
                  <button
                    type="button"
                    className="md-file-link"
                    title={`打开 ${text}`}
                    onClick={() => onOpenFile(text.trim())}
                  >
                    {text}
                  </button>
                );
              }
              return (
                <code className={className} {...props}>
                  {children}
                </code>
              );
            }
            return <CodeBlock className={className}>{children}</CodeBlock>;
          },
          strong: ({ children }) => {
            const text = String(children ?? "");
            if (onOpenFile && looksLikeOpenableFile(text)) {
              return (
                <button
                  type="button"
                  className="md-file-link"
                  title={`打开 ${text}`}
                  onClick={() => onOpenFile(text.trim())}
                >
                  {text}
                </button>
              );
            }
            return <strong>{children}</strong>;
          },
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}
