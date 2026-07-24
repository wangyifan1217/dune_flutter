import { invoke } from "@tauri-apps/api/core";
import { useState } from "react";

const INSTALL_COMMAND = "curl -fsSL https://x.ai/cli/install.sh | bash";
const DOCS_URL = "https://docs.x.ai/build/overview";

interface GrokSetupModalProps {
  open: boolean;
  checking?: boolean;
  onRecheck: () => Promise<void>;
}

export function GrokSetupModal({
  open,
  checking = false,
  onRecheck,
}: GrokSetupModalProps) {
  const [copied, setCopied] = useState(false);

  if (!open) return null;

  async function copyCommand() {
    try {
      const { writeText } = await import("@tauri-apps/plugin-clipboard-manager");
      await writeText(INSTALL_COMMAND);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      // 复制失败时仍保留可选中的命令文本。
    }
  }

  return (
    <div className="modal-backdrop grok-setup-backdrop">
      <section className="grok-setup" role="dialog" aria-modal="true" aria-label="安装 Grok">
        <div className="grok-setup-mark">G</div>
        <h1>安装 Grok Agent</h1>
        <p>
          Nova Build 需要 Grok Agent 执行代码任务。请在“终端”中运行下方官方安装命令，
          完成后回到这里重新检测。
        </p>
        <div className="grok-setup-command">
          <code>{INSTALL_COMMAND}</code>
          <button type="button" className="text-btn" onClick={() => void copyCommand()}>
            {copied ? "已复制" : "复制"}
          </button>
        </div>
        <div className="grok-setup-actions">
          <button
            type="button"
            className="text-btn"
            onClick={() => void invoke("open_url", { url: DOCS_URL })}
          >
            打开官方安装说明
          </button>
          <button
            type="button"
            className="primary-btn"
            disabled={checking}
            onClick={() => void onRecheck()}
          >
            {checking ? "正在检测…" : "我已安装，重新检测"}
          </button>
        </div>
      </section>
    </div>
  );
}
