// 写真の解析で、料理を成分表の食材と重さに分けさせ、値は成分表から引く。
// AI に微量栄養素の数値を直接答えさせると大きく外れる。成分表を引く形のほうが誤差が小さいと報告されている。
import { NUTRIENTS } from './nutrients';
import { COMPOSITION_NUTRIENTS } from './composition';

/** 食材の1行。grams は1回分に含まれる、その食材の可食部の重さ */
export type ComponentInput = { foodNumber: string; grams: number };

/** 1回分に入る食材の数の上限。料理を食材に分けても、これを超えることはまず無い */
export const MAX_COMPONENTS = 30;

/** AI が答えた食材の形を確かめる。おかしければ null */
export function parseComponents(value: unknown): ComponentInput[] | null {
  if (!Array.isArray(value) || value.length > MAX_COMPONENTS) return null;
  const components: ComponentInput[] = [];
  for (const item of value) {
    const foodNumber = (item as { foodNumber?: unknown })?.foodNumber;
    const grams = Number((item as { grams?: unknown })?.grams);
    if (typeof foodNumber !== 'string' || !/^\d{5}$/.test(foodNumber)) return null;
    if (!Number.isFinite(grams) || grams <= 0) return null;
    components.push({ foodNumber, grams });
  }
  return components;
}

/** 成分表の1食品の100 g あたりの値。列名で引く。未測定は null */
export type Per100g = Record<string, number | null>;

/**
 * 食材ごとの値を重さで足す。1つでも値の分からない食材があれば、その栄養素は分からないにする。
 * 分かる食材の分だけを足すと、小さな値が分かっているように見えてしまうため
 */
export function sumComponents(components: readonly { grams: number; per100g: Per100g | null }[]): Record<string, number | null> {
  const totals: Record<string, number | null> = {};
  for (const n of COMPOSITION_NUTRIENTS) {
    let total: number | null = components.length > 0 ? 0 : null;
    for (const c of components) {
      const v = c.per100g?.[n.column];
      if (v === null || v === undefined || total === null) {
        total = null;
        continue;
      }
      total += (v * c.grams) / 100;
    }
    totals[n.column] = total === null ? null : Math.round(total * 10_000) / 10_000;
  }
  return totals;
}

/** 指示に足す規則。成分表の一覧はこの後ろに置く */
export const COMPONENT_RULES = `

components
- Split what the user eats in this sitting into foods from the composition table at the end of these instructions. For each, give the food number exactly as listed and the edible grams in this portion.
- Choose the form as eaten: cooked rice is めし, boiled noodles are ゆで, grilled meat is 焼き. Include cooking oil, dressing, sauce and soup when they are clearly part of the meal.
- grams is a weight, never a count. When only the count is known, estimate the weight of one piece, e.g. one wafer is about 10 g and one egg about 50 g.
- Do not leave out the rice, noodles or bread under or beside the topping. A 丼 or curry rice includes the rice even when the topping hides it, about 250 g for one serving.
- For granular or powdered seasonings such as 顆粒和風だし, give the grams of the dry powder, usually 2 to 10 g. For a liquid stock, prefer the ready-to-use form such as かつおだし.
- Build soups and sauces from the table as served. For noodle soup, count half of the soup, since most people leave the rest.
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
  // 濃縮の食品は薄める前の値で、そのまま重さを掛けると食塩が何倍にもなる。評価でラーメンが 58 g になったので一覧から外す。
  // 濃縮還元のジュースはそのまま飲む形なので残す
  const { results } = await db.prepare(
    "SELECT food_number, name FROM composition_foods WHERE name NOT LIKE '%濃縮%' OR name LIKE '%濃縮還元%' ORDER BY food_number",
  )
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

  const totals = sumComponents(components.map((c) => ({ grams: c.grams, per100g: per100g.get(c.foodNumber) ?? null })));
  // 1食で食塩が 20 g を超えるのは、粉の調味料をスープの量で数えたような読み違い。評価で顆粒だし 100 g が出た。
  // 外れた値を成分表の値として出すより、AI の答えた数値に戻す
  if ((totals.salt_equivalent ?? 0) > MAX_PLAUSIBLE_SALT) return null;
  return { components: components.map((c) => ({ ...c, name: catalog.names.get(c.foodNumber)! })), totals };
}

/** 1回分の食塩相当量として考えられる上限。ラーメンの汁を全部飲んでも 10 g 前後 */
export const MAX_PLAUSIBLE_SALT = 20;

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
