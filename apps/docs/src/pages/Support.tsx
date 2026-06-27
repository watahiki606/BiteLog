const FEATURE_CARDS = [
  {
    icon: '📝',
    title: '食事記録',
    items: [
      '食品名・量・単位を入力して記録',
      '過去に登録した食品を検索して再利用',
      '朝食・昼食・夕食・間食に分類',
      'スワイプで前後の日に移動',
    ],
  },
  {
    icon: '📸',
    title: 'AI 写真分析',
    items: [
      'カメラで撮影 or フォトライブラリから選択',
      '栄養素を AI が自動推定',
      '推定結果は手動で修正可能',
      'カメラ・フォトライブラリの許可が必要',
    ],
  },
  {
    icon: '📊',
    title: '栄養バランス',
    items: [
      'カロリー・タンパク質・脂質を自動集計',
      '正味炭水化物（Net Carbs）を表示',
      '食物繊維も個別にトラッキング',
      '食事タイプ別・日別で確認',
    ],
  },
  {
    icon: '🥗',
    title: '食品マスター',
    items: [
      'よく食べる食品を事前登録',
      'ブランド名・商品名で管理',
      '自分が登録した食品のみ表示するフィルター',
      '詳細画面から編集・削除',
    ],
  },
  {
    icon: '🔄',
    title: 'クラウド同期',
    items: [
      'Apple Sign-In または Google Sign-In でログイン',
      'データはクラウドに自動保存',
      '複数デバイスで同じデータにアクセス',
      '設定画面からサインアウト可能',
    ],
  },
  {
    icon: '📤',
    title: 'CSV インポート・エクスポート',
    items: [
      '全食事記録を CSV で書き出し',
      '他のアプリからデータを CSV で取り込み',
      '設定画面から操作',
    ],
  },
  {
    icon: '🗑️',
    title: 'データ管理',
    items: [
      '設定 › データ管理から全データを削除',
      '削除は取り消しできないため要注意',
      '削除前に CSV エクスポートを推奨',
    ],
  },
  {
    icon: '🌏',
    title: '多言語対応',
    items: [
      '日本語・英語に対応',
      'デフォルトはシステム設定に従う',
      '設定画面から言語を切り替え可能',
      '変更後はアプリの再起動が必要',
    ],
  },
]

const CSV_COLUMNS = [
  { name: 'date', desc: '日付', note: 'YYYY-MM-DD 形式（例: 2024-03-20）' },
  {
    name: 'meal_type',
    desc: '食事タイプ',
    note: 'Breakfast / Lunch / Dinner / Snack',
  },
  { name: 'brand_name', desc: 'ブランド名', note: '空欄可' },
  { name: 'product_name', desc: '商品名', note: '必須' },
  { name: 'calories', desc: 'カロリー（kcal）', note: '数値' },
  { name: 'carbs', desc: '炭水化物（g）', note: '数値' },
  {
    name: 'dietary_fiber',
    desc: '食物繊維（g）',
    note: '数値。正味炭水化物 = carbs − dietary_fiber',
  },
  { name: 'fat', desc: '脂質（g）', note: '数値' },
  { name: 'protein', desc: 'タンパク質（g）', note: '数値' },
  { name: 'portion_amount', desc: '摂取量', note: '数値（例: 1.0）' },
  {
    name: 'portion_unit',
    desc: '単位',
    note: '任意の文字列（例: 個、g、ml、食）',
  },
]

