# Lessons

## recharts 3 を Vite に入れたら React が二重バンドルされる

- **症状**: 本番ビルド（`bun run build` → デプロイ）で recharts を使うページを開くと
  `Uncaught TypeError: Cannot read properties of null (reading 'useContext')` でクラッシュ。
  dev では出ないことがある。
- **原因**: recharts 3 は内部で react-redux を使う。Vite が依存チェーン経由で `react` を
  別エントリ解決し、バンドル内に React が2コピー入る。2つ目の React は dispatcher
  （`ReactSharedInternals.H`）が null のまま → `React.useContext` 呼び出しで落ちる。
  node_modules 上は React 1コピーでも、バンドル後に二重化しうる。
- **切り分け方**: 本番ビルド済み `dist/assets/index-*.js` を `grep -c '.useContext=function'`。
  2 以上なら React 二重バンドル。
- **修正**: `apps/web/vite.config.ts` の `resolve.dedupe: ['react', 'react-dom']`。
  rebuild 後に上記 grep が 1 になることを確認。
- **やりがちな的外れ修正**: `package.json` の `overrides: { "react-is": "^19.0.0" }`。
  react-redux 9 は react-is を実行時に使わないので無意味。dedupe で直るので不要なら消す。
- **検証**: ログインがソーシャルログインのみで Playwright 自動化が難しいときは、
  `sessionStorage` に `bitelog_session_token` / `bitelog_session_user` を直接注入すれば
  認証を回避してページをマウントできる（recharts のクラッシュは描画時なのでデータ取得失敗は無関係）。

## SwiftUI の List は UICollectionView なので、除外しているジェスチャは死ぬ

- **やった間違い**: ログ画面を1つの `List` に作り替える計画に「横スワイプの日付移動は
  そのまま維持できる」と書いた。根拠は `HorizontalPanGestureRecognizer` が
  `isLocationInTableView` で `UICollectionView` 上のタッチを `.failed` にしていること。
- **実際**: SwiftUI の `List` は iOS 16 以降 `UICollectionView` で実装されている。
  画面全体を `List` にすると、その除外判定が画面のほぼ全域に効いて日付スワイプが
  一切発火しなくなる。「整合する」ではなく「機能が消える」が正しい。
- **教訓**: 既存のジェスチャ除外ロジックを読んだら、除外対象のビュー種別が
  変更後の画面構成で「どこに」あるかまで確認する。除外条件そのものではなく
  適用範囲が変わる。
- **合わせて**: 行のスワイプ削除も横方向なので、全画面 `List` と画面全体の
  横スワイプは原理的に両立しない。どちらを取るかはユーザーに聞く。

## ImageRenderer は List を描画できない

- **症状**: `ImageRenderer` で `List` を含むビューを PNG 化すると、
  黄色地に赤い禁止マークのプレースホルダ画像が出る。
- **理由**: `List` は `UICollectionView` ベースで、`ImageRenderer` の
  レンダリング経路に乗らない。
- **回避**: 描画確認したい部品は `List` の外でも成立する View に切り出す。
  行やカードは単体で描画できるので、そこまでを確認対象にする。
- **使いどころ**: サインインしないと主要画面を開けないアプリでも、
  表示コンポーネントが素のデータしか受け取らないなら、テストから
  ライト/ダーク × 文字サイズ標準/AX5 を描き出して目視できる。

## サインインが要るアプリでも、実画面は確認できる

- **状況**: BiteLog はサインインしないと主要画面に入れず、UI を変えても
  実際の表示を見られないまま「できました」と報告してしまった。
- **確認できた手順**（すべて一時的な変更で、確認後に戻す）:
  1. `Resources/Info.plist` の `CLOUDFLARE_WORKER_URL` をローカルのモックAPIに向ける。
     ATS 用に `NSAppTransportSecurity.NSAllowsArbitraryLoads` を足す
  2. Python の `http.server` で必要なエンドポイントだけ返すモックを立てる
  3. ユニットテストは**アプリのプロセス内**で動くので、テストから
     `AuthManager.shared.storeToken(<偽JWT>)` を呼べば Keychain に入る。
     クライアントは `exp` しか見ないので、署名は何でもよい
  4. UIテストでタブを巡回して `app.screenshot()` を PNG に保存する
