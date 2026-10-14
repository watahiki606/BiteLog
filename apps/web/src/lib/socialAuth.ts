import { API_URL, setSession, type Session } from './auth';

// Google Identity Services / Sign in with Apple JS の型(必要な範囲のみ)
declare global {
  interface Window {
    google?: {
      accounts: {
        oauth2: {
          initCodeClient(config: {
            client_id: string;
            scope: string;
            ux_mode: 'popup';
            callback: (response: { code?: string; error?: string }) => void;
            error_callback: (error: { type: string }) => void;
          }): { requestCode(): void };
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
        renderButton(): void;
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

// AppleのidentityTokenかGoogleの認可コードをWorkerに送ってセッションJWTを取得・保存する
async function signin(
  credential:
    | { provider: 'apple'; identityToken: string }
    | { provider: 'google'; authorizationCode: string }
): Promise<Session> {
  const res = await fetch(`${API_URL}/api/auth/signin`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(credential),
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

// Googleのポップアップを開く関数を返す。ポップアップはクリックと同じ流れで開かないとブロックされるため、
// スクリプトの読み込みと初期化は先に済ませておく。
// 公式ボタン部品(renderButton)は中身をGoogleが描き、形を揃えられないため使わない
export async function prepareGoogleSignIn(
  onSuccess: () => void,
  onError: (err: unknown) => void
): Promise<() => void> {
  const clientId = import.meta.env.VITE_GOOGLE_CLIENT_ID;
  if (!clientId) throw new Error('VITE_GOOGLE_CLIENT_ID is not set');

  await loadScript(GIS_SRC);
  const client = window.google!.accounts.oauth2.initCodeClient({
    client_id: clientId,
    // Workerが使うのはIDトークンのsubだけなので、メールやプロフィールは求めない
    scope: 'openid',
    ux_mode: 'popup',
    callback: async ({ code, error }) => {
      if (!code) {
        if (error !== 'access_denied') onError(new Error(error));
        return;
      }
      try {
        await signin({ provider: 'google', authorizationCode: code });
        onSuccess();
      } catch (err) {
        onError(err);
      }
    },
    error_callback: ({ type }) => {
      if (type !== 'popup_closed') onError(new Error(type));
    },
  });
  return () => client.requestCode();
}

// Apple公式ボタンを描画する。ロゴはApple配布の素材以外を使えないため、自前で描かない。
// 結果はdocumentへのイベントで届くので、購読を解除する関数を返す
export function renderAppleButton(
  container: HTMLElement,
  onSuccess: () => void,
  onError: (err: unknown) => void
): () => void {
  const serviceId = import.meta.env.VITE_APPLE_SERVICE_ID;
  if (!serviceId) return () => {};

  const handleSuccess = async (event: Event) => {
    const { authorization } = (event as CustomEvent<{ authorization: { id_token: string } }>)
      .detail;
    try {
      await signin({ provider: 'apple', identityToken: authorization.id_token });
      onSuccess();
    } catch (err) {
      onError(err);
    }
  };
  const handleFailure = (event: Event) => {
    const { error } = (event as CustomEvent<{ error: string }>).detail;
    if (error !== 'popup_closed_by_user') onError(new Error(error));
  };
  document.addEventListener('AppleIDSignInOnSuccess', handleSuccess);
  document.addEventListener('AppleIDSignInOnFailure', handleFailure);

  // 暗い背景では白しか使えない。左寄せモードは width: 100% で文字が折り返すため中央寄せにする。
  // 角丸は高さに対する % で、10 が 4px
  container.id = 'appleid-signin';
  Object.assign(container.dataset, {
    mode: 'center-align',
    type: 'sign-in',
    color: 'white',
    border: 'false',
    borderRadius: '10',
    width: '100%',
    height: '40',
  });

  loadScript(APPLE_SRC)
    .then(() => {
      window.AppleID!.auth.init({
        clientId: serviceId,
        scope: '',
        redirectURI: import.meta.env.VITE_APPLE_REDIRECT_URI ?? window.location.origin,
        usePopup: true,
      });
      window.AppleID!.auth.renderButton();
    })
    .catch(onError);

  return () => {
    document.removeEventListener('AppleIDSignInOnSuccess', handleSuccess);
    document.removeEventListener('AppleIDSignInOnFailure', handleFailure);
  };
}
