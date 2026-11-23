# 食品と成分表の対応の表をやめ、食品の列に値を持つだけにする

ブランチ refactor/drop-composition-links。ユーザーの許可で、マージ、Worker と web のデプロイ、本番 D1 での表と列の削除まで行う。App Store の申請はしない。

## 方針

- 食品は food_masters の栄養素の列に値を持つだけ。food_master_components と nutrient_sources は消す
- composition_foods は残す。手入力の「成分表から選ぶ」で値を欄に書き込むことと、写真の解析で値を計算することに使う。書き込んだ値は手で打った値と同じで、あとから直せる
- 画面から「補った値」「ひも付け」とその印、ひも付けの欄、管理画面のひも付けの作業画面をなくす。iOS と web
- food_masters の栄養素の値、nutrient_source と nutrient_source_ref は残す。対応の表より前からある出典の列

## 古い版のアプリとの互換

- 公開中の版は、応答の nutrientSources と components を decodeIfPresent で読む。応答から消しても読める
- 古い版は作成と更新で components を送ってくることがある。Worker は読まずに捨てる。400 にしない
- 出す順番: Worker を出してから、表と列を消す。先に消すと、今の Worker が無い表と列を読んで落ちる

## 計画

- [x] Worker: マイグレーション 0007 で表と索引と列を消す。schema.sql も同じ形に
- [x] Worker: foodCompositionDb.ts と補った印の処理を消す。写真の解析で使う食材の足し算は aiComposition.ts に移す
- [x] Worker: 食品の作成、更新、削除、1件の読み出しから対応の表を外す。components が来ても捨てるテスト
- [x] Worker: 管理者のひも付け一覧と計算し直しの API を消す
- [x] iOS: 食品の詳細から補った印と成分表の欄を消す
- [x] iOS: 食品の入力のひも付けの欄を「成分表から選ぶ」にする。選ぶと欄に値が入る。詳しい栄養素の欄も畳んで出す
- [x] iOS: 写真の結果から保存するとき components を送らない。詳しい栄養素は解析の値をそのまま送る。前はサーバーが食材から補っていた
- [x] web: LINK TABLE の画面、ひも付けの欄、TABLE の印、成分表から全部取るの切り替えを消し、成分表から選んで欄に入れる形にする。詳しい栄養素の欄も出す
- [x] design-2.md に【決定】を書く。runbook と README の記述を直す
- [x] テスト: Worker、web、iOS。通った数と落ちた数を見る
- [ ] PR、マージ、Worker と web のデプロイ、bookmark、0007 の適用、件数と値の確認
- [ ] 実機の iPhone 17 Pro に Debug で入れる
