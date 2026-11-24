// 日本食品標準成分表の値の読み方と、国の一覧の食品を food_masters に入れる形、食品検索の言い換え。
// 取り込みのスクリプト scripts/composition/build-sql.ts と、Worker の両方で使う。
import { NUTRIENTS, type NutrientDefinition } from './nutrients';

/** 成分表の値がある栄養素。定義ファイルの composition から決める */
export const COMPOSITION_NUTRIENTS: readonly (NutrientDefinition & {
  composition: NonNullable<NutrientDefinition['composition']>;
})[] = NUTRIENTS.filter((n): n is NutrientDefinition & { composition: NonNullable<NutrientDefinition['composition']> } =>
  n.composition !== undefined);

/**
 * 成分表のセルの値を数にする。
 * - 数値と、括弧付きの推計値はそのまま
 * - Tr と (Tr) は最小記載量に達しないという意味で 0
 * - (0) は推計で 0
 * - 「-」は未測定。含まれていないという意味ではないので null
 * - 14.0† のような注の記号は外す。記号だけのセルは null
 * Excel から読むと 64.900000000000006 のような誤差が付くので、小数6桁で丸める
 */
export function parseCompositionValue(raw: string | undefined): number | null {
  if (raw === undefined) return null;
  const text = raw.trim().replace(/^\((.*)\)$/, '$1').replace(/[†‡*＊]/g, '').trim();
  if (text === '' || text === '-') return null;
  if (text === 'Tr') return 0;
  const value = Number(text);
  if (Number.isNaN(value)) return null;
  return Math.round(value * 1e6) / 1e6;
}

const columnOf = (id: string) => {
  const n = COMPOSITION_NUTRIENTS.find((d) => d.id === id);
  if (!n) throw new Error(`定義に ${id} が無い`);
  return n.column;
};
const FAT_COLUMN = columnOf('fat');
const SATURATED_FAT_COLUMN = columnOf('saturatedFat');

/**
 * 定義の composition に従って、1食品の栄養素の値を取り出す。100 g あたり。
 * minus がある栄養素は引き算で出す。糖質は炭水化物から食物繊維を引く。
 * 成分表の Q&A 7-3 のとおりで、負になれば 0、引く値が未測定なら引かない。
 *
 * 脂質が 0 なら、飽和脂肪酸は分からなくても 0 にする。飽和脂肪酸は脂質の一部なので、脂質より多くならない。
 * 脂肪酸成分表に載らない酒などが、脂質 0 のまま飽和脂肪酸だけ分からないと、スコアの条件の
 * 「値の分かる品が8割」を満たせなくなる。食品マスタの値ではなくここで決めるのは、
 * 食品マスタの脂質は 0 と分からないを区別できないため
 */
export function compositionNutrients(cells: Record<string, string | undefined>): Record<string, number | null> {
  const values: Record<string, number | null> = {};
  for (const n of COMPOSITION_NUTRIENTS) {
    const base = parseCompositionValue(cells[n.composition.tag]);
    if (base === null || n.composition.minus === undefined) {
      values[n.column] = base;
      continue;
    }
    const minus = parseCompositionValue(cells[n.composition.minus]) ?? 0;
    values[n.column] = Math.max(0, Math.round((base - minus) * 1e6) / 1e6);
  }
  if (values[FAT_COLUMN] === 0 && values[SATURATED_FAT_COLUMN] === null) values[SATURATED_FAT_COLUMN] = 0;
  return values;
}

/** 国の一覧の食品を作った人。利用者の id と重ならない。編集と削除は管理者だけになる */
export const COMPOSITION_CREATOR = 'composition';

/**
 * 国の一覧の食品の id。食品番号から決める。
 * 同じ食品はどの環境でも同じ id になり、版を入れ替えるときは同じ行を上書きする。
 * 0008 の printf('00000000-0000-4000-8000-%012d', ...) と同じ形にする
 */
export function compositionFoodId(foodNumber: string): string {
  return `00000000-0000-4000-8000-${foodNumber.padStart(12, '0')}`;
}

