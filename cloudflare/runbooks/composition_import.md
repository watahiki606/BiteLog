# 日本食品標準成分表の食品を入れ直す

日本食品標準成分表の本表と脂肪酸成分表の値を、国の一覧の食品として `food_masters` に入れる手順。
最初の 2,538 食品はマイグレーション `0008_composition_foods_into_food_masters.sql` で入れた。
この手順は、文部科学省が正誤表で Excel を差し替えたときに使う。

国の一覧の食品は次の形で持つ。

- 100 g あたり。ブランド名は空で、名前は一覧のまま
- 作った人は `composition`。編集と削除は管理者だけ
- 出典は `composition_table`、食品番号は `nutrient_source_ref`
- id は食品番号から決める。`src/lib/composition.ts` の `compositionFoodId`

## 入れる

```bash
cd cloudflare
# Excel は manifest.json の URL から落とし、ハッシュを確かめる。置き場所はどこでもよい
bun scripts/composition/build-sql.ts /tmp/mext-composition > /tmp/composition.sql

# 手元で流して件数を確かめる。本表は 2538 行、飽和脂肪酸の値がある行は 2147 行
# 脂肪酸成分表に載る 1967 行と、脂質が 0 なので飽和脂肪酸を 0 にした 180 行
npx wrangler d1 execute bitelog --local --file /tmp/composition.sql
npx wrangler d1 execute bitelog --local --command "SELECT COUNT(*), COUNT(saturated_fat) FROM food_masters WHERE created_by = 'composition'"

# 本番。流す前に bookmark を控える
npx wrangler d1 time-travel info bitelog
npx wrangler d1 execute bitelog --remote --file /tmp/composition.sql
npx wrangler d1 execute bitelog --remote --command "SELECT COUNT(*), COUNT(saturated_fat) FROM food_masters WHERE created_by = 'composition'"
# 白米めし 01088 は 156 kcal、糖質 35.6 g、食物繊維 1.5 g
npx wrangler d1 execute bitelog --remote --command "SELECT calories, net_carbs, dietary_fiber FROM food_masters WHERE nutrient_source_ref = '01088' AND created_by = 'composition'"
```

文は1食品に1つの `INSERT ... ON CONFLICT(id) DO UPDATE`。何度流しても同じ結果になる。
基本5項目の未測定は 0 にする。`food_masters` の基本5項目は NULL を持てない。

## 版を入れ替える

文部科学省は正誤表のたびに Excel を差し替える。成分表のページで更新日が manifest と違えば入れ替える。

1. 新しい Excel の URL とハッシュ、`edition`、`erratumDate` で `scripts/composition/manifest.json` を直す
2. 上の手順で SQL を作り、手元で流す
3. 前の版と比べる。手元に前の版を入れた D1 を残しておき、値が変わった食品、増えた食品、消えた食品を数える。
   版で消えた食品は SQL が消さないので、残すか管理者の画面から消すかを決める
4. アプリとサイトの出典の表示にある正誤表の日付を直す

記録の栄養素は食品の値から計算するので、値が変わった食品を使った過去の記録も新しい値になる。

## 戻す

流したあとに件数や値がおかしければ、控えた bookmark に戻す。戻すと、そのあとの書き込みもすべて消える。

```bash
npx wrangler d1 time-travel restore bitelog --bookmark=<控えた bookmark>
```
