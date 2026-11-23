-- 食品を、成分表の食品と重さの組にひも付ける。grams は食品の1回分に含まれる、その食材の可食部の重さ
CREATE TABLE IF NOT EXISTS food_master_components (
  food_master_id TEXT NOT NULL COLLATE NOCASE REFERENCES food_masters(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  food_number TEXT NOT NULL REFERENCES composition_foods(food_number),
  grams REAL NOT NULL CHECK (grams > 0),
  PRIMARY KEY (food_master_id, position)
);

-- 成分表の版を入れ替えるとき、消える食品番号が使われていないかを引く
CREATE INDEX IF NOT EXISTS idx_food_master_components_food_number ON food_master_components(food_number);

-- 食品の出典 nutrient_source と違う出典の栄養素だけを並べた JSON。例 {"potassium":"composition_table"}。
-- NULL は、全栄養素が食品の出典と同じ
ALTER TABLE food_masters ADD COLUMN nutrient_sources TEXT;
