const sections = [
  {
    title: '1. はじめに',
    content: (
      <p>
        本利用規約（以下「本規約」）は、BiteLog（以下「本アプリ」）の利用に関する
        条件を定めるものです。本アプリをご利用いただく際には、
        本規約にご同意いただく必要があります。
      </p>
    ),
  },
  {
    title: '2. 利用許諾',
    content: (
      <p>
        本規約に従い、お客様に本アプリを使用する非独占的、
        譲渡不可能なライセンスを付与します。
        本アプリは個人的な非商用目的でのみご利用ください。
      </p>
    ),
  },
  {
    title: '3. 禁止事項',
    content: (
      <>
        <p className="mb-3">本アプリをご利用の際、以下の行為を禁止いたします：</p>
        <ul className="list-disc ml-5 space-y-1">
          <li>本アプリの逆アセンブル、逆コンパイル、リバースエンジニアリング</li>
          <li>本アプリの複製、配布、貸与、販売、移転</li>
          <li>本アプリの改変、修正</li>
          <li>違法な目的での使用</li>
          <li>他の利用者や第三者に迷惑をかける行為</li>
          <li>システムに負荷をかける行為</li>
        </ul>
      </>
    ),
  },
  {
    title: '4. データの取り扱い',
    content: (
      <p>
        お客様が本アプリに入力したデータ（食事記録等）の所有権は
        お客様に帰属します。本アプリの開発者は、
        お客様のデータに対していかなる権利も主張いたしません。
      </p>
    ),
  },
  {
    title: '5. 免責事項',
    content: (
      <>
        <h3 className="text-sm font-semibold text-fg-subtle mb-2">5.1 サービスの提供</h3>
        <p className="mb-4">
          本アプリは「現状のまま」提供され、明示または黙示を問わず、
          いかなる保証もいたしません。
        </p>
        <h3 className="text-sm font-semibold text-fg-subtle mb-2">5.2 健康・医療に関する免責</h3>
        <p className="mb-4">
          本アプリが提供する栄養情報は参考情報であり、
          医学的なアドバイスではありません。健康に関する決定を行う前に、
          医師や栄養士等の専門家にご相談ください。
        </p>
        <h3 className="text-sm font-semibold text-fg-subtle mb-2">5.3 損害の免責</h3>
        <p>
          本アプリの使用により生じたいかなる直接的、間接的、
          特別、偶発的、結果的損害についても責任を負いません。
        </p>
      </>
    ),
  },
  {
    title: '6. サービスの変更・終了',
    content: (
      <p>
        本アプリの開発者は、予告なく本アプリの機能の変更、追加、削除、
        またはサービスの終了を行う場合があります。
        これらによりお客様に生じた損害について責任を負いません。
      </p>
    ),
  },
  {
    title: '7. 知的財産権',
    content: (
      <p>
        本アプリに関するすべての知的財産権は、開発者または
        正当な権利者に帰属します。本規約は、これらの権利を
        お客様に譲渡するものではありません。
      </p>
    ),
  },
  {
    title: '8. 準拠法・管轄裁判所',
    content: (
      <p>
        本規約は日本法に準拠し、解釈されるものとします。
        本アプリに関連する紛争については、
        東京地方裁判所を専属的合意管轄裁判所とします。
      </p>
    ),
  },
  {
    title: '9. 規約の変更',
    content: (
      <p>
        本規約は予告なく変更される場合があります。
        変更後も継続して本アプリをご利用いただく場合、
        変更後の規約に同意したものとみなします。
      </p>
    ),
  },
  {
    title: '10. 分離可能性',
    content: (
      <p>
        本規約の一部が無効または執行不能と判断された場合でも、
        その他の規定は引き続き有効に存続するものとします。
      </p>
    ),
  },
  {
    title: '11. お問い合わせ',
    content: (
      <p>
        本規約に関するご質問は、{' '}
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

export default function Terms() {
  return (
    <div className="px-6 py-16">
      <div className="mx-auto max-w-3xl">
        <div className="mb-10">
          <p className="text-xs tracking-widest text-neon-green mb-2">&gt; LEGAL_DOC</p>
          <h1 className="text-3xl font-bold text-neon-cyan text-glow-cyan mb-3">
            利用規約
          </h1>
          <p className="text-xs text-fg-muted">最終更新日：2024年12月29日</p>
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
