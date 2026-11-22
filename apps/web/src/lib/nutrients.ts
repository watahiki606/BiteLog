// 栄養素の一覧。Worker と同じ定義を使い、web では5項目ごとの手書きをしない。
import {
  NUTRIENTS, CORE_NUTRIENT_IDS, ADDED_NUTRIENTS, ADDED_NUTRIENT_IDS,
  type CoreNutrientId, type CoreNutrients, type AddedNutrientId, type AddedNutrients, type NutrientDefinition,
} from '../../../../cloudflare/src/lib/nutrients';

export {
  NUTRIENTS, CORE_NUTRIENT_IDS, ADDED_NUTRIENTS, ADDED_NUTRIENT_IDS,
  type CoreNutrientId, type CoreNutrients, type AddedNutrientId, type AddedNutrients, type NutrientDefinition,
};

/** 最初の5項目をすべて 0 にした値 */
export function zeroNutrients(): CoreNutrients {
  return mapNutrients(() => 0);
}

/** 最初の5項目それぞれに同じ計算をする */
export function mapNutrients(f: (id: CoreNutrientId) => number): CoreNutrients {
  const values = {} as CoreNutrients;
  for (const id of CORE_NUTRIENT_IDS) values[id] = f(id);
  return values;
}

/** 栄養素ごとに足す */
export function addNutrients(a: CoreNutrients, b: CoreNutrients): CoreNutrients {
  return mapNutrients((id) => a[id] + b[id]);
}

/** 栄養素ごとに同じ数で割る */
export function divideNutrients(v: CoreNutrients, divisor: number): CoreNutrients {
  return mapNutrients((id) => v[id] / divisor);
}

/** 栄養素の値だけを取り出す。日付などほかの項目が混ざった行から使う */
export function pickNutrients(source: CoreNutrients): CoreNutrients {
  return mapNutrients((id) => source[id]);
}

/** 入力欄の刻み。定義の桁数が 1 なら 0.1 */
export function inputStep(n: NutrientDefinition): number {
  return 10 ** -n.fractionDigits;
}

/**
 * 値の分かっているものだけを足す。あとから足した栄養素は値の分からない品があり、
 * 0 として足すと少なく見えるので、何品ぶんの合計かを添える
 */
export function sumKnown(values: readonly (number | null | undefined)[]): { total: number | null; known: number } {
  let total = 0;
  let known = 0;
  for (const v of values) {
    if (v == null) continue;
    total += v;
    known += 1;
  }
  return { total: known > 0 ? total : null, known };
}

/** あとから足した栄養素の入力欄の中身。空欄は「分からない」 */
export type AddedInputs = Record<AddedNutrientId, string>;

export function emptyAddedInputs(): AddedInputs {
  return Object.fromEntries(ADDED_NUTRIENT_IDS.map((id) => [id, ''])) as AddedInputs;
}

export function addedInputsFrom(values: AddedNutrients): AddedInputs {
  return Object.fromEntries(ADDED_NUTRIENT_IDS.map((id) => [id, values[id] == null ? '' : String(values[id])])) as AddedInputs;
}

/**
 * 入力欄から送る値を作る。数として読めた欄だけを送る。
 * 直すときは空欄を null で送り、分からないに戻す。送らないとサーバーは前の値を残す
 */
export function addedInputsToBody(inputs: AddedInputs, clearEmpty: boolean): Partial<Record<AddedNutrientId, number | null>> {
  const body: Partial<Record<AddedNutrientId, number | null>> = {};
  for (const id of ADDED_NUTRIENT_IDS) {
    const text = inputs[id].trim();
    const value = text === '' ? NaN : Number(text);
    if (!Number.isNaN(value)) body[id] = value;
    else if (clearEmpty) body[id] = null;
  }
  return body;
}
