-- user_food_stats: ユーザーごとの食品使用統計（パーソナライズされた検索順位のため）
CREATE TABLE IF NOT EXISTS user_food_stats (
  user_id TEXT NOT NULL,
  food_master_id TEXT NOT NULL REFERENCES food_masters(id) ON DELETE CASCADE,
  usage_count INTEGER NOT NULL DEFAULT 0,
  last_used_date TEXT,
  last_number_of_servings REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY (user_id, food_master_id)
);

CREATE INDEX IF NOT EXISTS idx_user_food_stats_usage
  ON user_food_stats(user_id, usage_count DESC, last_used_date DESC);
