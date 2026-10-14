import { useEffect, useRef, useState } from 'react';
import {
  isAppleLoginConfigured,
  isGoogleLoginConfigured,
  prepareGoogleSignIn,
  renderAppleButton,
} from '@/lib/socialAuth';

const DOCS_URL = 'https://bitelog-docs.pages.dev';

interface Props {
  onAuthenticated: () => void;
}

export default function SetupModal({ onAuthenticated }: Props) {
  const [error, setError] = useState('');
  const [startGoogleSignIn, setStartGoogleSignIn] = useState<() => void>();
  const appleButtonRef = useRef<HTMLDivElement>(null);

  const googleEnabled = isGoogleLoginConfigured();
  const appleEnabled = isAppleLoginConfigured();

  useEffect(() => {
    if (!googleEnabled) return;
    prepareGoogleSignIn(onAuthenticated, () => setError('Googleサインインに失敗しました'))
      .then((start) => setStartGoogleSignIn(() => start))
      .catch(() => setError('Googleサインインの読み込みに失敗しました'));
  }, [googleEnabled, onAuthenticated]);

  useEffect(() => {
    if (!appleEnabled || !appleButtonRef.current) return;
    return renderAppleButton(appleButtonRef.current, onAuthenticated, () =>
      setError('Appleサインインに失敗しました')
    );
  }, [appleEnabled, onAuthenticated]);

  return (
    <div className="fixed inset-0 flex items-center justify-center px-4 bg-bg-deep">
      <div className="w-full max-w-80 text-center">
        <h1 className="text-2xl font-bold tracking-widest text-foreground">BiteLog</h1>
        <p className="mt-2 text-sm text-muted-foreground">食事と体の記録をひとつに</p>

        <div className="mt-10 space-y-3">
          {googleEnabled && (
            // Apple公式ボタンと並べたときに揃うよう、高さ・角丸・文字の書体と大きさを合わせる。
            // 枠線と配色はGoogleのLightテーマの指定どおり
            <button
              type="button"
              onClick={() => startGoogleSignIn?.()}
              disabled={!startGoogleSignIn}
              className="flex h-10 w-full items-center justify-center gap-2 rounded bg-white text-[#1F1F1F] border border-[#747775] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-neon-cyan disabled:opacity-60"
              style={{ fontFamily: 'system-ui, -apple-system, sans-serif', fontSize: 16, fontWeight: 600 }}
            >
              <img src="/google-g.svg" alt="" width={18} height={18} />
              Googleでサインイン
            </button>
          )}
          {appleEnabled && <div ref={appleButtonRef} />}
        </div>

        {error && <p className="mt-4 text-xs text-destructive">{error}</p>}

        {!googleEnabled && !appleEnabled && (
          <p className="mt-4 text-xs text-muted-foreground">
            ソーシャルログインが設定されていません。VITE_GOOGLE_CLIENT_ID または
            VITE_APPLE_SERVICE_ID を設定してください。
          </p>
        )}

        <p className="mt-10 text-xs text-muted-foreground">
          <a href={`${DOCS_URL}/terms`} className="hover:text-foreground">
            利用規約
          </a>
          <span className="mx-2">·</span>
          <a href={`${DOCS_URL}/privacy`} className="hover:text-foreground">
            プライバシーポリシー
          </a>
        </p>
      </div>
    </div>
  );
}
