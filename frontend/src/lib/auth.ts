const TOKEN_KEY = 'bitelog_admin_token';
const API_URL_KEY = 'bitelog_api_url';

const DEFAULT_API_URL = 'https://bitelog-workers.v10acdict.workers.dev';

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

export function getApiUrl(): string {
  return localStorage.getItem(API_URL_KEY) ?? DEFAULT_API_URL;
}

export function setApiUrl(url: string): void {
  localStorage.setItem(API_URL_KEY, url);
}
