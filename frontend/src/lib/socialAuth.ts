import { API_URL, setSession, type Session } from './auth';

// Google Identity Services / Sign in with Apple JS の型(必要な範囲のみ)
declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize(config: {
            client_id: string;
            callback: (response: { credential: string }) => void;
          }): void;
          renderButton(
            parent: HTMLElement,
            options: { theme: string; size: string; width: number; text: string }
          ): void;
        };
      };
    };
    AppleID?: {
      auth: {
        init(config: {
          clientId: string;
          scope: string;
          redirectURI: string;
          usePopup: boolean;
        }): void;
        signIn(): Promise<{ authorization: { id_token: string } }>;
      };
    };
  }
}

const GIS_SRC = 'https://accounts.google.com/gsi/client';
const APPLE_SRC =
  'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/ja_JP/appleid.auth.js';

const scriptPromises = new Map<string, Promise<void>>();

function loadScript(src: string): Promise<void> {
  let promise = scriptPromises.get(src);
  if (!promise) {
    promise = new Promise<void>((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.async = true;
      script.onload = () => resolve();
      script.onerror = () => {
        scriptPromises.delete(src);
        reject(new Error(`Failed to load ${src}`));
      };
      document.head.appendChild(script);
    });
    scriptPromises.set(src, promise);
  }
  return promise;
}

export function isGoogleLoginConfigured(): boolean {
  return !!import.meta.env.VITE_GOOGLE_CLIENT_ID;
}

// AppleのReturn URLにlocalhostは登録できないため、ローカル開発では無効化する
export function isAppleLoginConfigured(): boolean {
  return !!import.meta.env.VITE_APPLE_SERVICE_ID && window.location.protocol === 'https:';
}

// identityTokenをWorkerに送ってセッションJWTを取得・保存する
async function signinWithIdentityToken(
  provider: 'apple' | 'google',
  identityToken: string
): Promise<Session> {
  const res = await fetch(`${API_URL}/api/auth/signin`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ provider, identityToken }),
  });
  if (!res.ok) {
    throw new Error('サインインに失敗しました');
  }
  const { token, userId, isAdmin } = (await res.json()) as {
    token: string;
    userId: string;
    isAdmin: boolean;
  };
  const session = { token, userId, isAdmin };
  setSession(session);
  return session;
}

// Google公式ボタンを描画する(GISはカスタムボタンからのID取得を許可していない)
export async function renderGoogleButton(
  container: HTMLElement,
  onSuccess: () => void,
  onError: (err: unknown) => void
): Promise<void> {
  const clientId = import.meta.env.VITE_GOOGLE_CLIENT_ID;
  if (!clientId) return;

  await loadScript(GIS_SRC);
  window.google!.accounts.id.initialize({
    client_id: clientId,
    callback: async (response) => {
      try {
        await signinWithIdentityToken('google', response.credential);
        onSuccess();
      } catch (err) {
        onError(err);
      }
    },
  });
  window.google!.accounts.id.renderButton(container, {
    theme: 'filled_black',
    size: 'large',
    width: 280,
    text: 'signin_with',
  });
}

export async function signInWithApple(): Promise<Session> {
  const serviceId = import.meta.env.VITE_APPLE_SERVICE_ID;
  if (!serviceId) {
    throw new Error('Apple Sign-Inが設定されていません');
  }

  await loadScript(APPLE_SRC);
  window.AppleID!.auth.init({
    clientId: serviceId,
    scope: '',
    redirectURI: import.meta.env.VITE_APPLE_REDIRECT_URI ?? window.location.origin,
    usePopup: true,
  });
  const { authorization } = await window.AppleID!.auth.signIn();
  return await signinWithIdentityToken('apple', authorization.id_token);
}
