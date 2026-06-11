import { Hono } from 'hono';
import { APPLE_BUNDLE_ID, authMiddleware, issueSessionJwt, verifyAppleToken, verifyGoogleToken } from '../middleware/auth';
import type { Bindings, Variables } from '../types';

const auth = new Hono<{ Bindings: Bindings; Variables: Variables }>();

// POST /api/auth/signin
// Body: { provider: "apple" | "google", identityToken: string }
auth.post('/signin', async (c) => {
  let body: { provider: string; identityToken: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON' }, 400);
  }

  const { provider, identityToken } = body;
  if (!provider || !identityToken) {
    return c.json({ error: 'provider and identityToken are required' }, 400);
  }

  let userId: string;
  try {
    if (provider === 'apple') {
      userId = await verifyAppleToken(identityToken, [APPLE_BUNDLE_ID]);
    } else if (provider === 'google') {
      userId = await verifyGoogleToken(identityToken, [c.env.GOOGLE_CLIENT_ID]);
    } else {
      return c.json({ error: 'Unsupported provider' }, 400);
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
// 資格情報(管理キーまたはJWT)の有効性を確認する。管理画面のログイン検証に使う
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
