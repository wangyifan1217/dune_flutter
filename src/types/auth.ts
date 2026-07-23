export interface AuthSession {
  phone: string;
  userId: number;
  token: string;
  apiBase: string;
  roles: string[];
  displayName?: string | null;
  departmentId?: number | null;
  userType: string;
}

export interface QrSession {
  sessionId: string;
  clientSecret: string;
  qrCode: string;
  ttlSeconds: number;
}

export interface QrStatus {
  status: string;
  confirmedUserName?: string | null;
}
