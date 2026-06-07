import { motion } from 'motion/react';
import { clearToken } from '@/lib/auth';

type Tab = 'food' | 'log' | 'goals';

interface Props {
  activeTab: Tab;
  onTabChange: (tab: Tab) => void;
  onLogout: () => void;
}

const tabs: { id: Tab; label: string; icon: string }[] = [
  { id: 'food', label: 'FOOD MASTER', icon: '◈' },
  { id: 'log', label: 'MEAL LOG', icon: '◉' },
  { id: 'goals', label: 'NUTRITION', icon: '◇' },
];

export default function Sidebar({ activeTab, onTabChange, onLogout }: Props) {
  function handleLogout() {
    clearToken();
    onLogout();
  }

  return (
    <div
      className="w-52 flex-shrink-0 flex flex-col border-r border-border-dim bg-bg-surface"
      style={{ boxShadow: '2px 0 20px rgba(0,0,0,0.5)' }}
    >
      {/* ブランド */}
      <div className="px-5 py-6 border-b border-border-dim">
        <GlitchText text="BITELOG" />
        <div className="text-xs text-muted-foreground tracking-widest mt-1">ADMIN v2.0</div>
      </div>

      {/* ナビゲーション */}
      <nav className="flex-1 py-4">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className="relative w-full text-left px-5 py-3 text-xs tracking-widest transition-all duration-200 group"
            style={{
              color: activeTab === tab.id ? '#00e5ff' : '#6060a0',
              background: activeTab === tab.id ? 'rgba(0,229,255,0.05)' : 'transparent',
            }}
          >
            {activeTab === tab.id && (
              <motion.span
                layoutId="activeTab"
                className="absolute left-0 top-0 bottom-0 w-0.5 bg-neon-cyan"
                style={{ boxShadow: '0 0 8px #00e5ff' }}
              />
            )}
            <span className="mr-2 opacity-70">{tab.icon}</span>
            {tab.label}
            {activeTab === tab.id && (
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-neon-cyan opacity-50">›</span>
            )}
          </button>
        ))}
      </nav>

      {/* ログアウト */}
      <div className="px-5 py-4 border-t border-border-dim">
        <button
          onClick={handleLogout}
          className="w-full py-2 text-xs tracking-widest text-muted-foreground hover:text-destructive border border-border-dim hover:border-destructive transition-all duration-200 uppercase"
        >
          ⏻ Logout
        </button>
      </div>
    </div>
  );
}

function GlitchText({ text }: { text: string }) {
  return (
    <div className="relative">
      <span
        className="text-lg font-bold tracking-widest text-neon-cyan text-glow-cyan"
        data-text={text}
      >
        {text}
      </span>
    </div>
  );
}
