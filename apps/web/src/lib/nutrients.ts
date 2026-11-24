// 栄養素の一覧。Worker と同じ定義を使い、web では5項目ごとの手書きをしない。
import {
  NUTRIENTS, CORE_NUTRIENT_IDS, ADDED_NUTRIENTS, ADDED_NUTRIENT_IDS, LABEL_NUTRIENTS,
  type CoreNutrientId, type CoreNutrients, type AddedNutrientId, type AddedNutrients, type NutrientDefinition,
} from '../../../../cloudflare/src/lib/nutrients';

export {
  NUTRIENTS, CORE_NUTRIENT_IDS, ADDED_NUTRIENTS, ADDED_NUTRIENT_IDS, LABEL_NUTRIENTS,
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
 * 0 として足すと少なく見えてしまう。どの品も分からなければ null
 */
export function sumKnown(values: readonly (number | null | undefined)[]): number | null {
  const known = values.filter((v): v is number => v != null);
  return known.length > 0 ? known.reduce((a, b) => a + b, 0) : null;
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

/** 引き算で出る 0.19999… のような誤差を丸める */
function roundSmall(value: number): number {
  return Math.round(value * 10_000) / 10_000;
}

type CarbParts = { netCarbs: number; dietaryFiber: number };

/**
 * 入力欄に出す炭水化物。食品表示の義務は炭水化物なので、入力欄はラベルと同じ並びにする。
 * 保存の形は糖質と食物繊維のまま。公開中の古い版のアプリが食物繊維を必須の数値として読むため
 */
export function carbohydrateOf(v: CarbParts): number {
  return roundSmall(v.netCarbs + v.dietaryFiber);
}

/** 炭水化物を入れたら、食物繊維を引いた値を糖質にする */
export function withCarbohydrate<T extends CarbParts>(v: T, carbohydrate: number): T {
  return { ...v, netCarbs: roundSmall(carbohydrate - v.dietaryFiber) };
}

/** 食物繊維は炭水化物の内訳なので、炭水化物を保ったまま糖質を減らす */
export function withFiber<T extends CarbParts>(v: T, fiber: number): T {
  return { ...v, dietaryFiber: fiber, netCarbs: roundSmall(carbohydrateOf(v) - fiber) };
}
