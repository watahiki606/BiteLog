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
 * 栄養素の名前。web は Worker の応答の型を Hono RPC で推論しているが、
 * JSON から読んだ id は string に広がってしまう。応答の型を保つため、名前を型でも持つ。
 * 定義ファイルと食い違えば nutrients.test.ts が落ちる。
 */
/** 最初からある5項目。必ず値を持つ */
export const CORE_NUTRIENT_IDS = ['calories', 'protein', 'fat', 'netCarbs', 'dietaryFiber'] as const;
/** あとから足した栄養素。値が無ければ「分からない」 */
export const ADDED_NUTRIENT_IDS = ['saltEquivalent', 'saturatedFat'] as const;
export type CoreNutrientId = (typeof CORE_NUTRIENT_IDS)[number];
export type AddedNutrientId = (typeof ADDED_NUTRIENT_IDS)[number];
export type CoreNutrients = Record<CoreNutrientId, number>;
export type AddedNutrients = Partial<Record<AddedNutrientId, number>>;
export type Nutrients = CoreNutrients & AddedNutrients;

/** 値の出典。食品ごとに1つ持つ */
export const NUTRIENT_SOURCES = ['label', 'composition_table', 'ai_estimate', 'manual'] as const;
export type NutrientSource = (typeof NUTRIENT_SOURCES)[number];

export function isNutrientSource(value: unknown): value is NutrientSource {
  return (NUTRIENT_SOURCES as readonly unknown[]).includes(value);
}

/** あとから足した栄養素の定義 */
export const ADDED_NUTRIENTS: readonly NutrientDefinition[] = NUTRIENTS.filter((n) => !n.core);

/** food_masters の栄養素の列。定義の並び順 */
export const NUTRIENT_COLUMNS: readonly string[] = NUTRIENTS.map((n) => n.column);

/**
 * D1 の行から、栄養素の値を API のキーで取り出す。
 * 値の無い栄養素はキーごと省く。core は NOT NULL なので必ず入る。
 */
export function nutrientsFromRow(row: Record<string, unknown>): Nutrients {
  const values: Record<string, unknown> = {};
  for (const n of NUTRIENTS) {
    const value = row[n.column];
    if (value !== null && value !== undefined) values[n.id] = value;
  }
  return values as Nutrients;
}

/**
 * 送られた本文から、NUTRIENT_COLUMNS の並びで値を取り出す。無ければ null。
 * 型は確かめずにそのまま渡す。数字の文字列でも D1 の REAL の列は数として保存するので、それに任せる
 */
export function nutrientBinds(body: Record<string, unknown>): unknown[] {
  return NUTRIENTS.map((n) => body[n.id] ?? null);
}

const SNAPSHOT_KEYS = new Set(['brandName', 'productName', 'portionSize', 'portionUnit', ...NUTRIENTS.map((n) => n.id)]);

/**
 * 記録のスナップショットから、名前と量と定義にある栄養素だけを残す。
 * 食品を丸ごと送ってくるクライアントもあり、id や使用回数まで保存すると読み返したときに紛らわしい
 */
export function snapshotForStorage(snapshot: object): Record<string, unknown> {
  return Object.fromEntries(Object.entries(snapshot).filter(([key]) => SNAPSHOT_KEYS.has(key)));
}
