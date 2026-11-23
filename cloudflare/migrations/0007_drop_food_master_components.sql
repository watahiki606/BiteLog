-- 食品は栄養素の列に値を持つだけにする。成分表は、手入力で値を欄に書き込むときと写真の解析で引くだけで、食品と結ばない。
-- 食品と成分表の対応の表と、成分表で補った栄養素の印の列を消す。値はすでに食品の列に入っているので残る
DROP INDEX IF EXISTS idx_food_master_components_food_number;
DROP TABLE IF EXISTS food_master_components;
ALTER TABLE food_masters DROP COLUMN nutrient_sources;
