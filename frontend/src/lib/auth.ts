const TOKEN_KEY = 'bitelog_admin_token';
const USER_KEY = 'bitelog_session_user';

export const API_URL =
  import.meta.env.VITE_API_URL ?? 'https://bitelog-workers.v10acdict.workers.dev';

export interface Session {
  token: string;
  userId: string;
  isAdmin: boolean;
}

export function getToken(): string {
  return sessionStorage.getItem(TOKEN_KEY) ?? '';
}

export function setSession(session: Session): void {
  sessionStorage.setItem(TOKEN_KEY, session.token);
  sessionStorage.setItem(
    USER_KEY,
    JSON.stringify({ userId: session.userId, isAdmin: session.isAdmin })
  );
}

export function getSession(): Session | null {
  const token = getToken();
  const user = sessionStorage.getItem(USER_KEY);
  if (!token || !user) return null;
  try {
    const { userId, isAdmin } = JSON.parse(user) as { userId: string; isAdmin: boolean };
    return { token, userId, isAdmin };
  } catch {
    return null;
  }
}

export function clearSession(): void {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(USER_KEY);
}
