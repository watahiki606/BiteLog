/// <reference types="@cloudflare/vitest-pool-workers" />
import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { verifyAppleToken, verifyGoogleToken } from './auth';

const IOS_BUNDLE_ID = 'com.watahiki.BiteLog';
const WEB_SERVICE_ID = 'com.watahiki.BiteLog.web';
const IOS_GOOGLE_CLIENT = 'ios-client.apps.googleusercontent.com';
const WEB_GOOGLE_CLIENT = 'web-client.apps.googleusercontent.com';

let privateKey: CryptoKey;

beforeAll(async () => {
  const pair = await generateKeyPair('RS256', { extractable: true });
  privateKey = pair.privateKey as CryptoKey;
  const publicJwk = {
    ...(await exportJWK(pair.publicKey as CryptoKey)),
    kid: 'test-kid',
    alg: 'RS256',
    use: 'sig',
  };

  // Apple/GoogleのJWKS取得をモック
  vi.stubGlobal('fetch', async (input: RequestInfo | URL) => {
    const url = input.toString();
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

async function signIdentityToken(opts: {
  iss: string;
  aud: string;
  sub?: string;
  expiresIn?: string;
}): Promise<string> {
  return await new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid: 'test-kid' })
    .setIssuer(opts.iss)
    .setAudience(opts.aud)
    .setSubject(opts.sub ?? 'user-123')
    .setIssuedAt()
    .setExpirationTime(opts.expiresIn ?? '1h')
    .sign(privateKey);
}

// 署名中間のビットを反転する（末尾文字はbase64urlの詰め物ビットのみの場合があり改ざんにならない）
function tamperSignature(token: string): string {
  const [h, p, sig] = token.split('.');
  const i = 10;
  const flipped = sig[i] === 'A' ? 'B' : 'A';
  return `${h}.${p}.${sig.slice(0, i)}${flipped}${sig.slice(i + 1)}`;
}

describe('verifyAppleToken', () => {
  const allowed = [IOS_BUNDLE_ID, WEB_SERVICE_ID];

  it('iOSバンドルIDのaudを持つトークンを受理する(回帰)', async () => {
    const token = await signIdentityToken({
      iss: 'https://appleid.apple.com',
      aud: IOS_BUNDLE_ID,
      sub: 'apple-sub-1',
    });
    expect(await verifyAppleToken(token, allowed)).toBe('apple:apple-sub-1');
  });

  it('許可リストに含まれるWeb Services IDのaudを受理する', async () => {
    const token = await signIdentityToken({
      iss: 'https://appleid.apple.com',
      aud: WEB_SERVICE_ID,
      sub: 'apple-sub-1',
    });
    expect(await verifyAppleToken(token, allowed)).toBe('apple:apple-sub-1');
  });

  it('許可リスト外のaudは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://appleid.apple.com',
      aud: 'com.evil.app',
    });
    await expect(verifyAppleToken(token, allowed)).rejects.toThrow();
  });

  it('期限切れトークンは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://appleid.apple.com',
      aud: IOS_BUNDLE_ID,
      expiresIn: '-1h',
    });
    await expect(verifyAppleToken(token, allowed)).rejects.toThrow();
  });

  it('issが不正なトークンは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://evil.example.com',
      aud: IOS_BUNDLE_ID,
    });
    await expect(verifyAppleToken(token, allowed)).rejects.toThrow();
  });

  it('署名が不正なトークンは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://appleid.apple.com',
      aud: IOS_BUNDLE_ID,
    });
    await expect(verifyAppleToken(tamperSignature(token), allowed)).rejects.toThrow();
  });
});

describe('verifyGoogleToken', () => {
  const allowed = [IOS_GOOGLE_CLIENT, WEB_GOOGLE_CLIENT];

  it('iOSクライアントIDのaudを持つトークンを受理する(回帰)', async () => {
    const token = await signIdentityToken({
      iss: 'https://accounts.google.com',
      aud: IOS_GOOGLE_CLIENT,
      sub: 'google-sub-1',
    });
    expect(await verifyGoogleToken(token, allowed)).toBe('google:google-sub-1');
  });

  it('許可リストに含まれるWebクライアントIDのaudを受理する', async () => {
    const token = await signIdentityToken({
      iss: 'https://accounts.google.com',
      aud: WEB_GOOGLE_CLIENT,
      sub: 'google-sub-1',
    });
    expect(await verifyGoogleToken(token, allowed)).toBe('google:google-sub-1');
  });

  it('iss が accounts.google.com (httpsなし) のトークンも受理する', async () => {
    const token = await signIdentityToken({
      iss: 'accounts.google.com',
      aud: WEB_GOOGLE_CLIENT,
      sub: 'google-sub-1',
    });
    expect(await verifyGoogleToken(token, allowed)).toBe('google:google-sub-1');
  });

  it('許可リスト外のaudは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://accounts.google.com',
      aud: 'other-client.apps.googleusercontent.com',
    });
    await expect(verifyGoogleToken(token, allowed)).rejects.toThrow();
  });

  it('期限切れトークンは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://accounts.google.com',
      aud: IOS_GOOGLE_CLIENT,
      expiresIn: '-1h',
    });
    await expect(verifyGoogleToken(token, allowed)).rejects.toThrow();
  });

  it('署名が不正なトークンは拒否する', async () => {
    const token = await signIdentityToken({
      iss: 'https://accounts.google.com',
      aud: IOS_GOOGLE_CLIENT,
    });
    await expect(verifyGoogleToken(tamperSignature(token), allowed)).rejects.toThrow();
  });
});
