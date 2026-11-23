// 食品の表を読み書きする SQL。栄養素の列は定義ファイルの並びで組み立てる。
import { NUTRIENTS, NUTRIENT_COLUMNS, isNutrientSource, nutrientBinds, type Nutrients, type NutrientSource } from './nutrients';

/** 食品を作るときに送られてくる本文。栄養素は API のキーで並ぶ */
export type FoodMasterInput = Nutrients & {
  id: string;
  brandName: string;
  productName: string;
  portionSize: number;
  portionUnit: string;
  uniqueKey: string;
  nutrientSource?: NutrientSource | null;
  nutrientSourceRef?: string | null;
};

/** fm を別名にした food_masters の栄養素と出典の列。SELECT に並べる */
export const FM_NUTRIENT_SELECT = [...NUTRIENT_COLUMNS, 'nutrient_source', 'nutrient_source_ref', 'nutrient_sources']
  .map((column) => `fm.${column}`)
  .join(', ');

/** 出典が送られていて、決まった種類のどれでもなければ true */
export function hasInvalidSource(body: { nutrientSource?: unknown }): boolean {
  return body.nutrientSource !== undefined && body.nutrientSource !== null && !isNutrientSource(body.nutrientSource);
}

const INSERT_COLUMNS = [
  'id', 'brand_name', 'product_name', ...NUTRIENT_COLUMNS,
  'portion_size', 'portion_unit', 'unique_key', 'created_by', 'nutrient_source', 'nutrient_source_ref',
];

const INSERT_SQL = `INSERT INTO food_masters
  (${INSERT_COLUMNS.join(', ')})
 VALUES (${INSERT_COLUMNS.map(() => '?').join(', ')})
 ON CONFLICT(unique_key) DO NOTHING`;

/** 食品を1つ作る文。同じ unique_key の食品が既にあれば何もしない */
export function insertFoodMaster(db: D1Database, item: FoodMasterInput, userId: string): D1PreparedStatement {
  return db.prepare(INSERT_SQL).bind(
    item.id, item.brandName, item.productName, ...nutrientBinds(item),
    item.portionSize, item.portionUnit, item.uniqueKey, userId,
    item.nutrientSource ?? null, item.nutrientSourceRef ?? null,
  );
}

/**
 * 送られた栄養素と出典だけを変える SET 句の断片と、その並びの値。
 * 最初の5項目は必ず値を持つので、null が来ても今の値を残す。
 * それ以外はキーがあれば変え、null なら分からないに戻す。キーが無ければ今の値のまま。
 * 公開中の古い版のアプリは新しい栄養素のキーを送らないので、その値を消さずに済む
 */
export function nutrientUpdate(body: Record<string, unknown>): { sql: string[]; binds: unknown[] } {
  const sql: string[] = [];
  const binds: unknown[] = [];
  for (const n of NUTRIENTS) {
    if (n.core) {
      sql.push(`${n.column} = COALESCE(?, ${n.column})`);
      binds.push(body[n.id] ?? null);
    } else if (n.id in body) {
      sql.push(`${n.column} = ?`);
      binds.push(body[n.id] ?? null);
    }
  }
  for (const [key, column] of [['nutrientSource', 'nutrient_source'], ['nutrientSourceRef', 'nutrient_source_ref']]) {
    if (key in body) {
      sql.push(`${column} = ?`);
      binds.push(body[key] ?? null);
    }
  }
  return { sql, binds };
}
