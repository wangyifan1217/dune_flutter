import { useCallback, useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import type { AuthSession } from "../types/auth";

interface LoginPageProps {
  onRequestSms: (phone: string) => Promise<void>;
  onSignInSms: (phone: string, code: string) => Promise<AuthSession>;
  onCreateQr: () => Promise<{
    sessionId: string;
    clientSecret: string;
    qrCode: string;
    ttlSeconds: number;
  }>;
  onPollQr: (
    sessionId: string,
    clientSecret: string,
  ) => Promise<{ status: string; confirmedUserName?: string | null }>;
  onSignInQr: (sessionId: string, clientSecret: string) => Promise<AuthSession>;
}

type Mode = "qr" | "sms";

export function LoginPage({
  onRequestSms,
  onSignInSms,
  onCreateQr,
  onPollQr,
  onSignInQr,
}: LoginPageProps) {
  const [mode, setMode] = useState<Mode>("qr");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [smsSent, setSmsSent] = useState(false);
  const [cooldown, setCooldown] = useState(0);

  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [qrHint, setQrHint] = useState("正在生成二维码…");
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const pollInFlight = useRef(false);
  const qrAlive = useRef(true);
  const swipeStart = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    if (cooldown <= 0) return;
    const t = setTimeout(() => setCooldown((c) => c - 1), 1000);
    return () => clearTimeout(t);
  }, [cooldown]);

  const stopPoll = useCallback(() => {
    if (pollRef.current) {
      clearInterval(pollRef.current);
      pollRef.current = null;
    }
  }, []);

  const startQr = useCallback(async () => {
    stopPoll();
    qrAlive.current = true;
    setError(null);
    setQrDataUrl(null);
    setQrHint("正在生成二维码…");
    try {
      const session = await onCreateQr();
      if (!qrAlive.current) return;
      if (!session.qrCode) throw new Error("未返回二维码内容");
      const url = await QRCode.toDataURL(session.qrCode, {
        width: 220,
        margin: 2,
        color: { dark: "#111111", light: "#ffffff" },
      });
      if (!qrAlive.current) return;
      setQrDataUrl(url);
      setQrHint("请使用沙丘 App 扫码确认");

      const expiresAt = Date.now() + (session.ttlSeconds || 120) * 1000;
      pollRef.current = setInterval(() => {
        if (pollInFlight.current) return;
        pollInFlight.current = true;
        void (async () => {
          try {
            if (Date.now() > expiresAt) {
              stopPoll();
              setQrHint("二维码已过期，请刷新");
              setQrDataUrl(null);
              return;
            }
            const st = await onPollQr(session.sessionId, session.clientSecret);
            if (!qrAlive.current) return;
            if (st.status === "CONFIRMED") {
              stopPoll();
              setQrHint(
                st.confirmedUserName
                  ? `${st.confirmedUserName} 已确认，正在登录…`
                  : "已确认，正在登录…",
              );
              setBusy(true);
              try {
                await onSignInQr(session.sessionId, session.clientSecret);
              } catch (e) {
                setError(String(e));
                setQrHint("登录失败，请刷新二维码");
              } finally {
                setBusy(false);
              }
            } else if (st.status === "EXPIRED" || st.status === "CONSUMED") {
              stopPoll();
              setQrHint("二维码已失效，请刷新");
              setQrDataUrl(null);
            }
          } catch (e) {
            console.warn(e);
          } finally {
            pollInFlight.current = false;
          }
        })();
      }, 1800);
    } catch (e) {
      setError(String(e));
      setQrHint("生成失败，请刷新重试");
    }
  }, [onCreateQr, onPollQr, onSignInQr, stopPoll]);

  useEffect(() => {
    if (mode !== "qr") {
      qrAlive.current = false;
      stopPoll();
      return;
    }
    void startQr();
    return () => {
      qrAlive.current = false;
      stopPoll();
    };
  }, [mode, startQr, stopPoll]);

  async function handleSendSms() {
    setError(null);
    setBusy(true);
    try {
      await onRequestSms(phone.trim());
      setSmsSent(true);
      setCooldown(60);
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function handleSmsLogin() {
    setError(null);
    setBusy(true);
    try {
      await onSignInSms(phone.trim(), code.trim());
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  const canSend = !busy && cooldown <= 0 && phone.length === 11;

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-brand">Nova Build</div>
        <h1>登录后继续</h1>
        <p className="login-sub">使用沙丘 App 扫码，或手机号验证码登录</p>

        <div className={`login-tabs ${mode === "sms" ? "sms" : "qr"}`} role="tablist">
          <span className="login-tabs-thumb" aria-hidden />
          <button
            type="button"
            role="tab"
            aria-selected={mode === "qr"}
            className={mode === "qr" ? "active" : ""}
            onClick={() => setMode("qr")}
          >
            App 扫码
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === "sms"}
            className={mode === "sms" ? "active" : ""}
            onClick={() => setMode("sms")}
          >
            手机号登录
          </button>
        </div>

        {error && <div className="login-error">{error}</div>}

        <div
          className="login-panels"
          onPointerDown={(e) => {
            const t = e.target as HTMLElement | null;
            if (t?.closest("input, textarea, button, a, label")) {
              swipeStart.current = null;
              return;
            }
            if (e.pointerType === "mouse" && e.button !== 0) return;
            swipeStart.current = { x: e.clientX, y: e.clientY };
          }}
          onPointerUp={(e) => {
            const start = swipeStart.current;
            swipeStart.current = null;
            if (!start) return;
            const dx = e.clientX - start.x;
            const dy = e.clientY - start.y;
            if (Math.abs(dx) < 56 || Math.abs(dx) < Math.abs(dy) * 1.4) return;
            if (dx < 0 && mode === "qr") setMode("sms");
            if (dx > 0 && mode === "sms") setMode("qr");
          }}
          onPointerCancel={() => {
            swipeStart.current = null;
          }}
        >
          <div className={`login-panels-track mode-${mode}`}>
            <div className="login-panel">
              <div className="login-qr">
                <div className="login-qr-frame">
                  {qrDataUrl ? (
                    <img src={qrDataUrl} alt="登录二维码" width={220} height={220} />
                  ) : (
                    <div className="login-qr-placeholder">{qrHint}</div>
                  )}
                </div>
                <p className="login-hint">{qrHint}</p>
                <button type="button" className="text-btn" onClick={() => void startQr()} disabled={busy}>
                  刷新二维码
                </button>
              </div>
            </div>
            <div className="login-panel">
              <div className="login-sms">
                <label>
                  手机号
                  <input
                    value={phone}
                    onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 11))}
                    placeholder="11 位手机号"
                    inputMode="numeric"
                  />
                </label>
                <label>
                  验证码
                  <div className="login-code-field">
                    <input
                      value={code}
                      onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                      placeholder="6 位验证码"
                      inputMode="numeric"
                    />
                    <button
                      type="button"
                      className="login-sms-send"
                      disabled={!canSend}
                      onClick={() => void handleSendSms()}
                    >
                      {cooldown > 0 ? `${cooldown}s` : smsSent ? "重新发送" : "获取验证码"}
                    </button>
                  </div>
                </label>
                <button
                  type="button"
                  className="primary-btn login-submit"
                  disabled={busy || phone.length !== 11 || code.length !== 6}
                  onClick={() => void handleSmsLogin()}
                >
                  {busy ? "登录中…" : "登录"}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
