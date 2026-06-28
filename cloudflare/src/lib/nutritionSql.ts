// 栄養素の日次集計で共有する SQL 断片。
//
// log_items から栄養値を取り出す base CTE。FoodMaster が結合できればそれを優先し、
// 無ければ nutrition_snapshot_json を使う（iOS の NutritionSnapshot と同順）。
// 栄養値は ratio = number_of_servings / portion_size で按分するため、
// 集計側（SUM 等）と組み合わせて使う。bind 順は user_id, from, to。
export const NUTRITION_BASE_CTE = `base AS (
  SELECT li.log_date AS log_date, li.meal_type AS meal_type,
    li.number_of_servings AS s,
    COALESCE(fm.calories,      json_extract(li.nutrition_snapshot_json, '$.calories'))     AS cal,
    COALESCE(fm.protein,       json_extract(li.nutrition_snapshot_json, '$.protein'))      AS pro,
    COALESCE(fm.fat,           json_extract(li.nutrition_snapshot_json, '$.fat'))          AS fat,
    COALESCE(fm.net_carbs,     json_extract(li.nutrition_snapshot_json, '$.netCarbs'))     AS nc,
    COALESCE(fm.dietary_fiber, json_extract(li.nutrition_snapshot_json, '$.dietaryFiber')) AS fib,
    COALESCE(fm.portion_size,  json_extract(li.nutrition_snapshot_json, '$.portionSize'))  AS psize
  FROM log_items li
  LEFT JOIN food_masters fm ON fm.id = li.food_master_id
  WHERE li.user_id = ? AND li.log_date >= ? AND li.log_date <= ?
)`;

// base CTE の按分済み栄養値を SUM する SELECT 列（GROUP BY と組み合わせて使う）。
export const NUTRITION_SUM_COLUMNS = `SUM(CASE WHEN psize > 0 THEN cal * s / psize ELSE 0 END) AS calories,
  SUM(CASE WHEN psize > 0 THEN pro * s / psize ELSE 0 END) AS protein,
  SUM(CASE WHEN psize > 0 THEN fat * s / psize ELSE 0 END) AS fat,
  SUM(CASE WHEN psize > 0 THEN nc  * s / psize ELSE 0 END) AS netCarbs,
  SUM(CASE WHEN psize > 0 THEN fib * s / psize ELSE 0 END) AS dietaryFiber`;
