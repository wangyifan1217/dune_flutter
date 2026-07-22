import { useEffect } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

interface FilePreviewProps {
  path: string;
  content: string;
  onBack: () => void;
}

export function FilePreview({ path, content, onBack }: FilePreviewProps) {
  const name = path.split(/[/\\]/).pop() ?? path;
  const isMarkdown = /\.(md|markdown)$/i.test(name);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onBack();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onBack]);

  return (
    <div className="file-preview-screen">
      <header className="file-preview-top">
        <button type="button" className="back-btn" onClick={onBack}>
          ← 返回对话
        </button>
        <div className="file-preview-meta">
          <strong title={path}>{name}</strong>
          <span>Esc 也可返回</span>
        </div>
      </header>
      <div className="file-preview-scroll">
        {isMarkdown ? (
          <div className="md file-preview-md">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
          </div>
        ) : (
          <pre className="file-preview-code">{content}</pre>
        )}
      </div>
    </div>
  );
}
