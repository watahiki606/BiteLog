// 食品の表を読み書きする SQL。栄養素の列は定義ファイルの並びで組み立てる。
import { NUTRIENTS, NUTRIENT_COLUMNS, nutrientBinds, type CoreNutrients } from './nutrients';

/** 食品を作るときに送られてくる本文。栄養素は API のキーで並ぶ */
export type FoodMasterInput = CoreNutrients & {
  id: string;
  brandName: string;
  productName: string;
  portionSize: number;
  portionUnit: string;
  uniqueKey: string;
};

/** fm を別名にした food_masters の栄養素の列。SELECT に並べる */
export const FM_NUTRIENT_SELECT = NUTRIENT_COLUMNS.map((column) => `fm.${column}`).join(', ');

const INSERT_COLUMNS = [
  'id', 'brand_name', 'product_name', ...NUTRIENT_COLUMNS,
  'portion_size', 'portion_unit', 'unique_key', 'created_by',
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
  );
}

/** 送られた栄養素だけを変える SET 句の断片と、その並びの値。送られなかった栄養素は今の値のまま */
export function nutrientUpdate(body: Record<string, unknown>): { sql: string; binds: unknown[] } {
  return {
    sql: NUTRIENTS.map((n) => `${n.column} = COALESCE(?, ${n.column})`).join(',\n        '),
    binds: nutrientBinds(body),
  };
}
