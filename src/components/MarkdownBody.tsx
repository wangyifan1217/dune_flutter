import { useState, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface MarkdownBodyProps {
  content: string;
  onOpenFile?: (path: string) => void;
}

/** 会话里可点击打开的文件名/路径（含中文名如 测试.docx） */
export function looksLikeOpenableFile(raw: string): boolean {
  const path = raw.trim().replace(/^[`'"]+|[`'"]+$/g, "");
  if (!path || path.includes("://") || path.startsWith("//")) return false;
  if (path.length > 260) return false;
  // 排除纯域名
  if (/^\.?[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(path) && !path.includes("/") && !path.includes("\\")) {
    return false;
  }
  return /\.[A-Za-z0-9]{1,12}$/.test(path);
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
