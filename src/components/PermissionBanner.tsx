import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface PermissionRequest {
  id: number | string;
  title: string;
  detail: string;
  summary?: string;
}

interface Props {
  request: PermissionRequest | null;
  onDone: () => void;
  onError?: (message: string) => void;
}

function humanSummary(title: string, detail: string): string {
  try {
    const params = JSON.parse(detail) as {
      toolCall?: {
        title?: string;
        kind?: string;
        locations?: Array<{ path?: string }>;
      };
    };
    const tool = params.toolCall;
    const paths = (tool?.locations ?? [])
      .map((l) => l.path)
      .filter(Boolean)
      .slice(0, 3);
    const parts = [tool?.title || title];
    if (tool?.kind) parts.push(`类型：${tool.kind}`);
    if (paths.length) parts.push(`涉及：${paths.join("、")}`);
    return parts.filter(Boolean).join(" · ");
  } catch {
    return title;
  }
}

export function PermissionBanner({ request, onDone, onError }: Props) {
  const [busy, setBusy] = useState(false);
  const [showRaw, setShowRaw] = useState(false);
  if (!request) return null;

  const summary = request.summary || humanSummary(request.title, request.detail);

  async function respond(allow: boolean) {
    if (busy) return;
    setBusy(true);
    try {
      await invoke("respond_permission", { id: request!.id, allow });
      onDone();
    } catch (error) {
      const msg = String(error);
      onError?.(msg);
      if (msg.includes("过期") || msg.includes("不存在")) {
        onDone();
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="permission-banner permission-card permission-sticky">
      <div className="permission-body">
        <strong>需要批准</strong>
        <div className="permission-title">{request.title}</div>
        <p className="permission-summary">{summary}</p>
        {request.detail ? (
          <div className="permission-raw-wrap">
            <button
              type="button"
              className="linkish"
              onClick={() => setShowRaw((v) => !v)}
            >
              {showRaw ? "收起详情" : "查看原始请求"}
            </button>
            {showRaw ? <pre className="permission-detail">{request.detail}</pre> : null}
          </div>
        ) : null}
      </div>
      <div className="permission-actions">
        <button
          type="button"
          className="danger"
          disabled={busy}
          onClick={() => void respond(false)}
        >
          拒绝
        </button>
        <button
          type="button"
          className="send"
          disabled={busy}
          onClick={() => void respond(true)}
        >
          {busy ? "处理中…" : "允许"}
        </button>
      </div>
    </div>
  );
}