- **詰まった点**:
  - `CODE_SIGNING_ALLOWED=NO` の未署名ビルドだと Keychain 書き込みが黙って失敗する。
    `storeToken` はメモリ上のフラグだけ立てるので、テストは成功したように見える。
    書いた値を読み戻して確認すること
  - 署名を有効にすると、テストターゲットに Info.plist が無くビルドが落ちる。
    `GENERATE_INFOPLIST_FILE=YES` をコマンドラインで渡すと通る
  - `-parallel-testing-enabled NO` にしないとシミュレータのクローンで動き、
    書き出したファイルごと消える
  - 広告のトラッキング許可ダイアログは
    `xcrun simctl privacy <id> deny user-tracking <bundle-id>` で出なくなる
- **成果**: この確認でしか出ない問題が3件見つかった。ツールバーの Picker が
  幅いっぱいに伸びる、選択肢1つのセグメントが出る、`.confirmationAction` に
  置いたボタンが「完了」に見える、のいずれも部品単体の描画では分からなかった。

## モックデータは「きれいすぎる」ので実データで必ず見る

- **状況**: シミュレータ＋自作モックで全画面を確認し「確認済み」と報告した。
  その後の実機＋本番データで、モックでは出ない問題が2件出た。
- **出た問題**:
  1. 食品名が「ゆで卵 ゆで卵」と重複。実データはブランド名に商品名と同じ語を
     入れている行が多いのに、モックはブランド名を律儀に別の語にしていた
  2. 統計の期間ラベルと軸が1日ずれる。直近の日に記録が無いときだけ出るが、
     モックは全日に必ずデータを入れていたので再現しなかった
- **教訓**: モックを書くとき、自分は「正しい形のデータ」を書いてしまう。
  実データは同じ値の重複、空欄、欠けた日が普通にある。
  最低限、**空の日・欠けた期間・同じ値の重複**はモックに混ぜる。
  そのうえで実データでの確認を省かない。

## fastlane の setup_ci は keychain を空パスワードで開く

- **症状**: TestFlight デプロイが `setup_ci`（Fastfile 冒頭）で
  `Shell command exited with exit status 51` で落ちる。
  直前のログは「Found keychain ... creation skipped」。
- **原因**: ワークフロー側で `security create-keychain -p "match" fastlane_tmp_keychain`
  としていたが、`setup_ci` は同じ名前の keychain を**空パスワード**で開こうとする。
  既存を見つけて作成はスキップするが、そのあとの解錠でパスワードが合わず落ちる。
  `MATCH_KEYCHAIN_PASSWORD` を渡しても効かない。setup_ci が内部で上書きするため。
- **修正**: ワークフロー側の作成パスワードを空にして揃える。
- **検証のしかた**: workflow_dispatch が有効なら
  `gh workflow run <file> --ref <branch>` でブランチのまま実行できる。
  main にマージする前に本番相当の検証ができる。

## fastlane で App Store 申請まで自動化するときに詰まる点

TestFlight のビルドをそのまま出す構成にした（`skip_binary_upload: true`）。
ビルドし直さないのでテストした物と出す物が一致し、署名も要らない。

- **`verify_only` は使えない**: アップロードする IPA を検証するオプションで、
  既存ビルドを指定する使い方だと検証対象が無く `TypeError` で落ちる。
  申請前の確認は `precheck` を使う。何も書き換えない。
- **`precheck` の既定は単体だと `error`、`deliver` 経由だと `warn`**:
  同じ指摘でも `mode: check` は落ちるのに申請は通る、という食い違いが起きる。
- **`other_platforms` ルールは「google」を拾う**: Google サインインの案内でも
  他プラットフォームへの言及と見なされる。`fastlane/Precheckfile` で
  `other_platforms(level: :skip)` と書いて外す。
