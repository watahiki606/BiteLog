/// <reference types="@cloudflare/vitest-pool-workers" />
import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import app from '../index';

const IOS_BUNDLE_ID = 'com.watahiki.BiteLog';
const WEB_SERVICE_ID = 'com.watahiki.BiteLog.web';
const IOS_GOOGLE_CLIENT = 'ios-client.apps.googleusercontent.com';
const WEB_GOOGLE_CLIENT = 'web-client.apps.googleusercontent.com';
const WEB_GOOGLE_SECRET = 'web-client-secret';
const PAGE_ORIGIN = 'https://bitelog-web.pages.dev';

const TEST_ENV = {
  WORKER_JWT_SECRET: 'signin-test-secret',
  GOOGLE_CLIENT_ID: IOS_GOOGLE_CLIENT,
  GOOGLE_WEB_CLIENT_ID: WEB_GOOGLE_CLIENT,
  GOOGLE_WEB_CLIENT_SECRET: WEB_GOOGLE_SECRET,
  APPLE_WEB_SERVICE_ID: WEB_SERVICE_ID,
};

let privateKey: CryptoKey;
// Google のトークンエンドポイントに送られたフォームと、'valid-code' に対して返す ID トークン
let tokenExchangeForms: URLSearchParams[] = [];
let exchangedIdToken = '';

beforeAll(async () => {
  const pair = await generateKeyPair('RS256', { extractable: true });
  privateKey = pair.privateKey as CryptoKey;
  const publicJwk = {
    ...(await exportJWK(pair.publicKey as CryptoKey)),
    kid: 'test-kid',
    alg: 'RS256',
    use: 'sig',
  };

  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = input.toString();
    if (url === 'https://oauth2.googleapis.com/token') {
      const form = new URLSearchParams(init?.body as URLSearchParams);
      tokenExchangeForms.push(form);
      return form.get('code') === 'valid-code'
        ? Response.json({ id_token: exchangedIdToken })
        : Response.json({ error: 'invalid_grant' }, { status: 400 });
    }
    if (
      url === 'https://appleid.apple.com/auth/keys' ||
      url === 'https://www.googleapis.com/oauth2/v3/certs'
    ) {
      return Response.json({ keys: [publicJwk] });
    }
    throw new Error(`Unexpected fetch in test: ${url}`);
  });
});

afterAll(() => {
  vi.unstubAllGlobals();
});

async function signIdentityToken(iss: string, aud: string, sub: string): Promise<string> {
  return await new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid: 'test-kid' })
    .setIssuer(iss)
    .setAudience(aud)
    .setSubject(sub)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(privateKey);
}

function signin(provider: string, identityToken: string, env: object = TEST_ENV) {
  return app.request(
    '/api/auth/signin',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ provider, identityToken }),
    },
    env
  );
}

function signinWithGoogleCode(authorizationCode: string) {
  return app.request(
    '/api/auth/signin',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: PAGE_ORIGIN },
      body: JSON.stringify({ provider: 'google', authorizationCode }),
    },
    TEST_ENV
  );
}

describe('POST /api/auth/signin', () => {
  it('Googleの認可コードを、呼び出し元のオリジンを redirect_uri にして交換しサインインできる', async () => {
    tokenExchangeForms = [];
    exchangedIdToken = await signIdentityToken(
      'https://accounts.google.com', WEB_GOOGLE_CLIENT, 'g-sub'
    );
    const res = await signinWithGoogleCode('valid-code');

    expect(res.status).toBe(200);
    const body = await res.json<{ userId: string }>();
    expect(body.userId).toBe('google:g-sub');
    expect(Object.fromEntries(tokenExchangeForms[0])).toEqual({
      code: 'valid-code',
      client_id: WEB_GOOGLE_CLIENT,
      client_secret: WEB_GOOGLE_SECRET,
      redirect_uri: PAGE_ORIGIN,
      grant_type: 'authorization_code',
    });
  });

  it('Googleが認可コードを拒否したら401になる', async () => {
    const res = await signinWithGoogleCode('expired-code');
    expect(res.status).toBe(401);
  });

  it('Google WebクライアントIDのトークンでサインインできる', async () => {
    const token = await signIdentityToken(
      'https://accounts.google.com', WEB_GOOGLE_CLIENT, 'g-sub'
    );
    const res = await signin('google', token);

    expect(res.status).toBe(200);
    const body = await res.json<{ token: string; userId: string; isAdmin: boolean }>();
    expect(body.userId).toBe('google:g-sub');
    expect(body.token).toBeTruthy();
  });

  it('Apple Web Services IDのトークンでサインインできる', async () => {
    const token = await signIdentityToken(
      'https://appleid.apple.com', WEB_SERVICE_ID, 'a-sub'
    );
    const res = await signin('apple', token);

    expect(res.status).toBe(200);
    const body = await res.json<{ userId: string }>();
    expect(body.userId).toBe('apple:a-sub');
  });

  it('iOSのaudのトークンも引き続きサインインできる(回帰)', async () => {
    const apple = await signin(
      'apple',
      await signIdentityToken('https://appleid.apple.com', IOS_BUNDLE_ID, 'a-sub')
    );
    const google = await signin(
      'google',
      await signIdentityToken('https://accounts.google.com', IOS_GOOGLE_CLIENT, 'g-sub')
    );
    expect(apple.status).toBe(200);
    expect(google.status).toBe(200);
  });

  it('許可リスト外のaudのトークンは401になる', async () => {
    const res = await signin(
      'google',
      await signIdentityToken('https://accounts.google.com', 'evil-client', 'g-sub')
    );
    expect(res.status).toBe(401);
  });

  it('Web用ID未設定の環境でもiOSのaudは受理される', async () => {
    const envWithoutWebIds = {
      WORKER_JWT_SECRET: 'signin-test-secret',
      GOOGLE_CLIENT_ID: IOS_GOOGLE_CLIENT,
    };
    const res = await signin(
      'google',
      await signIdentityToken('https://accounts.google.com', IOS_GOOGLE_CLIENT, 'g-sub'),
      envWithoutWebIds
    );
    expect(res.status).toBe(200);
  });

  it('ADMIN_API_KEYと一致するパスワードをBearerに入れても401になる(パスワード認証は廃止)', async () => {
    const res = await app.request(
      '/api/auth/verify',
      { headers: { Authorization: 'Bearer legacy-admin-password' } },
      { ...TEST_ENV, ADMIN_API_KEY: 'legacy-admin-password' }
    );
    expect(res.status).toBe(401);
  });

  it('signinで得たトークンで /api/auth/verify が通る', async () => {
    const signinRes = await signin(
      'google',
      await signIdentityToken('https://accounts.google.com', WEB_GOOGLE_CLIENT, 'g-sub')
    );
    const { token } = await signinRes.json<{ token: string }>();

    const verifyRes = await app.request(
      '/api/auth/verify',
      { headers: { Authorization: `Bearer ${token}` } },
      TEST_ENV
    );

    expect(verifyRes.status).toBe(200);
    const body = await verifyRes.json<{ userId: string; isAdmin: boolean }>();
    expect(body.userId).toBe('google:g-sub');
    expect(body.isAdmin).toBe(false);
  });
});
