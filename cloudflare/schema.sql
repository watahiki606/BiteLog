-- food_masters: 全ユーザー共有のグローバル食品マスタ
CREATE TABLE IF NOT EXISTS food_masters (
  id TEXT PRIMARY KEY,
  brand_name TEXT NOT NULL DEFAULT '',
  product_name TEXT NOT NULL,
  calories REAL NOT NULL DEFAULT 0,
  dietary_fiber REAL NOT NULL DEFAULT 0,
  net_carbs REAL NOT NULL DEFAULT 0,
  fat REAL NOT NULL DEFAULT 0,
  protein REAL NOT NULL DEFAULT 0,
  portion_size REAL NOT NULL DEFAULT 1.0,
  portion_unit TEXT NOT NULL DEFAULT 'g',
  unique_key TEXT NOT NULL UNIQUE,
  created_by TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_food_masters_product_name ON food_masters(product_name);

-- log_items: ユーザーごとの食事ログ（user_idで分離）
CREATE TABLE IF NOT EXISTS log_items (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  log_date TEXT NOT NULL,
  meal_type TEXT NOT NULL CHECK(meal_type IN ('Breakfast','Lunch','Dinner','Snack','Other')),
  number_of_servings REAL NOT NULL DEFAULT 1.0,
  food_master_id TEXT REFERENCES food_masters(id) ON DELETE SET NULL,
  nutrition_snapshot_json TEXT,
  is_master_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_log_items_user_date ON log_items(user_id, log_date);
CREATE INDEX IF NOT EXISTS idx_log_items_timestamp ON log_items(timestamp);

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

-- nutrition_goals: ユーザーごとの栄養目標（user_idで分離）
CREATE TABLE IF NOT EXISTS nutrition_goals (
  user_id TEXT PRIMARY KEY,
  target_protein REAL NOT NULL DEFAULT 150,
  target_fat REAL NOT NULL DEFAULT 80,
  target_net_carbs REAL NOT NULL DEFAULT 250,
  target_fiber REAL NOT NULL DEFAULT 25
);