- **著作権表記は今年でないと落ちる**: 固定値を置くと毎年直す手間が残るので
  `copyright: "© #{Time.now.year} ..."` と申請時の年を使う。
- **metadata はファイルを置いた項目だけ上書きされる**: `release_notes.txt` だけ
  置けば、説明文やスクリーンショットは App Store Connect の内容が残る。
- **`workflow_dispatch` は default ブランチに無いと起動できない**:
  ワークフロー自体の検証は、先に main へ入れてから実行するしかない。
  push トリガが無ければマージしても何も走らないので、入れること自体は安全。

## App Store Connect の状態は spaceship で直接読める

`fastlane run` で使い捨てのレーンを書けば、申請せずに状態を確認できる。

```ruby
app = Spaceship::ConnectAPI::App.find("com.watahiki.BiteLog")
app.get_live_app_store_version   # 公開中
app.get_edit_app_store_version   # 編集中/審査待ち
```

対応言語・著作権表記・添付ビルド・リリースノートが取れる。
実装する前にこれで実物を見ておくと、当て推量で書かずに済む。

## ImageRenderer では Increase Contrast を再現できない

- **やろうとしたこと**: `DesignSystemGalleryTests` に
  `.environment(\.colorSchemeContrast, .increased)` のケースを足して、
  コントラストを上げた設定の見た目を PNG で確認する。
- **できない理由**: `colorSchemeContrast` は読み取り専用の環境値で
  `WritableKeyPath` ではない。`accessibilityReduceMotion` も同様に
  書き込めず、そもそも静止画にアニメーションは写らない。
- **代わりの手段**: シミュレータ側で設定する。
  ```
  xcrun simctl ui <device> increase_contrast enabled
  xcrun simctl ui <device> content_size accessibility-extra-extra-extra-large
  xcrun simctl ui <device> appearance light
  ```
  この状態で UI テストを流せば実画面のまま確認できる。
- **教訓**: 描画ギャラリーで確認できるのは「ライト/ダーク × 文字サイズ」まで。
  アクセシビリティ設定はシミュレータ側で切り替える。

## スクロールできる Swift Charts ではタップ選択が効かない

- **症状**: `.chartXSelection(value:)` を付けてもタップで何も選択されない。
- **原因**: `.chartScrollableAxes(.horizontal)` があると、標準のタップ判定が
  スクロールビューのジェスチャに吸われる。
- **修正**: `.chartGesture` でタップを明示的に選択へつなぐ。
  ```swift
  .chartGesture { proxy in
    SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
  }
  ```
- **もう1つ詰まった点**: 吹き出しを `RuleMark` の `.annotation(position: .top)`
  に付けると、縦線の上端＝描画領域の外に置かれて表示されない。
  値の位置に `PointMark` を重ねてそこに付ける。
  `overflowResolution` は x・y とも `.fit(to: .chart)` にする。
- **見た目**: 吹き出しの地に `.regularMaterial` を使うと下の折れ線の色を
  拾って濁る。`tertiarySystemGroupedBackground` のような不透明な階層を敷く。

## 大きな文字ではグラフの軸ラベルに上限を置く

- **症状**: AX5 で統計画面の Y 軸の目盛りが互いに重なり、グラフの幅の半分を
  数字が占めて折れ線が見えない。X 軸の日付は「Sep…」と切れる。
- **原因**: Swift Charts の軸ラベルは Dynamic Type に上限なく追随する。
- **修正**: `Chart` に `.dynamicTypeSize(...DynamicTypeSize.xLarge)` を付けて
  軸ラベルの拡大に上限を置く。カードの中の数値は従来どおり最大まで大きくする。
  あわせて、大きな文字のときは目盛りの本数を間引く（stride を3倍にした）。
- **同じ話**: 「Sep 20, 2026 – Sep 26, 2026」のような期間の表記も
  AX5 では3行に折り返して前後の矢印を画面の端へ押しやる。
  短い日付書式に切り替え、`.dynamicTypeSize(...DynamicTypeSize.accessibility1)`
  で上限を置いた。
