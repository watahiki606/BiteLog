import { useEffect, useRef, useState } from 'react';
import { motion } from 'motion/react';
import {
  isAppleLoginConfigured,
  isGoogleLoginConfigured,
  renderGoogleButton,
  signInWithApple,
} from '@/lib/socialAuth';

interface Props {
  onAuthenticated: () => void;
}

export default function SetupModal({ onAuthenticated }: Props) {
  const [error, setError] = useState('');
  const googleButtonRef = useRef<HTMLDivElement>(null);

  const googleEnabled = isGoogleLoginConfigured();
  const appleEnabled = isAppleLoginConfigured();
  const socialEnabled = googleEnabled || appleEnabled;

  useEffect(() => {
    if (!googleEnabled || !googleButtonRef.current) return;
    renderGoogleButton(
      googleButtonRef.current,
      onAuthenticated,
      () => setError('Googleサインインに失敗しました')
    ).catch(() => setError('Googleサインインの読み込みに失敗しました'));
  }, [googleEnabled, onAuthenticated]);

  async function handleAppleSignIn() {
    setError('');
    try {
      await signInWithApple();
      onAuthenticated();
    } catch (err) {
      // ユーザーがポップアップを閉じた場合もrejectされるため、メッセージは控えめにする
      if (err instanceof Error && err.message.includes('サインイン')) {
        setError(err.message);
      }
    }
  }

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-bg-deep neon-grid">
      <div className="scanlines" />

      <motion.div
        initial={{ opacity: 0, scale: 0.9, y: 20 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        transition={{ duration: 0.4, ease: 'easeOut' }}
        className="w-full max-w-sm"
      >
        <div
          className="bg-bg-surface border border-border-dim p-8 relative"
          style={{ boxShadow: '0 0 30px rgba(0,229,255,0.1), inset 0 0 30px rgba(0,0,0,0.5)' }}
        >
          {/* コーナーデコレーション */}
          <span className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-neon-cyan" />
          <span className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-neon-cyan" />
          <span className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-neon-cyan" />
          <span className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-neon-cyan" />

          <div className="mb-8 text-center">
            <div className="text-neon-cyan text-2xl font-bold tracking-widest text-glow-cyan mb-1">
              BITELOG
            </div>
            <div className="text-muted-foreground text-xs tracking-widest uppercase">
              Access Terminal
            </div>
          </div>

          {socialEnabled ? (
            <div className="space-y-3">
              {googleEnabled && (
                <div ref={googleButtonRef} className="flex justify-center" />
              )}
              {appleEnabled && (
                <motion.button
                  type="button"
                  onClick={handleAppleSignIn}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  className="w-full py-2.5 text-sm font-medium bg-white text-black flex items-center justify-center gap-2"
                  style={{ borderRadius: 4 }}
                >
                  <span aria-hidden="true"></span>
                  Appleでサインイン
                </motion.button>
              )}
            </div>
          ) : (
            <p className="text-xs text-muted-foreground tracking-wide">
              ソーシャルログインが設定されていません。VITE_GOOGLE_CLIENT_ID または
              VITE_APPLE_SERVICE_ID を設定してください。
            </p>
          )}

          {error && (
            <p className="text-xs text-destructive tracking-wide mt-4">{error}</p>
          )}
        </div>
      </motion.div>
    </div>
  );
}
