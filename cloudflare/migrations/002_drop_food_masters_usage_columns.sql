-- food_mastersのusage関連カラムを削除（user_food_statsに移行済み）
DROP INDEX IF EXISTS idx_food_masters_usage;
ALTER TABLE food_masters DROP COLUMN usage_count;
ALTER TABLE food_masters DROP COLUMN last_used_date;
ALTER TABLE food_masters DROP COLUMN last_number_of_servings;
