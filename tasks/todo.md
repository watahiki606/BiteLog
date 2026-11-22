# 栄養素の定義ファイルと Swift の生成

設計は `~/research/bitelog-nutrients/design.md` の2章と7章の PR 1。栄養素の一覧を `shared/nutrients.json` の1か所にまとめ、iOS はそこから生成した Swift を使う。この PR では既存の5項目だけを書き、動きは変えない。生成物を使う置き換えは PR 4 で行う。

## 計画

- [x] 食い違いを検出するテストを先に書く。JSON を `#filePath` から読み、生成済みの Swift と比べる
  - 並びと id が `NutrientID.allCases` と一致する
  - 列名、単位、桁数、グループ、core、表示での扱いが一致する
  - 日本語と英語の表示名と短い名前が `Nutrients.strings` と一致する
  - core の栄養素が、食品の JSON のキーとして今の DTO に揃っている
- [x] `shared/nutrients.json` に既存の5項目を書く。表示名と短い名前は今の Localizable.strings と同じ値にする
- [x] `shared/generate-swift.ts` を bun で書く。JSON の形を確かめてから、次を書き出す
  - `BiteLog/Generated/NutrientDefinitions.swift`
  - `BiteLog/Resources/{ja,en}.lproj/Nutrients.strings`
- [x] ルートの package.json に `generate:nutrients` を足す
- [x] 生成し、iOS の単体テストを全件通す
- [x] 生成し直しても差分が出ないことを確かめる
- [x] ios-development のスキルに、JSON を直したら生成してテストを流す手順を書く

## 確かめたこと

- iOS の単体テスト245件がすべて通った。新しいテストは4つで、表示名のテストは日本語と英語の2件ずつ流れる
- JSON の列名だけを変えると属性のテストが、英語の短い名前だけを変えると英語の表示名のテストだけが落ちた
- 生成し直しても3つのファイルに差分は出なかった
- group に無い値を入れたり、日本語の短い名前を消したりすると、生成スクリプトは理由を並べて何も書かずに止まった

## 振り返り

- 新しい依存は無い。bun と Swift の標準機能だけで作った
- 既存の `Nutrient` 型と Localizable.strings には触れていない。生成した型はまだテストからしか使っていない
