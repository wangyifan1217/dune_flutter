import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { MemoryEntry } from "../types/memory";
import { ConfirmDialog } from "./ConfirmDialog";
import { IconX } from "./Icons";

interface MemoryModalProps {
  open: boolean;
  onClose: () => void;
}

export function MemoryModal({ open, onClose }: MemoryModalProps) {
  const [memories, setMemories] = useState<MemoryEntry[]>([]);
  const [memoryDraft, setMemoryDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pendingClear, setPendingClear] = useState(false);
  const [pendingDeleteId, setPendingDeleteId] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setPendingClear(false);
    setPendingDeleteId(null);
    setMemoryDraft("");
    void invoke<MemoryEntry[]>("list_memories")
      .then(setMemories)
      .catch((e) => {
        setMemories([]);
        setError(String(e));
      });
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      e.preventDefault();
      e.stopPropagation();
      if (pendingClear || pendingDeleteId) {
        setPendingClear(false);
        setPendingDeleteId(null);
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [open, pendingClear, pendingDeleteId]);

  if (!open) return null;

  async function refresh() {
    const list = await invoke<MemoryEntry[]>("list_memories");
    setMemories(list);
  }

  async function addMemory() {
    const text = memoryDraft.trim();
    if (!text) return;
    try {
      await invoke("add_memory", { content: text, source: "user" });
      setMemoryDraft("");
      setError(null);
      await refresh();
    } catch (e) {
      setError(String(e));
    }
  }

  async function confirmRemove() {
    if (!pendingDeleteId) return;
    try {
      await invoke("delete_memory", { id: pendingDeleteId });
      setPendingDeleteId(null);
      await refresh();
    } catch (e) {
      setError(String(e));
      setPendingDeleteId(null);
    }
  }

  async function confirmClear() {
    try {
      await invoke("clear_memories");
      setPendingClear(false);
      await refresh();
    } catch (e) {
      setError(String(e));
      setPendingClear(false);
    }
  }

  return (
    <div
      className="modal-backdrop nested-modal"
      role="presentation"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) e.preventDefault();
      }}
    >
      <div
        className="modal-sheet memory-modal"
        role="dialog"
        aria-modal="true"
        aria-label="永久记忆"
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="modal-head">
          <div>
            <h2>永久记忆</h2>
            <p>
              写入磁盘，重启仍在；每次对话会自动带上。也可在输入框发送「记住：xxx」。
              注意：这与「工具与 MCP」里的 Memory 工具不是同一套存储。
            </p>
          </div>
          <button type="button" className="icon-x" onClick={onClose} aria-label="关闭">
            <IconX size={16} />
          </button>
        </div>

        {error ? (
          <p className="hint" style={{ color: "#b42318" }}>
            {error}
          </p>
        ) : null}

        <div className="settings-modal-body">
          <label>
            新增一条
            <textarea
              rows={3}
              value={memoryDraft}
              placeholder="例如：我偏好 TypeScript + Tauri"
              onChange={(e) => setMemoryDraft(e.target.value)}
            />
          </label>
          <button
            type="button"
            className="text-btn block"
            disabled={!memoryDraft.trim()}
            onClick={() => void addMemory()}
          >
            + 保存记忆
          </button>

          <div className="sidebar-label-row spaced">
            <div className="sidebar-label">已保存 {memories.length}</div>
            <button
              type="button"
              className="linkish"
              disabled={memories.length === 0}
              onClick={() => setPendingClear(true)}
            >
              清空
            </button>
          </div>
          <div className="memory-list">
            {memories.length === 0 && <div className="empty-hint">还没有记忆</div>}
            {memories.map((m) => (
              <div key={m.id} className="memory-row">
                <p>{m.content}</p>
                <button
                  type="button"
                  className="linkish"
                  onClick={() => setPendingDeleteId(m.id)}
                >
                  删除
                </button>
              </div>
            ))}
          </div>
        </div>

        <div className="modal-foot">
          <button type="button" className="primary-btn" onClick={onClose}>
            完成
          </button>
        </div>
      </div>

      <ConfirmDialog
        open={pendingDeleteId != null}
        title="删除记忆？"
        message="确定删除这条永久记忆？"
        confirmLabel="删除"
        danger
        onCancel={() => setPendingDeleteId(null)}
        onConfirm={() => void confirmRemove()}
      />

      <ConfirmDialog
        open={pendingClear}
        title="清空全部记忆？"
        message="将删除所有永久记忆，此操作不可撤销。"
        confirmLabel="清空"
        danger
        onCancel={() => setPendingClear(false)}
        onConfirm={() => void confirmClear()}
      />
    </div>
  );
}
