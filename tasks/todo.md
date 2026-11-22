# Worker の栄養素の列と集計を定義ファイルから組み立てる

設計は `~/research/bitelog-nutrients/design.md` の7章の PR 2。応答の形は変えない。

## 計画

- [x] 作り直しの前に、今の動きを押さえるテストを足す。5つの栄養素に別々の値を入れる
  - 作成、一括作成、部分更新、削除のときのスナップショット、記録の一覧、日ごとと日次の集計、CSV の読み込み
- [x] `lib/nutrients.ts` で定義ファイルを読む。行から応答への変換と、本文から列の並びへの変換を持つ
- [x] `lib/foodMasterSql.ts` に食品の INSERT と、栄養素の UPDATE をまとめる。作成、一括作成、CSV で同じ文を使う
- [x] `nutritionSql.ts`、`types.ts`、`foodMasters.ts`、`logItems.ts`、`statistics.ts`、`csvImport.ts` を定義から回す
- [x] web の型が崩れないことを確かめる。Worker のソースを辿ると JSON を読むので、web にも `resolveJsonModule` を足す
- [x] Worker のテスト、web のビルドと lint とテスト

## 振り返り

- JSON から読んだ id は型が string に広がり、web が Hono RPC で推論する応答の型から栄養素のキーが消える。最初の5項目だけ名前を型でも持ち、JSON の core と食い違えばテストで落ちるようにした
- 送られた値と D1 の値は型を確かめずにそのまま渡す。今の動きを変えないため
- AI 推定のスキーマ、CSV の列の読み方、目標値の表は、この PR では触れていない。PR 6 と 7 で扱う
