import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { ModelEntry } from "../types/agent";
import { modelLabelOf } from "../types/agent";

interface ModelPickerProps {
  modelId: string;
  models: ModelEntry[];
  onChange: (modelId: string) => void;
  onManage?: () => void;
}

export function ModelPicker({
  modelId,
  models,
  onChange,
  onManage,
}: ModelPickerProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [pos, setPos] = useState<{ left: number; bottom: number } | null>(null);

  useLayoutEffect(() => {
    if (!open || !triggerRef.current) {
      setPos(null);
      return;
    }
    const rect = triggerRef.current.getBoundingClientRect();
    setPos({
      left: Math.min(rect.left, window.innerWidth - 280),
      bottom: window.innerHeight - rect.top + 8,
    });
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      const t = e.target as Node;
      if (rootRef.current?.contains(t)) return;
      const pop = document.getElementById("nova-model-popover");
      if (pop?.contains(t)) return;
      setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    const onResize = () => setOpen(false);
    document.addEventListener("mousedown", onDoc);
    window.addEventListener("keydown", onKey);
    window.addEventListener("resize", onResize);
    window.addEventListener("scroll", onResize, true);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("resize", onResize);
      window.removeEventListener("scroll", onResize, true);
    };
  }, [open]);

  return (
    <div className="model-picker" ref={rootRef}>
      <button
        ref={triggerRef}
        type="button"
        className={`tool-chip model-trigger ${open ? "open" : ""}`}
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-haspopup="listbox"
      >
        <span className="model-trigger-label">
          {modelLabelOf(models, modelId) || "选择模型"}
        </span>
        <span className="chev">▾</span>
      </button>

      {open &&
        pos &&
        createPortal(
          <div
            id="nova-model-popover"
            className="model-popover model-popover-portal"
            role="listbox"
            style={{ left: pos.left, bottom: pos.bottom }}
          >
            <div className="model-popover-title">切换模型</div>
            {models.length === 0 ? (
              <div className="model-empty">
                还没有模型，请先在设置里添加
                {onManage && (
                  <button
                    type="button"
                    className="text-btn"
                    onClick={() => {
                      setOpen(false);
                      onManage();
                    }}
                  >
                    去设置
                  </button>
                )}
              </div>
            ) : (
              models.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  role="option"
                  className={`model-option ${modelId === m.id ? "selected" : ""}`}
                  onClick={() => {
                    onChange(m.id);
                    setOpen(false);
                  }}
                >
                  <span className="model-option-text">
                    <span className="model-option-label">{m.label || m.id}</span>
                    {m.label && m.label !== m.id ? (
                      <span className="model-option-id">{m.id}</span>
                    ) : null}
                  </span>
                  {modelId === m.id ? <span className="check">✓</span> : null}
                </button>
              ))
            )}
            {onManage && (
              <button
                type="button"
                className="model-manage"
                onClick={() => {
                  setOpen(false);
                  onManage();
                }}
              >
                管理模型…
              </button>
            )}
            <p className="model-hint">
              同一 new-api Key；切换后下一条消息会重连 Agent。查天气等实时信息需启用 Fetch MCP，且网关对该模型支持工具调用。
            </p>
          </div>,
          document.body,
        )}
    </div>
  );
}
