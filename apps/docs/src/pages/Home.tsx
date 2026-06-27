const FEATURES = [
  {
    icon: '📝',
    title: 'かんたん食事記録',
    body: '食品を選んで量を入力するだけ。過去に記録した食品はすぐ再利用できます。',
  },
  {
    icon: '📸',
    title: 'AI 写真分析',
    body: '食事の写真を撮るだけで栄養素を自動推定。面倒な入力を省けます。',
  },
  {
    icon: '📊',
    title: '栄養バランス確認',
    body: 'カロリー・タンパク質・脂質・正味炭水化物・食物繊維を日別に自動集計。',
  },
  {
    icon: '📅',
    title: '食事タイプ別管理',
    body: '朝食・昼食・夕食・間食に分けて記録。スワイプで前後の日にすばやく移動。',
  },
  {
    icon: '🥗',
    title: '食品マスター',
    body: 'よく食べる食品を登録しておけば、毎回の入力がワンタップで完了。',
  },
  {
    icon: '📤',
    title: 'CSV エクスポート',
    body: '全記録を CSV 形式でダウンロード。自分のデータはいつでも手元に。',
  },
]

export default function Home() {
  return (
    <>
      {/* Hero */}
      <section className="px-6 py-24 text-center">
        <div className="mx-auto max-w-2xl">
          <p className="text-xs tracking-widest text-neon-green mb-4 font-semibold">
            &gt; MEAL_TRACKER v2.4 INITIALIZED
          </p>
          <h1 className="text-4xl sm:text-5xl font-bold text-foreground leading-tight mb-6">
            食べたものを記録する。<br />
            <span className="text-neon-cyan text-glow-cyan">それだけでいい。</span>
          </h1>
          <p className="text-fg-subtle text-base leading-relaxed mb-10">
            記録を続けることで、無意識の食習慣が見えてくる。<br />
            特別なルールも、複雑な計算も必要ありません。
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="https://apps.apple.com/jp/app/mybitelog/id6742934521"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block border border-neon-cyan bg-neon-cyan/10 text-neon-cyan px-6 py-3 text-sm font-semibold hover:bg-neon-cyan/20 transition-colors glow-cyan"
            >
              App Store からダウンロード
            </a>
            <a
              href="#features"
              className="inline-block border border-border text-fg-subtle px-6 py-3 text-sm hover:border-neon-cyan hover:text-neon-cyan transition-colors"
            >
              機能を見る
            </a>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="px-6 py-20 border-t border-border">
        <div className="mx-auto max-w-4xl">
          <div className="text-center mb-12">
            <p className="text-xs tracking-widest text-neon-green mb-2">&gt; FEATURES</p>
            <h2 className="text-2xl font-bold text-foreground">主な機能</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {FEATURES.map((f) => (
              <div
                key={f.title}
                className="border border-border bg-bg-surface p-6 hover:border-neon-cyan/50 transition-colors"
              >
                <div className="text-2xl mb-3">{f.icon}</div>
                <h3 className="text-sm font-semibold text-neon-cyan mb-2">{f.title}</h3>
                <p className="text-xs text-fg-muted leading-relaxed">{f.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Download */}
      <section id="download" className="px-6 py-20 border-t border-border text-center">
        <div className="mx-auto max-w-2xl">
          <p className="text-xs tracking-widest text-neon-green mb-2">&gt; DOWNLOAD</p>
          <h2 className="text-2xl font-bold text-foreground mb-4">ダウンロード</h2>
          <p className="text-fg-subtle text-sm mb-8">iPhone で無料でご利用いただけます。</p>
          <a
            href="https://apps.apple.com/jp/app/mybitelog/id6742934521"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-3 border border-neon-green bg-neon-green/10 text-neon-green px-8 py-4 hover:bg-neon-green/20 transition-colors glow-green"
          >
            <span className="text-xl">⬇</span>
            <span className="flex flex-col items-start">
              <span className="text-xs opacity-70">Download on the</span>
              <span className="text-base font-bold tracking-wide">App Store</span>
            </span>
          </a>
        </div>
      </section>

      {/* Contact */}
      <section id="contact" className="px-6 py-20 border-t border-border text-center">
        <div className="mx-auto max-w-2xl">
          <p className="text-xs tracking-widest text-neon-green mb-2">&gt; CONTACT</p>
          <h2 className="text-2xl font-bold text-foreground mb-4">お問い合わせ・サポート</h2>
          <p className="text-fg-subtle text-sm leading-relaxed mb-8">
            アプリに関するご質問やサポートが必要な場合は、<br />
            GitHub の Issues ページからお気軽にお問い合わせください。
          </p>
          <a
            href="https://github.com/watahiki606/BiteLog/issues"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block border border-neon-cyan bg-neon-cyan/10 text-neon-cyan px-6 py-3 text-sm font-semibold hover:bg-neon-cyan/20 transition-colors"
          >
            GitHub でお問い合わせ
          </a>
        </div>
      </section>
    </>
  )
}
