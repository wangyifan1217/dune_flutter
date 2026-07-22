interface IconRailProps {
  leftMode: "threads" | "files" | "settings";
  onNew: () => void;
  onMode: (mode: "threads" | "files" | "settings") => void;
  onToggleRight: () => void;
  rightOpen: boolean;
}

export function IconRail({
  leftMode,
  onNew,
  onMode,
  onToggleRight,
  rightOpen,
}: IconRailProps) {
  return (
    <nav className="icon-rail">
      <button
        type="button"
        className="icon-btn primary"
        title="新对话 (Ctrl+N)"
        onClick={onNew}
      >
        +
      </button>
      <button
        type="button"
        className={`icon-btn ${leftMode === "threads" ? "active" : ""}`}
        title="对话"
        onClick={() => onMode("threads")}
      >
        ≡
      </button>
      <button
        type="button"
        className={`icon-btn ${leftMode === "files" ? "active" : ""}`}
        title="文件"
        onClick={() => onMode("files")}
      >
        ⌕
      </button>
      <div className="icon-spacer" />
      <button
        type="button"
        className={`icon-btn ${rightOpen ? "active" : ""}`}
        title="审阅面板"
        onClick={onToggleRight}
      >
        ▥
      </button>
      <button
        type="button"
        className={`icon-btn ${leftMode === "settings" ? "active" : ""}`}
        title="设置"
        onClick={() => onMode("settings")}
      >
        ⚙
      </button>
    </nav>
  );
}
