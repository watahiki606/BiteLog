const TOKEN_KEY = 'bitelog_admin_token';

export const API_URL =
  import.meta.env.VITE_API_URL ?? 'https://bitelog-workers.v10acdict.workers.dev';

export function getToken(): string {
  return sessionStorage.getItem(TOKEN_KEY) ?? '';
}

export function setToken(token: string): void {
  sessionStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  sessionStorage.removeItem(TOKEN_KEY);
}

export function isAuthenticated(): boolean {
  return getToken().length > 0;
}
