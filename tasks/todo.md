# サーバーで食塩相当量と飽和脂肪酸、値の出典を扱えるようにする

設計は `~/research/bitelog-nutrients/design.md` の3〜6章と、7章の PR 6。アプリと web の画面は後の PR で足す。

## 計画

- [x] テストの表を schema.sql から作る形にそろえ、既存のテストがそのまま通ることを確かめる
- [x] `migrations/0001_nutrients_salt_saturated_fat.sql` と schema.sql に4列を足す
- [x] 定義ファイルに2つの栄養素を足し、iOS の生成物を作り直す。iOS の色とアイコンはグループで共通にする
- [x] 先にテストを書く。作成、更新、出典、スナップショット、集計、CSV
- [x] Worker を直す
  - 応答では NULL の栄養素を省き、出典を返す
  - 更新では、追加の栄養素と出典は送られたキーだけを変え、null なら NULL に戻す。最初の5項目は null で今の値を消さない
  - 出典は決まった種類だけを受け付ける
  - 記録のスナップショットは、名前と量と定義にある栄養素だけを保存する
  - 集計では、追加の栄養素を値の分かっている品だけで足し、品数を返す
  - CSV は見出しに列があるときだけ読む
- [x] Worker、web、iOS のテスト
- [x] 使い捨ての D1 にマイグレーションを当てて確かめる

## 本番に出す順番

1. `npx wrangler d1 time-travel info bitelog` で bookmark を控える
2. `npx wrangler d1 migrations apply bitelog --remote`
3. 列と件数を読み取りで確かめる
4. Worker をデプロイする

## 振り返り

- 追加の栄養素の名前も、最初の5項目と同じく型で持った。web が応答の型でそのキーを読めるようにするためで、JSON と食い違えばテストで落ちる
- テストの表を schema.sql から作るように変えても、外部キーや CHECK 制約で落ちるテストは無かった
