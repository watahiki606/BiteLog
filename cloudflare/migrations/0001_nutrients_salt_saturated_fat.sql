-- 食塩相当量と飽和脂肪酸、値の出典を食品に足す。
-- どれも NULL を許し、NULL は「分からない」を表す。既存の食品は分からないまま残す。
-- 新しい列を読む Worker は、この適用のあとにデプロイする。
ALTER TABLE food_masters ADD COLUMN salt_equivalent REAL;
ALTER TABLE food_masters ADD COLUMN saturated_fat REAL;
-- label、composition_table、ai_estimate、manual のどれか
ALTER TABLE food_masters ADD COLUMN nutrient_source TEXT;
-- 成分表の食品番号か URL
ALTER TABLE food_masters ADD COLUMN nutrient_source_ref TEXT;
-- 写真の解析で作った食品は、ブランド名を AI にして保存してきた
UPDATE food_masters SET nutrient_source = 'ai_estimate' WHERE brand_name = 'AI';
