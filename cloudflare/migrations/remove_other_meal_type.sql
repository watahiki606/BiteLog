-- 食事の種類から「その他」(Other) を外す。
--
-- 本番には 2026-11-05 に適用済み。53,385 件を全列一致で写したことを確かめ、
-- アプリで記録が読めることを見てから log_items_old を消した。
-- 新しく DB を作るときは schema.sql に反映済みなので、これを流す必要は無い。
--
-- 2026-11-05 時点の本番の確認結果:
--   - meal_type = 'Other' の記録は 0 件
--   - log_items の列は下の CREATE TABLE と一致
--   - log_items を参照するトリガーや別の表は無い
--
-- SQLite は CHECK 制約を ALTER で変えられないので、表を作り直す。
-- 元の表はすぐには消さず log_items_old として残し、件数を確かめてから消す。
-- 手順ごとに区切ってあるので、1つずつ流して結果を確かめること。

-- 1. 新しい表を作り、記録を写す
CREATE TABLE log_items_new (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  log_date TEXT NOT NULL,
  meal_type TEXT NOT NULL CHECK(meal_type IN ('Breakfast','Lunch','Dinner','Snack')),
  number_of_servings REAL NOT NULL DEFAULT 1.0,
  food_master_id TEXT COLLATE NOCASE REFERENCES food_masters(id) ON DELETE SET NULL,
  nutrition_snapshot_json TEXT,
  is_master_deleted INTEGER NOT NULL DEFAULT 0
);

INSERT INTO log_items_new (
  id, user_id, timestamp, log_date, meal_type, number_of_servings,
  food_master_id, nutrition_snapshot_json, is_master_deleted
)
SELECT
  id, user_id, timestamp, log_date,
  CASE meal_type WHEN 'Other' THEN 'Snack' ELSE meal_type END,
  number_of_servings, food_master_id, nutrition_snapshot_json, is_master_deleted
FROM log_items;

-- 2. 件数が同じか確かめる。2つの数が違えば先へ進まない
SELECT (SELECT COUNT(*) FROM log_items) AS old_count,
       (SELECT COUNT(*) FROM log_items_new) AS new_count;

-- 3. 入れ替える。索引の名前は元の表が持っているので、先に外してから作り直す
ALTER TABLE log_items RENAME TO log_items_old;
ALTER TABLE log_items_new RENAME TO log_items;
DROP INDEX IF EXISTS idx_log_items_user_date;
DROP INDEX IF EXISTS idx_log_items_timestamp;
CREATE INDEX idx_log_items_user_date ON log_items(user_id, log_date);
CREATE INDEX idx_log_items_timestamp ON log_items(timestamp);

-- 4. 1 と 3 のあいだに追加された記録があれば写す
INSERT OR IGNORE INTO log_items
SELECT id, user_id, timestamp, log_date,
       CASE meal_type WHEN 'Other' THEN 'Snack' ELSE meal_type END,
       number_of_servings, food_master_id, nutrition_snapshot_json, is_master_deleted
FROM log_items_old;

-- 5. アプリで記録が見えることを確かめてから、元の表を消す
-- DROP TABLE log_items_old;
