// 写真の解析で、料理を成分表の食材と重さに分けさせ、値は成分表から引く。
// AI に微量栄養素の数値を直接答えさせると大きく外れる。成分表を引く形のほうが誤差が小さいと報告されている。
import { NUTRIENTS } from './nutrients';
import { COMPOSITION_NUTRIENTS } from './composition';
import { parseComponents, sumComponents, type Per100g } from './foodComposition';

/** 指示に足す規則。成分表の一覧はこの後ろに置く */
export const COMPONENT_RULES = `

components
- Split what the user eats in this sitting into foods from the composition table at the end of these instructions. For each, give the food number exactly as listed and the edible grams in this portion.
- Choose the form as eaten: cooked rice is めし, boiled noodles are ゆで, grilled meat is 焼き. Include cooking oil, dressing, sauce and soup when they are clearly part of the meal.
- A dish listed in the table, such as 親子丼の具 or とん汁, may be used as one food.
- For a packaged product with a nutrition label, give the closest table food for the product with the package weight. The app uses it only to fill nutrients the label does not show.
- If no food in the table fits, return an empty array.`;

/** 成分表の一覧。並びを毎回同じにして、前方一致のキャッシュが効くようにする */
export type Catalog = { text: string; names: Map<string, string> };

let cached: Catalog | null = null;

/** 成分表の食品番号と食品名の一覧。表が空なら null で、写真の解析は今までどおり数値だけを答えさせる */
export async function loadCatalog(db: D1Database | undefined): Promise<Catalog | null> {
  if (cached) return cached;
  if (!db) return null;
  const { results } = await db.prepare('SELECT food_number, name FROM composition_foods ORDER BY food_number')
    .all<{ food_number: string; name: string }>();
  if (results.length === 0) return null;
  cached = {
    text: `\n\nComposition table (food number and name, values per 100 g):\n${results.map((r) => `${r.food_number} ${r.name}`).join('\n')}`,
    names: new Map(results.map((r) => [r.food_number, r.name])),
  };
  return cached;
}

/** テストで一覧を読み直させる */
export function resetCatalogCache(): void {
  cached = null;
}

export const COMPONENTS_SCHEMA = {
  type: 'array',
  items: {
    type: 'object',
    properties: {
      foodNumber: { type: 'string', description: 'Five-digit food number from the composition table' },
      grams: { type: 'number', description: 'Edible grams of this food in the portion' },
    },
    required: ['foodNumber', 'grams'],
    additionalProperties: false,
  },
};

export type ResolvedComponents = {
  components: { foodNumber: string; name: string; grams: number }[];
  /** 列名から、食材の重さで足した値 */
  totals: Record<string, number | null>;
};

/** AI が答えた食材を確かめ、成分表から値を足す。表に無い番号や重さの無い行は捨てる。残らなければ null */
export async function resolveComponents(db: D1Database, catalog: Catalog, raw: unknown): Promise<ResolvedComponents | null> {
  if (!Array.isArray(raw)) return null;
  const valid = raw.filter((c) => catalog.names.has((c as { foodNumber?: string })?.foodNumber ?? '') && Number((c as { grams?: unknown }).grams) > 0);
  const components = parseComponents(valid);
  if (!components || components.length === 0) return null;

  const numbers = [...new Set(components.map((c) => c.foodNumber))];
  const columns = COMPOSITION_NUTRIENTS.map((n) => n.column);
  const { results } = await db.prepare(
    `SELECT food_number, ${columns.join(', ')} FROM composition_foods WHERE food_number IN (${numbers.map(() => '?').join(', ')})`,
  ).bind(...numbers).all<Record<string, unknown>>();
  const per100g = new Map<string, Per100g>(results.map((r) => [
    r.food_number as string, Object.fromEntries(columns.map((col) => [col, r[col] as number | null])),
  ]));

  return {
    components: components.map((c) => ({ ...c, name: catalog.names.get(c.foodNumber)! })),
    totals: sumComponents(components.map((c) => ({ grams: c.grams, per100g: per100g.get(c.foodNumber) ?? null }))),
  };
}

/**
 * 応答の栄養素の値を決める。キーは API の id。
 * - 値を表示か公式の値から読んだときは、読んだ値を残し、分からない栄養素だけを成分表で補う
 * - 写真から推定したときは、食材と重さから成分表で引いた値を使う。AI が思い出した数値より確かなため
 * - 食材が無ければ、AI の答えた値のまま
 */
export function mergeNutrients(
  model: Record<string, number | null>,
  resolved: ResolvedComponents | null,
  fromLabel: boolean,
): { values: Record<string, number>; fromTable: boolean } {
  const values: Record<string, number> = {};
  for (const n of NUTRIENTS) {
    const read = model[n.id] ?? null;
    const table = resolved?.totals[n.column] ?? null;
    let value: number | null;
    if (!resolved) value = read;
    else if (fromLabel) value = read ?? (n.core ? null : table);
    else value = table ?? (n.core ? read : null);
    if (value === null && n.core) value = 0;
    if (value !== null) values[n.id] = Math.round(value * 100) / 100;
  }
  return { values, fromTable: resolved !== null && !fromLabel };
}