/**
 * 国の一覧の1食品を food_masters に入れ、あれば値と名前を上書きする文。100 g あたり。
 * ブランド名は空にし、名前は一覧のまま。基本5項目は food_masters で NULL を持てないので、未測定は 0 にする
 */
export function compositionFoodUpsert(
  foodNumber: string, name: string, values: Record<string, number | null>,
): { sql: string; binds: (string | number | null)[] } {
  const nutrientColumns = COMPOSITION_NUTRIENTS.map((n) => n.column);
  const row: Record<string, string | number | null> = {
    id: compositionFoodId(foodNumber),
    brand_name: '',
    product_name: name,
    ...Object.fromEntries(COMPOSITION_NUTRIENTS.map((n) => [n.column, values[n.column] ?? (n.core ? 0 : null)])),
    portion_size: 100,
    portion_unit: 'g',
    unique_key: `|${name}|g`,
    created_by: COMPOSITION_CREATOR,
    nutrient_source: 'composition_table',
    nutrient_source_ref: foodNumber,
  };
  const columns = Object.keys(row);
  const updated = ['product_name', 'unique_key', ...nutrientColumns];
  return {
    sql: `INSERT INTO food_masters (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})
 ON CONFLICT(id) DO UPDATE SET ${updated.map((c) => `${c} = excluded.${c}`).join(', ')}`,
    binds: Object.values(row),
  };
}

/**
 * 普段の言葉を成分表の書き方に寄せる。成分表は「ぶた」「にわとり」「めし」のように書くので、
 * 「豚ロース」「鶏むね肉」「ご飯」のままでは国の一覧の食品が見つからない。
 * 長い語から順に置き換えるので、「鶏肉」は「鶏」より先に置く
 */
const SYNONYMS: readonly [string, string][] = [
  ['鶏むね肉', 'にわとり むね'], ['鶏もも肉', 'にわとり もも'], ['むね肉', 'むね'], ['もも肉', 'もも'],
  ['豚汁', 'とん汁'], ['豚肉', 'ぶた'], ['牛肉', 'うし'], ['鶏肉', 'にわとり'], ['鳥肉', 'にわとり'],
  ['豚', 'ぶた'], ['牛', 'うし'], ['鶏', 'にわとり'],
  ['ご飯', 'めし'], ['ごはん', 'めし'], ['ライス', 'めし'], ['白米', '精白米'],
  ['たまご', '鶏卵'], ['玉子', '鶏卵'], ['卵', '鶏卵'],
  ['鮭', 'さけ'], ['鯖', 'さば'], ['鮪', 'まぐろ'], ['鰯', 'いわし'], ['鯵', 'あじ'],
  ['玉ねぎ', 'たまねぎ'], ['玉葱', 'たまねぎ'], ['人参', 'にんじん'], ['じゃが芋', 'じゃがいも'],
  ['大根', 'だいこん'], ['胡瓜', 'きゅうり'], ['茄子', 'なす'], ['白菜', 'はくさい'], ['南瓜', 'かぼちゃ'],
  ['林檎', 'りんご'], ['苺', 'いちご'], ['蜜柑', 'みかん'],
  ['蕎麦', 'そば'], ['中華麺', '中華めん'], ['ラーメン', '中華めん'], ['パスタ', 'スパゲッティ'],
  ['味噌', 'みそ'], ['醤油', 'しょうゆ'],
].sort((a, b) => b[0].length - a[0].length) as [string, string][];

/**
 * 検索語1つを成分表の書き方に寄せた語の並び。言い換える語が無ければ null。
 * 食品検索は、元の語で見つかる食品に加えて、この語がすべて名前に含まれる食品も返す
 */
export function compositionWordsFor(word: string): string[] | null {
  let text = word;
  for (const [from, to] of SYNONYMS) text = text.split(from).join(` ${to} `);
  if (text === word) return null;
  return text.split(/[\s　]+/).filter(Boolean);
}
