# D1 のマイグレーションを wrangler の仕組みで足せるようにする

設計は `~/research/bitelog-nutrients/design.md` の6-1と、7章の PR 3。

## 計画

- [x] 本番の D1 の状態を読み取りで確かめる
- [x] 手順書の SQL を `migrations/` から `runbooks/` へ移す
- [x] `migrations/README.md` と web-admin-console のスキルに、置くものと本番の手順を書く
- [x] 本番と手元で、適用待ちが無いことを確かめる

## 振り返り

- 設計では、何もしない `0000_baseline.sql` を本番に流して記録の表を作る予定だった。本番には `d1_migrations` が5月からあり、`001_user_food_stats.sql` が適用済みとして記録されていたので、baseline は置かなかった
- 移す前の `migrations list --remote` は、手順書の `remove_other_meal_type.sql` を適用待ちとして並べていた。`migrations apply` を流せば、記録の表を作り直す手順書が本番に流れていた
