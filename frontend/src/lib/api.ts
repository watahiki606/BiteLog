import { hc } from 'hono/client';
import type { AppType } from '../../../cloudflare/src/index';
import { getToken, API_URL } from './auth';

export function createClient() {
  return hc<AppType>(API_URL, {
    headers: () => ({
      Authorization: `Bearer ${getToken()}`,
    }),
  });
}

export type Client = ReturnType<typeof createClient>;
