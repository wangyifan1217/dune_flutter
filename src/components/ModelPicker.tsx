import { useEffect, useRef, useState } from "react";
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

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, [open]);

  return (
    <div className="model-picker" ref={rootRef}>
      <button
        type="button"
        className="tool-chip model-trigger"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
      >
        {modelLabelOf(models, modelId)}
        <span className="chev">▾</span>
      </button>

      {open && (
        <div className="model-popover" role="listbox">
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
          <p className="model-hint">同一 new-api Key；切换后会重连 Agent</p>
        </div>
      )}
    </div>
  );
}
