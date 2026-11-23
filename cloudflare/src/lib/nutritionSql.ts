// 栄養素の日次集計で共有する SQL 断片。栄養素の並びは定義ファイルから組み立てる。
import { ADDED_NUTRIENTS, NUTRIENTS, type AddedNutrientId, type Nutrients } from './nutrients';

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

const knownAlias = (column: string) => `known_${column}`;

// base CTE の按分済み栄養値を SUM する SELECT 列（GROUP BY と組み合わせて使う）。列名は API のキー。
// あとから足した栄養素は、値の分からない品を 0 として足さない。SUM は NULL を飛ばすので、
// 分からない品は NULL のまま残し、値の分かっていた品数を COUNT で数える。
// 全品が分からなければ SUM は NULL になる
const sumColumns = NUTRIENTS.map((n) => {
  const v = valueAlias(n.column);
  return n.core
    ? `SUM(CASE WHEN psize > 0 THEN ${v} * s / psize ELSE 0 END) AS ${n.id}`
    : `SUM(CASE WHEN ${v} IS NULL THEN NULL WHEN psize > 0 THEN ${v} * s / psize ELSE 0 END) AS ${n.id}`;
});
const knownCountColumns = ADDED_NUTRIENTS.map((n) => `COUNT(${valueAlias(n.column)}) AS ${knownAlias(n.column)}`);

export const NUTRITION_SUM_COLUMNS = [...sumColumns, ...knownCountColumns, 'COUNT(*) AS item_count'].join(',\n  ');

/** 集計の合計。あとから足した栄養素は、値の分かっていた品数を添える */
export type NutritionTotals = Nutrients & {
  /** 合計に入れた品の数 */
  itemCount: number;
  /** あとから足した栄養素ごとの、値の分かっていた品の数 */
  knownCounts: Record<AddedNutrientId, number>;
};

/** 記録の無い日の合計 */
export function emptyTotals(): NutritionTotals {
  return totalsFromRow({});
}

/** NUTRITION_SUM_COLUMNS で集計した行を、応答の形にする。分からない栄養素は合計を省く */
export function totalsFromRow(row: Record<string, unknown>): NutritionTotals {
  const totals: Record<string, unknown> = {};
  const knownCounts: Record<string, number> = {};
  for (const n of NUTRIENTS) {
    const sum = row[n.id];
    if (n.core) {
      totals[n.id] = sum ?? 0;
    } else {
      if (sum !== null && sum !== undefined) totals[n.id] = sum;
      knownCounts[n.id] = Number(row[knownAlias(n.column)] ?? 0);
    }
  }
  return { ...(totals as Nutrients), itemCount: Number(row.item_count ?? 0), knownCounts } as NutritionTotals;
}
