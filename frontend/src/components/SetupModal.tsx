import { useState } from 'react';
import { motion } from 'motion/react';
import { setSession, API_URL } from '@/lib/auth';

interface Props {
  onAuthenticated: () => void;
}

export default function SetupModal({ onAuthenticated }: Props) {
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const res = await fetch(`${API_URL}/api/auth/verify`, {
        headers: { Authorization: `Bearer ${password}` },
      });

      if (!res.ok) {
        setError('認証失敗: パスワードを確認してください');
        setLoading(false);
        return;
      }

      const { userId, isAdmin } = (await res.json()) as { userId: string; isAdmin: boolean };
      setSession({ token: password, userId, isAdmin });
      onAuthenticated();
    } catch {
      setError('接続エラー: APIサーバーに到達できません');
      setLoading(false);
    }
  }

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-bg-deep cyber-grid">
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
              Admin Access Terminal
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs text-muted-foreground mb-1 tracking-wider uppercase">
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full bg-bg-card border border-border-dim px-3 py-2 text-sm text-foreground focus:outline-none focus:border-neon-cyan transition-colors"
                style={{ fontFamily: 'inherit' }}
                placeholder="••••••••"
                autoFocus
              />
            </div>

            {error && (
              <p className="text-xs text-destructive tracking-wide">{error}</p>
            )}

            <motion.button
              type="submit"
              disabled={loading || !password}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              className="w-full py-2 text-sm font-bold tracking-widest uppercase transition-all disabled:opacity-40"
              style={{
                background: loading ? 'transparent' : 'rgba(0,229,255,0.1)',
                border: '1px solid #00e5ff',
                color: '#00e5ff',
                boxShadow: loading ? 'none' : '0 0 15px rgba(0,229,255,0.3)',
              }}
            >
              {loading ? 'CONNECTING...' : 'LOGIN'}
            </motion.button>
          </form>
        </div>
      </motion.div>
    </div>
  );
}
