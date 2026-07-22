import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface PermissionRequest {
  id: number | string;
  title: string;
  detail: string;
}

interface Props {
  request: PermissionRequest | null;
  onDone: () => void;
  onError?: (message: string) => void;
}

export function PermissionBanner({ request, onDone, onError }: Props) {
  const [busy, setBusy] = useState(false);
  if (!request) return null;

  async function respond(allow: boolean) {
    if (busy) return;
    setBusy(true);
    try {
      await invoke("respond_permission", { id: request!.id, allow });
      onDone();
    } catch (error) {
      const msg = String(error);
      onError?.(msg);
      // 过期也关掉横幅，避免一直卡住
      if (msg.includes("过期") || msg.includes("不存在")) {
        onDone();
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="permission-banner">
      <div className="permission-body">
        <strong>需要批准</strong>
        <div className="permission-title">{request.title}</div>
        {request.detail && <pre className="permission-detail">{request.detail}</pre>}
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
