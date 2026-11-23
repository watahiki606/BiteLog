# 日本食品標準成分表を D1 に入れる

`composition_foods` に、日本食品標準成分表の本表と脂肪酸成分表の値を入れる手順。
表はマイグレーション `0003_composition_foods.sql` で作る。データは 3 MB を超え、版を入れ替えるたびに流し直すので、マイグレーションには入れない。

## 入れる

```bash
cd cloudflare
# Excel は manifest.json の URL から落とし、ハッシュを確かめる。置き場所はどこでもよい
bun scripts/composition/build-sql.ts /tmp/mext-composition > /tmp/composition.sql

# 手元で流して件数を確かめる。本表は 2538 行、飽和脂肪酸の値がある行は 1967 行
npx wrangler d1 execute bitelog --local --file /tmp/composition.sql
npx wrangler d1 execute bitelog --local --command "SELECT COUNT(*), COUNT(saturated_fat) FROM composition_foods"

# 本番。流す前に bookmark を控える
npx wrangler d1 time-travel info bitelog
npx wrangler d1 execute bitelog --remote --file /tmp/composition.sql
npx wrangler d1 execute bitelog --remote --command "SELECT COUNT(*), COUNT(saturated_fat) FROM composition_foods"
# 白米めし 01088 は 156 kcal、糖質 35.6 g、食物繊維 1.5 g
npx wrangler d1 execute bitelog --remote --command "SELECT calories, net_carbs, dietary_fiber FROM composition_foods WHERE food_number = '01088'"
```

文は1行1つの `INSERT OR REPLACE`。何度流しても同じ結果になる。

## 版を入れ替える

文部科学省は正誤表のたびに Excel を差し替える。成分表のページで更新日が manifest と違えば入れ替える。

1. 新しい Excel の URL とハッシュ、`edition`、`erratumDate` で `scripts/composition/manifest.json` を直す
2. 上の手順で SQL を作り、手元で流す
3. 前の版と比べる。手元に前の版を入れた D1 を残しておき、値が変わった食品、増えた食品、消えた食品を数える
4. 消えた食品番号が `food_master_components` で使われていれば止まる。行は消さずに残し、ひも付けを直してから消す
5. 本番に流したあと、管理者で `POST /api/admin/composition/recompute` を呼び、ひも付けのある食品の値を計算し直す
6. アプリとサイトの出典の表示にある正誤表の日付を直す

計算し直すと、その食品を使った過去の記録の値も変わる。記録の値は食品に追従させる決まりで、正誤表は誤りを直すものなので、変わってよい。

## 戻す

流したあとに件数や値がおかしければ、控えた bookmark に戻す。戻すと、そのあとの書き込みもすべて消える。

```bash
npx wrangler d1 time-travel restore bitelog --bookmark=<控えた bookmark>
```
