import { Hono } from 'hono';
import {
  APPLE_BUNDLE_ID,
  authMiddleware,
  exchangeGoogleAuthorizationCode,
  issueSessionJwt,
  verifyAppleToken,
  verifyGoogleToken,
} from '../middleware/auth';
import type { Bindings, Variables } from '../types';

const auth = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// POST /api/auth/signin
// Body: { provider: "apple" | "google", identityToken: string }
//     | { provider: "google", authorizationCode: string }  (Webのポップアップから)
auth.post('/signin', async (c) => {
  let body: { provider: string; identityToken?: string; authorizationCode?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const { provider, identityToken, authorizationCode } = body;

  let userId: string;
  try {
    if (provider === 'apple' && identityToken) {
      // iOSアプリ(Bundle ID)とWeb(Services ID)の両方を受理する
      const allowedAudiences = [APPLE_BUNDLE_ID, c.env.APPLE_WEB_SERVICE_ID].filter(
        (aud): aud is string => !!aud
      );
      userId = await verifyAppleToken(identityToken, allowedAudiences);
    } else if (provider === 'google' && (identityToken || authorizationCode)) {
      // Webはポップアップで得た認可コードを送ってくる。交換時のredirect_uriは呼び出し元のオリジン
      const googleToken = authorizationCode
        ? await exchangeGoogleAuthorizationCode(
            authorizationCode,
            c.env.GOOGLE_WEB_CLIENT_ID ?? '',
            c.env.GOOGLE_WEB_CLIENT_SECRET ?? '',
            c.req.header('Origin') ?? ''
          )
        : identityToken!;
      // iOS用とWeb用のOAuthクライアントIDの両方を受理する
      const allowedAudiences = [c.env.GOOGLE_CLIENT_ID, c.env.GOOGLE_WEB_CLIENT_ID].filter(
        (aud): aud is string => !!aud
      );
      userId = await verifyGoogleToken(googleToken, allowedAudiences);
    } else {
      return c.json({ error: 'provider and identityToken are required' }, 400);
    }
  } catch (err) {
    console.error('Token verification failed:', err);
    return c.json({ error: 'Invalid identity token' }, 401);
  }

  const sessionJwt = await issueSessionJwt(userId, c.env.WORKER_JWT_SECRET);
  const isAdmin = !!c.env.ADMIN_USER_ID && userId === c.env.ADMIN_USER_ID;
  return c.json({ token: sessionJwt, userId, isAdmin });
});

// GET /api/auth/verify
// セッションJWTの有効性を確認する。管理画面のログイン検証に使う
auth.get('/verify', authMiddleware, (c) => {
  return c.json({ userId: c.get('userId'), isAdmin: c.get('isAdmin') });
});

// POST /api/auth/refresh
// 現在有効なJWTで新しいJWT（30日）を発行する
auth.post('/refresh', authMiddleware, async (c) => {
  const userId = c.get('userId');
  const isAdmin = c.get('isAdmin');
  const sessionJwt = await issueSessionJwt(userId, c.env.WORKER_JWT_SECRET);
  return c.json({ token: sessionJwt, userId, isAdmin });
});

export default auth;
