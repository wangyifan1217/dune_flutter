import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AuthSession, QrSession, QrStatus } from "../types/auth";

export function useAuth() {
  const [session, setSession] = useState<AuthSession | null>(null);
  const [ready, setReady] = useState(false);
  const [apiBase, setApiBaseState] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    void (async () => {
      try {
        const base = await invoke<string>("auth_get_api_base");
        if (alive) setApiBaseState(base);
        const restored = await invoke<AuthSession | null>("auth_restore_session");
        if (alive) setSession(restored);
      } catch (e) {
        if (alive) setError(String(e));
      } finally {
        if (alive) setReady(true);
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const setApiBase = useCallback(async (next: string) => {
    await invoke("auth_set_api_base", { apiBase: next });
    setApiBaseState(next.trim().replace(/\/$/, "") || next);
  }, []);

  const logout = useCallback(async () => {
    await invoke("auth_logout");
    setSession(null);
  }, []);

  const requestSms = useCallback(async (phone: string) => {
    await invoke("auth_request_sms", { phone });
  }, []);

  const signInSms = useCallback(async (phone: string, code: string) => {
    const next = await invoke<AuthSession>("auth_sign_in_sms", { phone, code });
    setSession(next);
    return next;
  }, []);

  const createQrSession = useCallback(async () => {
    return invoke<QrSession>("auth_create_qr_session");
  }, []);

  const pollQrStatus = useCallback(async (sessionId: string, clientSecret: string) => {
    return invoke<QrStatus>("auth_poll_qr_status", { sessionId, clientSecret });
  }, []);

  const signInQr = useCallback(async (sessionId: string, clientSecret: string) => {
    const next = await invoke<AuthSession>("auth_sign_in_qr", { sessionId, clientSecret });
    setSession(next);
    return next;
  }, []);

  return {
    ready,
    session,
    apiBase,
    error,
    setError,
    setApiBase,
    logout,
    requestSms,
    signInSms,
    createQrSession,
    pollQrStatus,
    signInQr,
  };
}
