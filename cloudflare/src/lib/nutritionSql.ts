// 栄養素の日次集計で共有する SQL 断片。栄養素の並びは定義ファイルから組み立てる。
import { NUTRIENTS } from './nutrients';

// base CTE の中で栄養素の値を持つ列の名前。API のキーと同じ名前にすると、
// 大文字小文字を区別しない SQLite では合計の列名とぶつかるので、接頭辞を付ける
const valueAlias = (column: string) => `v_${column}`;

// log_items から栄養値を取り出す base CTE。FoodMaster が結合できればそれを優先し、
// 無ければ nutrition_snapshot_json を使う（iOS の NutritionSnapshot と同順）。
// 栄養値は ratio = number_of_servings / portion_size で按分するため、
// 集計側（SUM 等）と組み合わせて使う。bind 順は user_id, from, to。
const nutrientValues = NUTRIENTS.map(
  (n) => `COALESCE(fm.${n.column}, json_extract(li.nutrition_snapshot_json, '$.${n.id}')) AS ${valueAlias(n.column)},`,
).join('\n    ');

export const NUTRITION_BASE_CTE = `base AS (
  SELECT li.log_date AS log_date, li.meal_type AS meal_type,
    li.number_of_servings AS s,
    ${nutrientValues}
    COALESCE(fm.portion_size, json_extract(li.nutrition_snapshot_json, '$.portionSize')) AS psize
  FROM log_items li
  LEFT JOIN food_masters fm ON fm.id = li.food_master_id
  WHERE li.user_id = ? AND li.log_date >= ? AND li.log_date <= ?
)`;

// base CTE の按分済み栄養値を SUM する SELECT 列（GROUP BY と組み合わせて使う）。列名は API のキー
export const NUTRITION_SUM_COLUMNS = NUTRIENTS.map(
  (n) => `SUM(CASE WHEN psize > 0 THEN ${valueAlias(n.column)} * s / psize ELSE 0 END) AS ${n.id}`,
).join(',\n  ');
