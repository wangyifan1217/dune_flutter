import { invoke } from "@tauri-apps/api/core";
import { useEffect, useMemo, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { IconX } from "./Icons";

export interface FilePreviewPayload {
  kind: string;
  path: string;
  name: string;
  text?: string | null;
  mime?: string | null;
  imageBase64?: string | null;
  slides?: Array<{ title: string; body: string }> | null;
  sheet?: string | null;
  headers?: string[] | null;
  rows?: string[][] | null;
  message?: string | null;
}

interface PreviewPaneProps {
  path: string | null;
  onClear: () => void;
  onOpenExternal: (path: string) => void;
  onError?: (message: string) => void;
}

export function PreviewPane({
  path,
  onClear,
  onOpenExternal,
  onError,
}: PreviewPaneProps) {
  const [payload, setPayload] = useState<FilePreviewPayload | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [htmlMode, setHtmlMode] = useState<"render" | "source">("render");

  useEffect(() => {
    if (!path) {
      setPayload(null);
      setError(null);
      setLoading(false);
      return;
    }
    let alive = true;
    setLoading(true);
    setError(null);
    setHtmlMode("render");
    void invoke<FilePreviewPayload>("preview_file", { path })
      .then((next) => {
        if (!alive) return;
        setPayload(next);
      })
      .catch((e) => {
        if (!alive) return;
        const msg = String(e);
        setError(msg);
        setPayload(null);
        onError?.(msg);
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [path]);

  if (!path) {
    return (
      <div className="preview-pane empty">
        <div className="preview-empty">
          <strong>预览</strong>
          <p>在对话或文件树中点击文件，将在此处预览</p>
        </div>
      </div>
    );
  }

  const title = payload?.name ?? path.split(/[/\\]/).pop() ?? path;
  const isHtml = payload?.kind === "html";

  return (
    <div className="preview-pane">
      <div className="preview-toolbar">
        <div className="preview-toolbar-meta" title={payload?.path ?? path}>
          <strong>{title}</strong>
          {payload?.sheet ? <span>表：{payload.sheet}</span> : null}
          {isHtml ? <span>HTML / Canvas</span> : null}
        </div>
        <div className="preview-toolbar-actions">
          {isHtml ? (
            <div className="preview-mode-toggle" role="tablist" aria-label="预览模式">
              <button
                type="button"
                className={htmlMode === "render" ? "active" : ""}
                onClick={() => setHtmlMode("render")}
              >
                效果
              </button>
              <button
                type="button"
                className={htmlMode === "source" ? "active" : ""}
                onClick={() => setHtmlMode("source")}
              >
                源码
              </button>
            </div>
          ) : null}
          <button
            type="button"
            className="settings-ghost-btn"
            disabled={!payload?.path && !path}
            onClick={() => onOpenExternal(payload?.path ?? path)}
          >
            系统打开
          </button>
          <button
            type="button"
            className="icon-x"
            aria-label="关闭预览"
            onClick={onClear}
          >
            <IconX size={16} />
          </button>
        </div>
      </div>

      <div className={`preview-body ${isHtml && htmlMode === "render" ? "flush" : ""}`}>
        {loading ? <div className="preview-status">加载中…</div> : null}
        {error ? <div className="preview-status error">{error}</div> : null}
        {!loading && !error && payload ? (
          <PreviewContent payload={payload} htmlMode={htmlMode} />
        ) : null}
      </div>
    </div>
  );
}

function PreviewContent({
  payload,
  htmlMode,
}: {
  payload: FilePreviewPayload;
  htmlMode: "render" | "source";
}) {
  if (payload.kind === "unsupported") {
    return (
      <div className="preview-status">
        {payload.message || "暂不支持预览"}
      </div>
    );
  }

  if (payload.kind === "html" && payload.text != null) {
    if (htmlMode === "source") {
      return <pre className="preview-code">{payload.text}</pre>;
    }
    return <HtmlPreviewFrame html={payload.text} title={payload.name} />;
  }

  if (payload.kind === "image" && payload.imageBase64 && payload.mime) {
    return (
      <div className="preview-image-wrap">
        <img
          src={`data:${payload.mime};base64,${payload.imageBase64}`}
          alt={payload.name}
        />
      </div>
    );
  }

  if (payload.kind === "markdown" && payload.text != null) {
    return (
      <div className="md preview-md">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{payload.text}</ReactMarkdown>
      </div>
    );
  }

  if (payload.kind === "pptx" && payload.slides) {
    return (
      <div className="preview-slides">
        {payload.slides.length === 0 ? (
          <div className="preview-status">未提取到幻灯片文本</div>
        ) : (
          payload.slides.map((slide, i) => (
            <article key={`${slide.title}-${i}`} className="preview-slide-card">
              <header>
                <span className="preview-slide-index">{i + 1}</span>
                <h4>{slide.title}</h4>
              </header>
              <p>{slide.body || "（空）"}</p>
            </article>
          ))
        )}
      </div>
    );
  }

  if (payload.kind === "xlsx") {
    const headers = payload.headers ?? [];
    const rows = payload.rows ?? [];
    const colCount = Math.max(
      headers.length,
      ...rows.map((r) => r.length),
      1,
    );
    const pad = (cells: string[]) => {
      const next = [...cells];
      while (next.length < colCount) next.push("");
      return next;
    };
    return (
      <div className="preview-table-wrap">
        <table className="preview-table">
          {headers.length > 0 ? (
            <thead>
              <tr>
                {pad(headers).map((h, i) => (
                  <th key={`h-${i}`}>{h || `列${i + 1}`}</th>
                ))}
              </tr>
            </thead>
          ) : null}
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td colSpan={colCount}>（空表或仅有表头）</td>
              </tr>
            ) : (
              rows.map((row, ri) => (
                <tr key={`r-${ri}`}>
                  {pad(row).map((cell, ci) => (
                    <td key={`c-${ri}-${ci}`}>{cell}</td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    );
  }

  if (payload.text != null) {
    return <pre className="preview-code">{payload.text}</pre>;
  }

  return <div className="preview-status">{payload.message || "无可预览内容"}</div>;
}

/** 沙箱 iframe 渲染 HTML/Canvas；仅允许脚本，隔离源站。 */
function HtmlPreviewFrame({ html, title }: { html: string; title: string }) {
  const srcDoc = useMemo(() => ensureHtmlDocument(html), [html]);

  return (
    <iframe
      className="preview-html-frame"
      title={title}
      sandbox="allow-scripts"
      srcDoc={srcDoc}
      referrerPolicy="no-referrer"
    />
  );
}

function ensureHtmlDocument(raw: string): string {
  const trimmed = raw.trim();
  if (/<html[\s>]/i.test(trimmed) || /<!doctype/i.test(trimmed)) {
    return trimmed;
  }
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;width:100%;height:100%;background:#0b0d12;}</style></head><body>${trimmed}</body></html>`;
}
