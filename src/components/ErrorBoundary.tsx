import { Component, type ErrorInfo, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  error: string | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: unknown): State {
    return { error: String(error) };
  }

  componentDidCatch(error: unknown, info: ErrorInfo) {
    console.error("UI crash:", error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        <div
          style={{
            padding: 24,
            color: "#fecaca",
            background: "#0b0d12",
            height: "100%",
            fontFamily: "Segoe UI, Microsoft YaHei, sans-serif",
          }}
        >
          <h2 style={{ marginTop: 0 }}>界面出错</h2>
          <pre style={{ whiteSpace: "pre-wrap" }}>{this.state.error}</pre>
          <button
            type="button"
            onClick={() => window.location.reload()}
            style={{
              marginTop: 12,
              padding: "8px 14px",
              borderRadius: 8,
              border: "none",
              background: "#5865f2",
              color: "#fff",
              cursor: "pointer",
            }}
          >
            刷新界面
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
