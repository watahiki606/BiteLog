-- 詳しい栄養素にヨウ素、セレン、クロム、モリブデン、ビオチンを足す
-- 成分表で本表の約46%が未測定。未測定の食材を含む食品は NULL、つまり「分からない」のままにし、0 にしない
-- 成分表の列は scripts/composition/build-sql.ts で流し直して埋める
ALTER TABLE food_masters ADD COLUMN iodine REAL;
ALTER TABLE food_masters ADD COLUMN selenium REAL;
ALTER TABLE food_masters ADD COLUMN chromium REAL;
ALTER TABLE food_masters ADD COLUMN molybdenum REAL;
ALTER TABLE food_masters ADD COLUMN biotin REAL;
ALTER TABLE composition_foods ADD COLUMN iodine REAL;
ALTER TABLE composition_foods ADD COLUMN selenium REAL;
ALTER TABLE composition_foods ADD COLUMN chromium REAL;
ALTER TABLE composition_foods ADD COLUMN molybdenum REAL;
ALTER TABLE composition_foods ADD COLUMN biotin REAL;
