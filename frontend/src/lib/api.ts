import { hc } from 'hono/client';
import type { AppType } from '../../../cloudflare/src/index';
import { getToken, getApiUrl } from './auth';

export function createClient() {
  return hc<AppType>(getApiUrl(), {
    headers: () => ({
      Authorization: `Bearer ${getToken()}`,
    }),
  });
}

export type Client = ReturnType<typeof createClient>;
