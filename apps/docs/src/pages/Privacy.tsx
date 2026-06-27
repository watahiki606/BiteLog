const sections = [
  {
    title: '1. はじめに',
    content: (
      <p>
        本プライバシーポリシーは、BiteLog（以下「本アプリ」）をご利用いただく際の、
        お客様の情報の取り扱いについて説明するものです。
        本アプリをご利用いただくことで、本ポリシーの内容にご同意いただいたものとみなします。
      </p>
    ),
  },
  {
    title: '2. 収集する情報',
    content: (
      <>
        <h3 className="text-sm font-semibold text-fg-subtle mt-4 mb-2">2.1 アカウント情報</h3>
        <p className="mb-3">
          本アプリは、Apple Sign-In または Google Sign-In を通じてアカウント認証を行います。
          認証時に以下の情報を取得します：
        </p>
        <ul className="list-disc ml-5 space-y-1">
          <li>ユーザーID（Apple または Google が発行する一意の識別子）</li>
          <li>メールアドレス（Apple Sign-In では非公開リレーアドレスの場合あり）</li>
        </ul>

        <h3 className="text-sm font-semibold text-fg-subtle mt-5 mb-2">2.2 食事・栄養データ</h3>
        <p className="mb-3">お客様がアプリに入力した以下のデータを収集・保存します：</p>
        <ul className="list-disc ml-5 space-y-1">
          <li>食事記録（日付、食事タイプ、食品名、摂取量、栄養成分）</li>
          <li>食品マスターデータ（ブランド名、商品名、栄養成分情報）</li>
          <li>栄養目標（目標タンパク質・脂質・炭水化物・食物繊維量）</li>
        </ul>

        <h3 className="text-sm font-semibold text-fg-subtle mt-5 mb-2">2.3 写真・画像</h3>
        <p className="mb-3">
          AI食品分析機能をご利用の際、カメラで撮影した写真またはフォトライブラリから
          選択した画像を取得します。これらの画像は栄養素分析の目的でサーバーに送信されます。
          画像データは分析処理後、サーバーには保存されません。
        </p>

        <h3 className="text-sm font-semibold text-fg-subtle mt-5 mb-2">2.4 その他の情報</h3>
        <ul className="list-disc ml-5 space-y-1">
          <li>言語設定（日本語・英語・システム設定に従う）</li>
          <li>アプリの使用状況データ（広告配信のため Google AdMob が収集）</li>
        </ul>
      </>
    ),
  },
  {
    title: '3. アカウント認証',
    content: (
      <p>
        本アプリは Apple Sign-In および Google Sign-In を認証手段として使用します。
        ログイン後に発行される認証トークン（JWT）は、お客様のデバイスの
        iOS Keychain に暗号化した状態で保存されます。
        トークンは定期的に自動更新され、ログアウト時に削除されます。
      </p>
    ),
  },
  {
    title: '4. データの保存場所',
    content: (
      <p>
        お客様の食事記録・食品マスター・栄養目標データは、
        Cloudflare Workers を基盤とするクラウドサーバーに保存されます。
        通信はすべて HTTPS により暗号化されています。
        認証トークンはサーバーには保存されず、デバイスの Keychain のみに保存されます。
      </p>
    ),
  },
  {
    title: '5. AI 食品画像分析',
    content: (
      <>
        <p className="mb-3">
          本アプリは、食事写真から栄養素を自動推定する AI 分析機能を提供しています。
          この機能をご利用の際は以下の点をご了承ください：
        </p>
        <ul className="list-disc ml-5 space-y-1">
          <li>カメラおよびフォトライブラリへのアクセスを許可していただく必要があります</li>
          <li>選択・撮影した画像は分析のためサーバーに送信されます</li>
          <li>画像データは分析処理後にサーバーから削除されます</li>
          <li>AI の分析結果はあくまで参考値であり、正確性を保証するものではありません</li>
        </ul>
      </>
    ),
  },
  {
    title: '6. 広告・トラッキング',
    content: (
      <>
        <p className="mb-3">
          本アプリは Google Mobile Ads（AdMob）を使用してバナー広告を表示しています。
          よりお客様に適した広告を表示するため、初回起動時に
          App Tracking Transparency（ATT）の許可をリクエストします。
          許可・拒否はいつでも iOS の設定アプリから変更できます。
        </p>
        <p>
          AdMob によるデータ収集および利用については、{' '}
          <a
            href="https://policies.google.com/privacy"
            target="_blank"
            rel="noopener noreferrer"
            className="text-neon-cyan hover:underline"
          >
            Google のプライバシーポリシー
          </a>{' '}
          をご参照ください。
        </p>
      </>
    ),
  },
  {
    title: '7. データの利用目的',
    content: (
      <>
        <p className="mb-3">収集したデータは以下の目的でのみ使用します：</p>
        <ul className="list-disc ml-5 space-y-1">
          <li>食事記録・栄養管理機能の提供</li>
          <li>AI 食品画像分析の実行</li>
          <li>ユーザーアカウントの認証・セッション管理</li>
          <li>アプリの改善・新機能の開発</li>
          <li>関連性の高い広告の配信（Google AdMob）</li>
          <li>法的義務への対応</li>
        </ul>
      </>
    ),
  },
  {
    title: '8. 第三者へのデータ提供',
    content: (
      <>
        <p className="mb-3">お客様の情報を以下の第三者と共有する場合があります：</p>
        <ul className="list-disc ml-5 space-y-1">
          <li><strong className="text-fg-subtle">Google</strong> — AdMob による広告配信、Google Sign-In による認証</li>
          <li><strong className="text-fg-subtle">Apple</strong> — Apple Sign-In による認証</li>
          <li><strong className="text-fg-subtle">Cloudflare</strong> — サーバーインフラ（データ保存・API 処理）</li>
          <li><strong className="text-fg-subtle">法令・行政機関</strong> — 法的義務に基づき必要と判断される場合</li>
        </ul>
        <p className="mt-3">上記以外の第三者にお客様のデータを販売・提供することはありません。</p>
      </>
    ),
  },
  {
    title: '9. お客様の権利',
    content: (
      <>
        <p className="mb-3">お客様は以下の操作をいつでも行うことができます：</p>
        <ul className="list-disc ml-5 space-y-2">
          <li>
            <strong className="text-fg-subtle">データの削除</strong> —
            設定画面の「データ管理」から「すべてのデータを削除」を実行することで、
            サーバー上の全データを削除できます（この操作は取り消しできません）
          </li>
          <li>
            <strong className="text-fg-subtle">データのエクスポート</strong> —
            設定画面の「CSV エクスポート」から全食事記録を CSV 形式でダウンロードできます
          </li>
          <li>
            <strong className="text-fg-subtle">広告トラッキングの制限</strong> —
            iOS の設定アプリから ATT の許可をいつでも変更できます
          </li>
          <li>
            <strong className="text-fg-subtle">ログアウト</strong> —
            設定画面からサインアウトすると、デバイス上の認証トークンが削除されます
          </li>
        </ul>
      </>
    ),
  },
  {
    title: '10. セキュリティ',
    content: (
      <>
        <p className="mb-3">お客様のデータを保護するため、以下の対策を実施しています：</p>
        <ul className="list-disc ml-5 space-y-1">
          <li>すべての通信における HTTPS 暗号化</li>
          <li>認証トークンの iOS Keychain への暗号化保存</li>
          <li>JWT によるアクセス制御</li>
        </ul>
        <p className="mt-3">ただし、インターネット上での完全なセキュリティを保証することはできません。</p>
      </>
    ),
  },
  {
    title: '11. 子どものプライバシー',
    content: (
      <p>
        本アプリは13歳未満の子どもからの個人情報を意図的に収集しません。
        13歳未満の方のご利用は保護者の同意を得た上でお願いします。
      </p>
    ),
  },
  {
    title: '12. ポリシーの変更',
    content: (
      <p>
        本プライバシーポリシーは変更される場合があります。
        重要な変更がある場合は、アプリ内または本ページで通知します。
        最終更新日は本ページ上部に記載しています。
      </p>
    ),
  },
  {
    title: '13. お問い合わせ',
    content: (
      <p>
        本プライバシーポリシーに関するご質問・ご要望は、{' '}
        <a
          href="https://github.com/watahiki606/BiteLog/issues"
          target="_blank"
          rel="noopener noreferrer"
          className="text-neon-cyan hover:underline"
        >
          GitHub の Issues ページ
        </a>{' '}
        からお問い合わせください。
      </p>
    ),
  },
]

export default function Privacy() {
  return (
    <div className="px-6 py-16">
      <div className="mx-auto max-w-3xl">
        <div className="mb-10">
          <p className="text-xs tracking-widest text-neon-green mb-2">&gt; LEGAL_DOC</p>
          <h1 className="text-3xl font-bold text-neon-cyan text-glow-cyan mb-3">
            プライバシーポリシー
          </h1>
          <p className="text-xs text-fg-muted">最終更新日：2025年5月31日</p>
        </div>

        <div className="space-y-8">
          {sections.map((s) => (
            <section key={s.title} className="border-l-2 border-border-dim pl-6">
              <h2 className="text-base font-semibold text-neon-cyan mb-3">{s.title}</h2>
              <div className="text-xs text-fg-muted leading-relaxed space-y-2">{s.content}</div>
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}
