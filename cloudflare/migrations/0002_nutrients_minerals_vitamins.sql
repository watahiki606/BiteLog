-- カリウム、カルシウム、マグネシウム、鉄、ビタミン A、D、C を足す。
-- 第1段階の栄養素と同じく NULL を許し、NULL は「分からない」を表す
ALTER TABLE food_masters ADD COLUMN potassium REAL;
ALTER TABLE food_masters ADD COLUMN calcium REAL;
ALTER TABLE food_masters ADD COLUMN magnesium REAL;
ALTER TABLE food_masters ADD COLUMN iron REAL;
ALTER TABLE food_masters ADD COLUMN vitamin_a REAL;
ALTER TABLE food_masters ADD COLUMN vitamin_d REAL;
ALTER TABLE food_masters ADD COLUMN vitamin_c REAL;
