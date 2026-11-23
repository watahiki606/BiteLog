# D1 のマイグレーション

このフォルダの `.sql` は、`wrangler d1 migrations apply` が適用していないものを番号順にすべて流す。適用したものは D1 の `d1_migrations` 表に記録される。

- 置くのは、そのまま流してよい変更だけにする。手で1つずつ確かめながら流す手順書は `../runbooks/` に置く
- ファイル名は `0001_何をするか.sql` の形にする。本番には `001_user_food_stats.sql` が適用済みとして記録されているが、ファイルはもう無い
- 同じ PR で `../schema.sql` も同じ形に直す。テストと新しい環境は schema.sql から作る
- 一度本番に適用したファイルは書き換えない。直すときは新しい番号のファイルを足す

## 本番に適用する手順

```bash
cd cloudflare
npx wrangler d1 migrations apply bitelog --local    # 手元で流し、テストを通す
npx wrangler d1 time-travel info bitelog            # 適用前の bookmark を控える
npx wrangler d1 migrations list bitelog --remote    # 適用待ちを確かめる
npx wrangler d1 migrations apply bitelog --remote
```

新しい列を読む Worker は、列を足したあとにデプロイする。先に出すと、無い列を読んで落ちる。

戻すときは、まず Worker を前の版に戻す。D1 を戻すと、適用したあとの書き込みも消える。

```bash
npx wrangler rollback <前の Worker の版>
npx wrangler d1 time-travel restore bitelog --bookmark=<控えた bookmark>
```