const FAQ = [
  {
    q: 'CSV インポートがうまくいきません',
    a: (
      <div>
        以下の点を確認してください：
        <ul className="mt-3 ml-5 space-y-1 list-disc">
          <li>1行目にヘッダー行が含まれているか</li>
          <li>区切り文字がカンマ（<code className="text-neon-cyan">,</code>）になっているか</li>
          <li>
            日付が <code className="text-neon-cyan">YYYY-MM-DD</code> 形式（例:{' '}
            <code className="text-neon-cyan">2024-03-20</code>）になっているか
          </li>
          <li>
            <code className="text-neon-cyan">meal_type</code> が英語（
            <code className="text-neon-cyan">Breakfast / Lunch / Dinner / Snack</code>
            ）になっているか
          </li>
          <li>ファイルの文字コードが UTF-8 になっているか</li>
        </ul>
      </div>
    ),
  },
  {
    q: '過去の食事を検索しても何も表示されません',
    a: '食品マスターの検索はブランド名または商品名のキーワードで行います。過去に一度も食品を登録していない場合は検索結果は表示されません。まずは食品を1件記録するか、CSV インポートでデータを取り込んでみてください。',
  },
  {
    q: '単位（g・個など）を自由に設定できますか？',
    a: 'はい、任意の文字列を単位として入力できます。「g」「個」「ml」などの一般的な単位のほか、「パック」「切れ」「カップ」「食」なども入力可能です。',
  },
  {
    q: 'AI 写真分析の精度はどのくらいですか？',
    a: 'AI の推定結果はあくまで参考値です。食品の種類・量・撮影角度・光量によって精度が変わります。推定結果は編集画面で手動修正できますので、必要に応じて調整してください。',
  },
  {
    q: '機種変更してもデータを引き継げますか？',
    a: 'はい。新しいデバイスで同じ Apple または Google アカウントでサインインすると、クラウドに保存されたデータをそのまま引き継げます。',
  },
  {
    q: 'すべてのデータを削除したい',
    a: '設定画面の「データ管理」›「すべてのデータを削除」から削除できます。この操作は取り消しできません。削除前に CSV エクスポートでバックアップを取ることをおすすめします。',
  },
  {
    q: '広告トラッキングをオフにしたい',
    a: 'iOS の設定アプリ › 「プライバシーとセキュリティ」›「トラッキング」から BiteLog のトラッキング許可をいつでも変更できます。',
  },
]

