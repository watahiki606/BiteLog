import { createMiddleware } from 'hono/factory';
import { importSPKI, jwtVerify, SignJWT } from 'jose';
import type { Bindings, Variables } from '../types';

const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const GOOGLE_KEYS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

// iOSアプリのBundle ID（Appleトークンのaud）
export const APPLE_BUNDLE_ID = 'com.watahiki.BiteLog';

// セッションJWT発行（有効期限30日）
export async function issueSessionJwt(userId: string, secret: string): Promise<string> {
  const key = new TextEncoder().encode(secret);
  return await new SignJWT({ sub: userId })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(key);
}

// セッションJWT検証
export async function verifySessionJwt(
  token: string,
  secret: string
): Promise<string> {
  const key = new TextEncoder().encode(secret);
  const { payload } = await jwtVerify(token, key);
  if (!payload.sub) throw new Error('No sub in JWT');
  return payload.sub;
}

// Apple identityToken検証（RS256）
// allowedAudiences: iOSのBundle IDとWeb用Services IDの両方を受理する
export async function verifyAppleToken(
  identityToken: string,
  allowedAudiences: string[]
): Promise<string> {
  const res = await fetch(APPLE_KEYS_URL);
  const { keys } = (await res.json()) as { keys: JsonWebKey[] };

  // ヘッダーからkidを取得して一致する公開鍵を探す
  const [headerB64] = identityToken.split('.');
  const header = JSON.parse(atob(headerB64));
  const jwk = keys.find((k: JsonWebKey & { kid?: string }) => k.kid === header.kid);
  if (!jwk) throw new Error('Apple key not found');

  const publicKey = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );

  const [, payloadB64, sigB64] = identityToken.split('.');
  const data = new TextEncoder().encode(`${identityToken.split('.').slice(0, 2).join('.')}`);
  const sig = Uint8Array.from(atob(sigB64.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, sig, data);
  if (!valid) throw new Error('Invalid Apple token signature');

  const payload = JSON.parse(atob(payloadB64));
  const now = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < now) throw new Error('Apple token expired');
  if (payload.iss !== 'https://appleid.apple.com') throw new Error('Invalid Apple token issuer');
  if (!allowedAudiences.includes(payload.aud)) throw new Error('Invalid Apple token audience');
  if (!payload.sub) throw new Error('No sub in Apple token');
  return `apple:${payload.sub}`;
}

// Google identityToken検証
// allowedAudiences: iOS用とWeb用のOAuthクライアントIDの両方を受理する
export async function verifyGoogleToken(
  identityToken: string,
  allowedAudiences: string[]
): Promise<string> {
  const res = await fetch(GOOGLE_KEYS_URL);
  const { keys } = (await res.json()) as { keys: JsonWebKey[] };

  const [headerB64] = identityToken.split('.');
  const header = JSON.parse(atob(headerB64));
  const jwk = keys.find((k: JsonWebKey & { kid?: string }) => k.kid === header.kid);
  if (!jwk) throw new Error('Google key not found');

  const publicKey = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );

  const [, payloadB64, sigB64] = identityToken.split('.');
  const data = new TextEncoder().encode(`${identityToken.split('.').slice(0, 2).join('.')}`);
  const sig = Uint8Array.from(atob(sigB64.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, sig, data);
  if (!valid) throw new Error('Invalid Google token signature');

  const payload = JSON.parse(atob(payloadB64));
  const now = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < now) throw new Error('Google token expired');
  // issはhttpsあり/なしの両形式がある (https://developers.google.com/identity/openid-connect/openid-connect#validatinganidtoken)
  if (payload.iss !== 'https://accounts.google.com' && payload.iss !== 'accounts.google.com') {
    throw new Error('Invalid Google token issuer');
  }
  if (!allowedAudiences.includes(payload.aud)) throw new Error('Invalid Google token audience');
  if (!payload.sub) throw new Error('No sub in Google token');
  return `google:${payload.sub}`;
}

// 認証ミドルウェア（全APIルートに適用）
export const authMiddleware = createMiddleware<{ Bindings: Bindings; Variables: Variables }>(
  async (c, next) => {
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }
    const token = authHeader.slice(7);

    try {
      const userId = await verifySessionJwt(token, c.env.WORKER_JWT_SECRET);
      c.set('userId', userId);
      c.set('isAdmin', !!c.env.ADMIN_USER_ID && userId === c.env.ADMIN_USER_ID);
      await next();
    } catch {
      return c.json({ error: 'Unauthorized' }, 401);
    }
  }
);
