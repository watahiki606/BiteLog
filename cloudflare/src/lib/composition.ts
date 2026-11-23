// 日本食品標準成分表の値の読み方と、成分表の食品を探すときの言葉の揃え方。
// 取り込みのスクリプト scripts/composition/build-sql.ts と、Worker の検索の両方で使う。
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

/**
 * 定義の composition に従って、1食品の栄養素の値を取り出す。100 g あたり。
 * minus がある栄養素は引き算で出す。糖質は炭水化物から食物繊維を引く。
 * 成分表の Q&A 7-3 のとおりで、負になれば 0、引く値が未測定なら引かない
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
  return values;
}

const BRACKETS = /[＜＞<>（）()［］[\]「」【】・,，、。.\s　]/g;

/** 全角の英数字を半角に、カタカナをひらがなにし、括弧と空白を外して小文字にする */
export function normalizeForSearch(text: string): string {
  return text
    .normalize('NFKC')
    .replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60))
    .replace(BRACKETS, '')
    .toLowerCase();
}

/**
 * 普段の言葉を成分表の書き方に寄せる。成分表は「ぶた」「にわとり」「めし」のように書くので、
 * 「豚ロース」「鶏むね肉」「ご飯」のままでは見つからない。
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
];

/** 検索語を、成分表の search_text と比べられる語の並びにする */
export function compositionSearchWords(query: string): string[] {
  let text = query;
  for (const [from, to] of [...SYNONYMS].sort((a, b) => b[0].length - a[0].length)) {
    text = text.split(from).join(` ${to} `);
  }
  return text.split(/[\s　]+/).map(normalizeForSearch).filter(Boolean);
}

/** 成分表の食品の検索用の文字。食品名と、備考にある別名をまとめる */
export function compositionSearchText(name: string, remarks: string): string {
  const aliases = (/別名[:：]\s*([^\s　]+)/.exec(remarks)?.[1] ?? '').split(/[、,，]/);
  return [name, ...aliases].map(normalizeForSearch).filter(Boolean).join(' ');
}
