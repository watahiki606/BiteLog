// ひも付けの読み書きと、成分表から計算した値の書き込み。どこに何を書くかは foodComposition.ts が決める。
import { NUTRIENTS } from './nutrients';
import { COMPOSITION_NUTRIENTS } from './composition';
import {
  COMPOSITION_SOURCE, parseNutrientSources, planCompositionUpdate, serializeNutrientSources, sumComponents,
  type ComponentInput,
} from './foodComposition';

/** 食品番号のうち、成分表に無いものを返す */
export async function unknownFoodNumbers(db: D1Database, components: readonly ComponentInput[]): Promise<string[]> {
  const numbers = [...new Set(components.map((c) => c.foodNumber))];
  if (numbers.length === 0) return [];
  const { results } = await db.prepare(
    `SELECT food_number FROM composition_foods WHERE food_number IN (${numbers.map(() => '?').join(', ')})`,
  ).bind(...numbers).all<{ food_number: string }>();
  const found = new Set(results.map((r) => r.food_number));
  return numbers.filter((n) => !found.has(n));
}

/** ひも付けを置き換える文 */
export function replaceComponentsStatements(db: D1Database, foodId: string, components: readonly ComponentInput[]): D1PreparedStatement[] {
  return [
    db.prepare('DELETE FROM food_master_components WHERE food_master_id = ?').bind(foodId),
    ...components.map((c, i) =>
      db.prepare('INSERT INTO food_master_components (food_master_id, position, food_number, grams) VALUES (?, ?, ?, ?)')
        .bind(foodId, i, c.foodNumber, c.grams)),
  ];
}

/** 食品のひも付けを、成分表の食品名付きで返す */
export async function componentsOf(db: D1Database, foodId: string) {
  const { results } = await db.prepare(
    `SELECT c.food_number, c.grams, cf.name FROM food_master_components c
     LEFT JOIN composition_foods cf ON cf.food_number = c.food_number
     WHERE c.food_master_id = ? ORDER BY c.position`,
  ).bind(foodId).all<{ food_number: string; grams: number; name: string | null }>();
  return results.map((r) => ({ foodNumber: r.food_number, grams: r.grams, name: r.name }));
}

const NUTRIENT_COLUMNS = NUTRIENTS.map((n) => n.column);
const COMPOSITION_COLUMNS = COMPOSITION_NUTRIENTS.map((n) => n.column);

/**
 * 食品のひも付けから成分表の値を計算し、食品の列に書き込む。
 * ひも付けが無ければ、前に補っていた値を分からないに戻す
 */
export async function applyFoodComposition(db: D1Database, foodId: string): Promise<void> {
  const food = await db.prepare(
    `SELECT ${NUTRIENT_COLUMNS.join(', ')}, nutrient_source, nutrient_sources FROM food_masters WHERE id = ?`,
  ).bind(foodId).first<Record<string, unknown>>();
  if (!food) return;

  const { results } = await db.prepare(
    `SELECT c.grams, cf.food_number AS found, ${COMPOSITION_COLUMNS.map((col) => `cf.${col}`).join(', ')}
     FROM food_master_components c
     LEFT JOIN composition_foods cf ON cf.food_number = c.food_number
     WHERE c.food_master_id = ? ORDER BY c.position`,
  ).bind(foodId).all<Record<string, unknown>>();

  const totals = results.length === 0
    ? null
    : sumComponents(results.map((r) => ({
        grams: Number(r.grams),
        per100g: r.found === null ? null : Object.fromEntries(COMPOSITION_COLUMNS.map((col) => [col, r[col] as number | null])),
      })));

  const nutrientSource = (food.nutrient_source as string | null) ?? null;
  const plan = planCompositionUpdate({
    values: Object.fromEntries(NUTRIENT_COLUMNS.map((col) => [col, food[col] as number | null])),
    nutrientSource,
    nutrientSources: parseNutrientSources(food.nutrient_sources),
  }, totals);

  const sets = Object.keys(plan.values).map((col) => `${col} = ?`);
  const binds: unknown[] = Object.values(plan.values);
  sets.push('nutrient_sources = ?');
  binds.push(serializeNutrientSources(plan.nutrientSources));
  // 値をすべて成分表から取った食品は、食材が1つならその食品番号を参照先にする
  if (nutrientSource === COMPOSITION_SOURCE && totals !== null) {
    sets.push('nutrient_source_ref = ?');
    const numbers = results.map((r) => r.found as string | null);
    binds.push(numbers.length === 1 ? numbers[0] : null);
  }
  await db.prepare(`UPDATE food_masters SET ${sets.join(', ')} WHERE id = ?`).bind(...binds, foodId).run();
}

/**
 * 手で値を入れた栄養素から、成分表で補った印を外す。
 * その値は食品の出典の値になり、あとで計算し直しても書き換えない
 */
export async function clearSupplementMarks(db: D1Database, foodId: string, editedIds: readonly string[]): Promise<void> {
  if (editedIds.length === 0) return;
  const row = await db.prepare('SELECT nutrient_sources FROM food_masters WHERE id = ?').bind(foodId).first<{ nutrient_sources: string | null }>();
  const sources = parseNutrientSources(row?.nutrient_sources);
  let changed = false;
  for (const id of editedIds) {
    if (id in sources) {
      delete sources[id];
      changed = true;
    }
  }
  if (changed) {
    await db.prepare('UPDATE food_masters SET nutrient_sources = ? WHERE id = ?').bind(serializeNutrientSources(sources), foodId).run();
  }
}
