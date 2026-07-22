import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";

interface TerminalViewProps {
  active: boolean;
  cwd?: string | null;
}

export function TerminalView({ active, cwd }: TerminalViewProps) {
  const hostRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitRef = useRef<FitAddon | null>(null);
  const started = useRef(false);

  useEffect(() => {
    if (!active || !hostRef.current || termRef.current) return;

    const term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
      theme: {
        background: "#111111",
        foreground: "#f5f5f5",
        cursor: "#ffffff",
      },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(hostRef.current);
    fit.fit();
    termRef.current = term;
    fitRef.current = fit;

    const unsubs: Array<() => void> = [];
    void listen<string>("terminal://data", (event) => {
      term.write(event.payload);
    }).then((u) => unsubs.push(u));

    void listen("terminal://exit", () => {
      term.writeln("\r\n[终端已退出]");
      started.current = false;
    }).then((u) => unsubs.push(u));

    term.onData((data) => {
      void invoke("terminal_write", { data });
    });

    const onResize = () => {
      fit.fit();
      void invoke("terminal_resize", {
        rows: term.rows,
        cols: term.cols,
      });
    };
    window.addEventListener("resize", onResize);

    return () => {
      window.removeEventListener("resize", onResize);
      unsubs.forEach((u) => u());
      term.dispose();
      termRef.current = null;
    };
  }, [active]);

  useEffect(() => {
    if (!active) return;
    if (started.current) return;
    started.current = true;
    void invoke("terminal_start", { cwd: cwd ?? null }).catch((err) => {
      started.current = false;
      termRef.current?.writeln(`\r\n启动失败: ${String(err)}`);
    });
    const t = setTimeout(() => {
      fitRef.current?.fit();
      if (termRef.current) {
        void invoke("terminal_resize", {
          rows: termRef.current.rows,
          cols: termRef.current.cols,
        });
      }
    }, 50);
    return () => clearTimeout(t);
  }, [active, cwd]);

  return <div className="terminal-host" ref={hostRef} />;
}