export default function Support() {
  return (
    <>
      {/* Hero */}
      <section className="px-6 py-16 text-center border-b border-border">
        <div className="mx-auto max-w-2xl">
          <span className="inline-block border border-neon-cyan/40 text-neon-cyan text-xs px-3 py-1 mb-4 tracking-widest">
            HELP CENTER
          </span>
          <h1 className="text-3xl font-bold text-foreground mb-3">
            <span className="text-neon-cyan text-glow-cyan">BiteLog</span> サポート
          </h1>
          <p className="text-fg-subtle text-sm mb-8">使い方から困ったときの対処法まで</p>
          <nav className="flex flex-wrap justify-center gap-3 text-xs">
            {[
              ['#features', '機能ガイド'],
              ['#csv', 'CSV 仕様'],
              ['#faq', 'よくある質問'],
              ['#contact', 'お問い合わせ'],
            ].map(([href, label]) => (
              <a
                key={href}
                href={href}
                className="border border-border text-fg-subtle px-4 py-2 hover:border-neon-cyan hover:text-neon-cyan transition-colors"
              >
                {label}
              </a>
            ))}
          </nav>
        </div>
      </section>

      {/* Feature Guide */}
      <section id="features" className="px-6 py-16 border-b border-border">
        <div className="mx-auto max-w-4xl">
          <div className="mb-10">
            <p className="text-xs tracking-widest text-neon-green mb-1">&gt; FEATURE_GUIDE</p>
            <h2 className="text-xl font-bold text-foreground">機能ガイド</h2>
            <p className="text-fg-muted text-sm mt-1">BiteLog でできること</p>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {FEATURE_CARDS.map((c) => (
              <div key={c.title} className="border border-border bg-bg-surface p-5 hover:border-neon-cyan/40 transition-colors">
                <div className="flex items-center gap-2 mb-3">
                  <span className="text-xl">{c.icon}</span>
                  <h3 className="text-sm font-semibold text-neon-cyan">{c.title}</h3>
                </div>
                <ul className="space-y-1">
                  {c.items.map((item) => (
                    <li key={item} className="text-xs text-fg-muted flex gap-2">
                      <span className="text-neon-green shrink-0">▸</span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Net Carbs Note */}
      <section className="px-6 py-16 border-b border-border bg-bg-surface">
        <div className="mx-auto max-w-4xl">
          <div className="mb-6">
            <p className="text-xs tracking-widest text-neon-green mb-1">&gt; NUTRITION_CALC</p>
            <h2 className="text-xl font-bold text-foreground">栄養素の計算方法</h2>
          </div>
          <div className="border border-border bg-bg-card p-6 max-w-xl">
            <div className="flex items-center gap-2 mb-3">
              <span className="text-xl">🧮</span>
              <h3 className="text-sm font-semibold text-neon-cyan">正味炭水化物（Net Carbs）</h3>
            </div>
            <p className="text-xs text-fg-muted leading-relaxed">
              BiteLog では糖質管理の指標として{' '}
              <strong className="text-fg">正味炭水化物</strong> を使用しています。
            </p>
            <p className="text-xs text-neon-green font-semibold my-3 font-mono">
              正味炭水化物 = 炭水化物 − 食物繊維
            </p>
            <p className="text-xs text-fg-muted leading-relaxed">
              CSV インポート時に <code className="text-neon-cyan">carbs</code>（炭水化物）と{' '}
              <code className="text-neon-cyan">dietary_fiber</code>（食物繊維）を両方指定すると、
              正味炭水化物は自動的に計算されます。
            </p>
          </div>
        </div>
      </section>

      {/* CSV Spec */}
      <section id="csv" className="px-6 py-16 border-b border-border">
        <div className="mx-auto max-w-4xl">
          <div className="mb-8">
            <p className="text-xs tracking-widest text-neon-green mb-1">&gt; CSV_FORMAT</p>
            <h2 className="text-xl font-bold text-foreground">CSV フォーマット仕様</h2>
            <p className="text-fg-muted text-sm mt-1">インポート・エクスポートで使用するフォーマット</p>
          </div>
          <div className="border border-border bg-bg-card p-4 mb-6 overflow-x-auto">
            <pre className="text-xs text-neon-green font-mono whitespace-pre">
{`date,meal_type,brand_name,product_name,calories,carbs,dietary_fiber,fat,protein,portion_amount,portion_unit
2024-03-20,Breakfast,ブランドA,商品B,200,30,5,10,8,1.0,個
2024-03-20,Lunch,ブランドC,商品D,350,45,8,12,20,1.0,食`}
            </pre>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs border-collapse">
              <thead>
                <tr className="border-b border-border">
                  <th className="text-left text-neon-cyan py-2 pr-4 font-semibold">カラム名</th>
                  <th className="text-left text-neon-cyan py-2 pr-4 font-semibold">説明</th>
                  <th className="text-left text-neon-cyan py-2 font-semibold">形式・備考</th>
                </tr>
              </thead>
              <tbody>
                {CSV_COLUMNS.map((col) => (
                  <tr key={col.name} className="border-b border-border/50 hover:bg-bg-surface transition-colors">
                    <td className="py-2 pr-4">
                      <code className="text-neon-green">{col.name}</code>
                    </td>
                    <td className="py-2 pr-4 text-fg-subtle">{col.desc}</td>
                    <td className="py-2 text-fg-muted">{col.note}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="px-6 py-16 border-b border-border bg-bg-surface">
        <div className="mx-auto max-w-4xl">
          <div className="mb-8">
            <p className="text-xs tracking-widest text-neon-green mb-1">&gt; FAQ</p>
            <h2 className="text-xl font-bold text-foreground">よくある質問</h2>
            <p className="text-fg-muted text-sm mt-1">困ったときはまずここを確認</p>
          </div>
          <div className="space-y-2">
            {FAQ.map((item) => (
              <details
                key={item.q}
                className="border border-border group open:border-neon-cyan/40 transition-colors"
              >
                <summary className="px-5 py-4 text-sm text-fg-subtle cursor-pointer hover:text-neon-cyan transition-colors list-none flex items-center justify-between group-open:text-neon-cyan">
                  <span>{item.q}</span>
                  <span className="text-neon-cyan shrink-0 ml-4 group-open:rotate-45 transition-transform">+</span>
                </summary>
                <div className="px-5 pb-5 text-xs text-fg-muted leading-relaxed border-t border-border/50 pt-4">
                  {item.a}
                </div>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* Contact CTA */}
      <section id="contact" className="px-6 py-20 text-center">
        <div className="mx-auto max-w-xl">
          <p className="text-xs tracking-widest text-neon-green mb-2">&gt; CONTACT</p>
          <h2 className="text-2xl font-bold text-foreground mb-4">解決しない場合は</h2>
          <p className="text-fg-subtle text-sm leading-relaxed mb-10">
            GitHub Issues からお気軽にご連絡ください。できる限り対応します。
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="https://apps.apple.com/jp/app/mybitelog/id6742934521"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-3 border border-neon-green bg-neon-green/10 text-neon-green px-6 py-3 hover:bg-neon-green/20 transition-colors glow-green"
            >
              <span>⬇</span>
              <span className="flex flex-col items-start">
                <span className="text-xs opacity-70">Download on the</span>
                <span className="text-sm font-bold">App Store</span>
              </span>
            </a>
            <a
              href="https://github.com/watahiki606/BiteLog/issues"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block border border-border text-fg-subtle px-6 py-3 text-sm hover:border-neon-cyan hover:text-neon-cyan transition-colors"
            >
              GitHub Issues でお問い合わせ →
            </a>
          </div>
        </div>
      </section>
    </>
  )
}
