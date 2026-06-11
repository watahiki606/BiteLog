import { hc } from 'hono/client';
import type { AppType } from '../../../cloudflare/src/index';
import { getToken, clearSession, API_URL } from './auth';

export function createClient() {
  return hc<AppType>(API_URL, {
    headers: () => ({
      Authorization: `Bearer ${getToken()}`,
    }),
    // セッションJWT失効時はログイン画面に戻す
    fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
      const res = await fetch(input, init);
      if (res.status === 401) {
        clearSession();
        window.location.reload();
      }
      return res;
    },
  });
}

export type Client = ReturnType<typeof createClient>;
