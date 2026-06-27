import { Link, Outlet } from 'react-router-dom'

export default function Layout() {
  return (
    <div className="flex min-h-dvh flex-col neon-grid scanlines">
      <header className="border-b border-border sticky top-0 z-10 bg-bg-deep/90 backdrop-blur-sm">
        <div className="mx-auto flex max-w-4xl items-center justify-between px-6 py-4">
          <Link to="/" className="font-bold text-lg text-neon-cyan text-glow-cyan tracking-wide">
            // BiteLog
          </Link>
          <nav className="flex items-center gap-6 text-sm">
            <Link to="/" className="text-fg-subtle hover:text-neon-cyan transition-colors">
              ホーム
            </Link>
            <Link to="/support" className="text-fg-subtle hover:text-neon-cyan transition-colors">
              サポート
            </Link>
            <a
              href="https://apps.apple.com/jp/app/mybitelog/id6742934521"
              target="_blank"
              rel="noopener noreferrer"
              className="border border-neon-green text-neon-green px-3 py-1 text-xs hover:bg-neon-green/10 transition-colors"
            >
              App Store
            </a>
          </nav>
        </div>
      </header>

      <main className="flex-1">
        <Outlet />
      </main>

      <footer className="border-t border-border px-6 py-10 text-sm text-fg-muted">
        <div className="mx-auto max-w-4xl flex flex-col gap-6 sm:flex-row sm:justify-between">
          <div>
            <p className="font-semibold text-fg-subtle mb-1 text-glow-cyan text-neon-cyan">// BiteLog</p>
            <p>健康的な食生活をサポートする食事記録アプリ</p>
          </div>
          <nav className="flex flex-col gap-2">
            <Link to="/" className="hover:text-neon-cyan transition-colors">ホーム</Link>
            <Link to="/privacy" className="hover:text-neon-cyan transition-colors">プライバシーポリシー</Link>
            <Link to="/terms" className="hover:text-neon-cyan transition-colors">利用規約</Link>
            <Link to="/support" className="hover:text-neon-cyan transition-colors">サポート</Link>
            <a
              href="https://github.com/watahiki606/BiteLog"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-neon-cyan transition-colors"
            >
              GitHub
            </a>
          </nav>
        </div>
        <div className="mx-auto max-w-4xl mt-6 pt-4 border-t border-border text-xs">
          <p>&copy; 2024 BiteLog. All rights reserved.</p>
        </div>
      </footer>
    </div>
  )
}
