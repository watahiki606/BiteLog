// 栄養素の一覧。正本は shared/nutrients.json で、iOS は同じファイルから Swift を生成している。
// 食品の列の並び、INSERT と UPDATE、応答への変換、集計の SQL は、すべてこの一覧から組み立てる。
import definitions from '../../../shared/nutrients.json';

export type NutrientDefinition = {
  /** API の JSON とスナップショットのキー */
  id: string;
  /** D1 の food_masters の列名 */
  column: string;
  unit: string;
  fractionDigits: number;
  group: string;
  /** 最初からある5項目。NOT NULL で、未入力は 0 として持つ */
  core: boolean;
  label: string;
  names: Record<string, string>;
  shortNames: Record<string, string>;
};

export const NUTRIENTS: readonly NutrientDefinition[] = definitions;

// id と列名は SQL の文に直接埋め込むので、名前として安全な形だけを受け付ける。
// 定義ファイルに誤りがあれば、Worker が動き出す前に落とす
for (const n of NUTRIENTS) {
  if (!/^[a-z][A-Za-z0-9]*$/.test(n.id) || !/^[a-z][a-z0-9_]*$/.test(n.column)) {
    throw new Error(`栄養素の id か列名が不正: ${n.id} / ${n.column}`);
  }
}

/**
 * 最初からある5項目の名前。web は Worker の応答の型を Hono RPC で推論しているが、
 * JSON から読んだ id は string に広がってしまう。応答の型を保つため、名前を型でも持つ。
 * 定義ファイルの core と食い違えば nutrients.test.ts が落ちる。
 */
export const CORE_NUTRIENT_IDS = ['calories', 'protein', 'fat', 'netCarbs', 'dietaryFiber'] as const;
export type CoreNutrientId = (typeof CORE_NUTRIENT_IDS)[number];
export type CoreNutrients = Record<CoreNutrientId, number>;

/** food_masters の栄養素の列。定義の並び順 */
export const NUTRIENT_COLUMNS: readonly string[] = NUTRIENTS.map((n) => n.column);

/**
 * D1 の行から、栄養素の値を API のキーで取り出す。
 * 値の無い栄養素はキーごと省く。core は NOT NULL なので必ず入る。
 */
export function nutrientsFromRow(row: Record<string, unknown>): CoreNutrients {
  const values: Record<string, unknown> = {};
  for (const n of NUTRIENTS) {
    const value = row[n.column];
    if (value !== null && value !== undefined) values[n.id] = value;
  }
  return values as CoreNutrients;
}

/**
 * 送られた本文から、NUTRIENT_COLUMNS の並びで値を取り出す。無ければ null。
 * 型は確かめずにそのまま渡す。数字の文字列でも D1 の REAL の列は数として保存するので、それに任せる
 */
export function nutrientBinds(body: Record<string, unknown>): unknown[] {
  return NUTRIENTS.map((n) => body[n.id] ?? null);
}
