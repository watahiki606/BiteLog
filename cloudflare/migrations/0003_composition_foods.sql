-- 日本食品標準成分表。可食部 100 g あたりの値。
-- データは scripts/composition/build-sql.ts で作った SQL を runbooks/composition_import.md の手順で入れる。
-- 栄養素の列名は food_masters と同じにし、成分表の「-」は NULL で持つ
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
