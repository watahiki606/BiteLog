// 食品を成分表の食品と重さの組にひも付け、成分表から値を計算して食品の列に書き込む。
// 記録の集計は食品の列を読むので、書き込んでおけば集計の SQL は変えずに済む。
import { NUTRIENTS } from './nutrients';
import { COMPOSITION_NUTRIENTS } from './composition';

/** ひも付けの1行。grams は食品の1回分に含まれる、その食材の可食部の重さ */
export type ComponentInput = { foodNumber: string; grams: number };

/** 1回分に入る食材の数の上限。料理を食材に分けても、これを超えることはまず無い */
export const MAX_COMPONENTS = 30;

/** 送られた components の形を確かめる。おかしければ null */
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

export const COMPOSITION_SOURCE = 'composition_table';

/** 食品の今の値と出典 */
export type FoodState = {
  values: Record<string, number | null>;
  nutrientSource: string | null;
  /** 食品の出典と違う出典の栄養素。id から出典 */
  nutrientSources: Record<string, string>;
};

/** 書き込む値と出典。values に無い列は変えない */
export type CompositionUpdate = {
  values: Record<string, number | null>;
  nutrientSources: Record<string, string>;
};

/**
 * 成分表から計算した値を、どの栄養素に書き込むかを決める。
 * - 値をすべて成分表から取った食品は、最初の5項目も含めて全部を書く。5項目は不明を持てないので、分からなければ 0
 * - ラベルや手入力の値を持つ食品は、値の分からない栄養素と、前に成分表で補った栄養素だけを書く。
 *   最初の5項目は 0 と不明を区別できないので書き換えない。補った栄養素は nutrientSources に印を付ける
 * totals が null なら、ひも付けが無くなったということ。補っていた値は分からないに戻す
 */
export function planCompositionUpdate(food: FoodState, totals: Record<string, number | null> | null): CompositionUpdate {
  const values: Record<string, number | null> = {};
  const nutrientSources = { ...food.nutrientSources };
  const wholeFromTable = food.nutrientSource === COMPOSITION_SOURCE;

  for (const n of NUTRIENTS) {
    const computed = totals?.[n.column] ?? null;
    if (wholeFromTable) {
      if (totals === null) continue;
      values[n.column] = n.core ? (computed ?? 0) : computed;
      delete nutrientSources[n.id];
      continue;
    }
    if (n.core) continue;
    const supplemented = nutrientSources[n.id] === COMPOSITION_SOURCE;
    const unknown = food.values[n.column] === null || food.values[n.column] === undefined;
    if (!supplemented && !unknown) continue;
    values[n.column] = computed;
    if (computed === null) delete nutrientSources[n.id];
    else nutrientSources[n.id] = COMPOSITION_SOURCE;
  }
  return { values, nutrientSources };
}

/** nutrient_sources の列の中身を読む。壊れていれば空 */
export function parseNutrientSources(text: unknown): Record<string, string> {
  if (typeof text !== 'string' || text === '') return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

/** nutrient_sources の列に書く中身。空なら NULL */
export function serializeNutrientSources(sources: Record<string, string>): string | null {
  const keys = Object.keys(sources).sort();
  return keys.length === 0 ? null : JSON.stringify(Object.fromEntries(keys.map((k) => [k, sources[k]])));
}
