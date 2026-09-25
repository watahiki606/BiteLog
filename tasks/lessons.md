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
