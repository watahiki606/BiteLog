-- food_masters: 全ユーザー共有のグローバル食品マスタ
CREATE TABLE IF NOT EXISTS food_masters (
  id TEXT PRIMARY KEY COLLATE NOCASE,
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
  created_by TEXT NOT NULL,
  -- 最初の5項目より後に足した栄養素。NULL は「分からない」
  salt_equivalent REAL,
  saturated_fat REAL,
  potassium REAL,
  calcium REAL,
  magnesium REAL,
  iron REAL,
  vitamin_a REAL,
  vitamin_d REAL,
  vitamin_c REAL,
  -- 値の出典。label、composition_table、ai_estimate、manual のどれか。NULL は分からない
  nutrient_source TEXT,
  -- 出典の参照先。成分表の食品番号か URL
  nutrient_source_ref TEXT,
  -- 食品の出典と違う出典の栄養素だけを並べた JSON。例 {"potassium":"composition_table"}
  nutrient_sources TEXT
);

CREATE INDEX IF NOT EXISTS idx_food_masters_product_name ON food_masters(product_name);

-- composition_foods: 日本食品標準成分表。可食部 100 g あたり。成分表の「-」は NULL
CREATE TABLE IF NOT EXISTS composition_foods (
  food_number TEXT PRIMARY KEY,
  food_group TEXT NOT NULL,
  name TEXT NOT NULL,
  search_text TEXT NOT NULL,
  edition TEXT NOT NULL,
  calories REAL,
  protein REAL,
  fat REAL,
  net_carbs REAL,
  dietary_fiber REAL,
  salt_equivalent REAL,
  saturated_fat REAL,
  potassium REAL,
  calcium REAL,
  magnesium REAL,
  iron REAL,
  vitamin_a REAL,
  vitamin_d REAL,
  vitamin_c REAL,
  raw_json TEXT NOT NULL
);

-- food_master_components: 食品を成分表の食品と重さの組にひも付ける
CREATE TABLE IF NOT EXISTS food_master_components (
  food_master_id TEXT NOT NULL COLLATE NOCASE REFERENCES food_masters(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  food_number TEXT NOT NULL REFERENCES composition_foods(food_number),
  grams REAL NOT NULL CHECK (grams > 0),
  PRIMARY KEY (food_master_id, position)
);

CREATE INDEX IF NOT EXISTS idx_food_master_components_food_number ON food_master_components(food_number);

-- log_items: ユーザーごとの食事ログ（user_idで分離）
CREATE TABLE IF NOT EXISTS log_items (
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

CREATE INDEX IF NOT EXISTS idx_log_items_user_date ON log_items(user_id, log_date);
CREATE INDEX IF NOT EXISTS idx_log_items_timestamp ON log_items(timestamp);

-- user_food_stats: ユーザーごとの食品使用統計（パーソナライズされた検索順位のため）
CREATE TABLE IF NOT EXISTS user_food_stats (
  user_id TEXT NOT NULL,
  food_master_id TEXT NOT NULL COLLATE NOCASE REFERENCES food_masters(id) ON DELETE CASCADE,
  usage_count INTEGER NOT NULL DEFAULT 0,
  last_used_date TEXT,
  last_number_of_servings REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY (user_id, food_master_id)
);

CREATE INDEX IF NOT EXISTS idx_user_food_stats_usage
  ON user_food_stats(user_id, usage_count DESC, last_used_date DESC);

-- body_measurements: ユーザーごとの体組成計測データ（HealthPlanet由来のCSV全17列）
-- measured_at（計測のISOタイムスタンプ）を自然キーとし、再インポート時の重複を防ぐ
CREATE TABLE IF NOT EXISTS body_measurements (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_date TEXT,
  measured_at TEXT NOT NULL,
  measurement_date_raw TEXT,
  measurement_time_raw TEXT,
  measurement_index INTEGER,
  item_count INTEGER,
  input_method TEXT,
  weight_kg REAL,
  body_fat_percent REAL,
  muscle_mass_kg REAL,
  muscle_score REAL,
  visceral_fat_level REAL,
  basal_metabolism_kcal REAL,
  metabolic_age INTEGER,
  bone_mass_kg REAL,
  body_water_percent REAL,
  page_url TEXT,
  UNIQUE(user_id, measured_at)
);

CREATE INDEX IF NOT EXISTS idx_body_measurements_user_date
  ON body_measurements(user_id, measured_at);

-- nutrition_goals: ユーザーごとの栄養目標（user_idで分離）
CREATE TABLE IF NOT EXISTS nutrition_goals (
  user_id TEXT PRIMARY KEY,
  target_protein REAL NOT NULL DEFAULT 150,
  target_fat REAL NOT NULL DEFAULT 80,
  target_net_carbs REAL NOT NULL DEFAULT 250,
  target_fiber REAL NOT NULL DEFAULT 25
);