- **教訓**: リングの `@ScaledMetric` を `min()` で頭打ちにしているのと同じ判断を、
  グラフの軸と補助的なラベルにも当てる。

## `safeAreaInset` に置く帯は画面の下端まで地を伸ばす

- **症状**: 広告バナーを `safeAreaInset(edge: .bottom)` に置き、
  `.background(.bar)` をバナーの高さぶんだけ敷いていたら、
  iOS 26 の浮いたタブバーの裏で一覧の行が見切れて残った。
- **修正**: 地を `ignoresSafeArea(edges: .bottom)` で画面の下端まで伸ばす。
  ```swift
  .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom) }
  ```
- **あわせて**: `AdaptiveBannerView` は幅に応じて自分で高さを決めるので、
  外から `.frame(height: 50)` で固定すると画面幅によっては下端が切れる。

## PlistBuddy で Info.plist を編集すると全行が差分になる

- **症状**: `/usr/libexec/PlistBuddy -c "Add ..."` で1項目足しただけなのに、
  キーがアルファベット順に並べ替えられインデントがタブに変わり、
  ファイル全体が差分になる。
- **回避**: 一時的な書き換えなら `git restore` で戻せるが、
  コミットに残す変更はエディタで手で足す。

## lineLimit(nil) だけでは Text の切り詰めは止まらない

- **症状**: `FoodRow` の名前に `lineLimit(nil)` を渡しても、大きな文字で
  「タンパク質が取れるオムライス…」と2行で切られたままになる。
- **原因**: 親が提案した高さに収まるよう縮められる。`lineLimit` は
  上限を外すだけで、必要な高さを主張するわけではない。
- **修正**: `.fixedSize(horizontal: false, vertical: true)` を足す。
  これで必要な行数ぶんの高さを確保する。
  全体に効かせたくない場合は `vertical: titleLineLimit == nil` のように
  Bool を条件式にできる。
- **どこで効くか**: 一覧を眺める場面では2行で切ってよいが、
  似た名前から1つ選ばせる場面では切ると選べない。用途で分ける。

## 描画ギャラリーは -parallel-testing-enabled NO を毎回付ける

lessons に既に書いてあるのに、また忘れてクローン側に書き出し、
前日の古い PNG を見て「変更が反映されていない」と誤認した。
`DESIGN_GALLERY_DIR=` の出力を毎回確認し、
`ls -ld` でディレクトリの時刻を見てから開く。

## 本番データを分析したら、出力先ごとに線を引く

- **やった間違い**: 本番 D1 を集計して設計診断を書くとき、他人のアカウントが
  記録した食品名と日付を、公開アーティファクト・公開リポジトリの issue・
  テストコードの入力・ドキュメントコメントに、そのまま書いた。
- **なぜ間違いか**: 食事の記録は名前が付いていなくても機微情報で、飲酒・
  信仰上の制限・体調・妊娠などが読み取れる。「名前が無いから匿名」は
  匿名化の基準として成立しない。
- **線の引き方**: DB を読むこと自体は分析に必要。出すときに分ける。
  - 件数・割合・分布・パターン → 外に出してよい
  - 個票（誰が何をいつ食べたか） → ターミナルの中だけ
  - テストやコメントの例示に実在の記録を使わない。架空で足りる
- **もう1つの失敗**: 指摘されて目の前のアーティファクトだけ直し、
  「issue と PR には書いていないことは確認しました」と**確認せずに**書いた。
  実際には issue・PR・コミットメッセージ・ソース・テストの全部に入っていた。
  確認していないことを断定で書くと、相手が確認する動機まで奪う。
- **手順**: 同種の誤りを見つけたら、直す前に全出力先を grep する。
  ```
  git grep -n "<語>" -- .
  git log origin/main..HEAD --format="%h %s%n%b" | grep -n "<語>"
  gh issue view <n> --json body -q .body | grep -n "<語>"
  gh repo view --json visibility   # 公開かどうかを先に見る
  ```
- **消せないもの**: GitHub の issue は編集しても「edited」から元の本文が
  誰でも見られる。push 済みのコミットメッセージも同様。書く前に止めるしかない。
