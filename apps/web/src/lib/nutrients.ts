// 栄養素の一覧。Worker と同じ定義を使い、web では5項目ごとの手書きをしない。
import {
  NUTRIENTS, CORE_NUTRIENT_IDS, type CoreNutrientId, type CoreNutrients, type NutrientDefinition,
} from '../../../../cloudflare/src/lib/nutrients';

export { NUTRIENTS, CORE_NUTRIENT_IDS, type CoreNutrientId, type CoreNutrients, type NutrientDefinition };

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
