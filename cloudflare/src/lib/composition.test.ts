import { describe, it, expect } from 'vitest';
import {
  COMPOSITION_CREATOR, COMPOSITION_NUTRIENTS, compositionFoodId, compositionFoodUpsert, compositionNutrients,
  compositionWordsFor, parseCompositionValue,
} from './composition';
import { NUTRIENTS } from './nutrients';

describe('成分表のセルの値', () => {
  it('数値はそのまま、Excel の誤差は丸める', () => {
    expect(parseCompositionValue('12.7')).toBe(12.7);
    expect(parseCompositionValue('64.900000000000006')).toBe(64.9);
  });

  it('括弧付きの推計値は数値として読む', () => {
    expect(parseCompositionValue('(11.3)')).toBe(11.3);
  });

  it('微量の Tr と、推計で 0 の (0) は 0', () => {
    expect(parseCompositionValue('Tr')).toBe(0);
    expect(parseCompositionValue('(Tr)')).toBe(0);
    expect(parseCompositionValue('(0)')).toBe(0);
  });

  it('未測定の「-」は 0 ではなく分からない', () => {
    expect(parseCompositionValue('-')).toBeNull();
    expect(parseCompositionValue('')).toBeNull();
    expect(parseCompositionValue(undefined)).toBeNull();
  });

  it('注の記号は外し、記号だけなら分からない', () => {
    expect(parseCompositionValue('14.0†')).toBe(14);
    expect(parseCompositionValue('*')).toBeNull();
  });
});

describe('1食品の栄養素', () => {
  // 白米めし 01088 の値
  const rice = { ENERC_KCAL: '156', 'PROT-': '2.5', 'FAT-': '0.3', 'CHOCDF-': '37.1', 'FIB-': '1.5', NACL_EQ: '0', K: '29', VITD: '(0)', FASAT: '0.10' };

  it('定義の列名で、成分表の値を取り出す', () => {
    const v = compositionNutrients(rice);
    expect(v).toMatchObject({ calories: 156, protein: 2.5, fat: 0.3, dietary_fiber: 1.5, salt_equivalent: 0, potassium: 29, vitamin_d: 0, saturated_fat: 0.1 });
  });

  it('糖質は炭水化物から食物繊維を引く', () => {
    expect(compositionNutrients(rice).net_carbs).toBe(35.6);
  });

  it('食物繊維が未測定なら、糖質は炭水化物のまま', () => {
    expect(compositionNutrients({ ...rice, 'FIB-': '-' }).net_carbs).toBe(37.1);
  });

  it('引いて負になれば 0', () => {
    expect(compositionNutrients({ ...rice, 'CHOCDF-': '2.8', 'FIB-': '3.1' }).net_carbs).toBe(0);
  });

  it('未測定の栄養素は分からない', () => {
    expect(compositionNutrients({ ...rice, VITD: '-' }).vitamin_d).toBeNull();
  });

  it('ヨウ素やセレンのように未測定の多い栄養素も、未測定なら 0 にせず分からない', () => {
    const v = compositionNutrients({ ...rice, ID: '-', SE: '1', CR: '-', MO: '30', BIOT: '(0.5)' });
    expect(v).toMatchObject({ iodine: null, selenium: 1, chromium: null, molybdenum: 30, biotin: 0.5 });
  });

  it('成分表の値を持つ栄養素は、定義のすべての栄養素', () => {
    expect(COMPOSITION_NUTRIENTS.map((n) => n.id)).toEqual(NUTRIENTS.map((n) => n.id));
  });
});

describe('脂質が 0 の食品の飽和脂肪酸', () => {
  // ウイスキー 16016 のように、脂肪酸成分表に載らず FASAT の列が無い食品
  const spirit = { ENERC_KCAL: '234', 'PROT-': '0', 'FAT-': '(0)', 'CHOCDF-': '0', 'FIB-': '(0)' };

  it('脂質が 0 で飽和脂肪酸が分からなければ、飽和脂肪酸も 0', () => {
    expect(compositionNutrients(spirit).saturated_fat).toBe(0);
    expect(compositionNutrients({ ...spirit, 'FAT-': '0' }).saturated_fat).toBe(0);
  });

  it('脂質が Tr でも、飽和脂肪酸は 0', () => {
    expect(compositionNutrients({ ...spirit, 'FAT-': 'Tr', FASAT: '-' }).saturated_fat).toBe(0);
  });

  it('脂質が未測定なら、飽和脂肪酸は分からないまま', () => {
    expect(compositionNutrients({ ...spirit, 'FAT-': '-' }).saturated_fat).toBeNull();
  });

  it('脂質が少しでもあれば、飽和脂肪酸は分からないまま', () => {
    expect(compositionNutrients({ ...spirit, 'FAT-': '0.1' }).saturated_fat).toBeNull();
  });

  it('飽和脂肪酸の値があれば、その値を使う', () => {
    expect(compositionNutrients({ ...spirit, 'FAT-': '0', FASAT: '(0.01)' }).saturated_fat).toBe(0.01);
  });

  it('ほかの脂肪酸は 0 にしない', () => {
    expect(compositionNutrients(spirit).n3_fatty_acids).toBeNull();
  });
});

describe('食品検索の言い換え', () => {
  it('普段の言葉を成分表の書き方に寄せ、語に分ける', () => {
    expect(compositionWordsFor('豚ロース')).toEqual(['ぶた', 'ロース']);
    expect(compositionWordsFor('鶏むね肉')).toEqual(['にわとり', 'むね']);
    expect(compositionWordsFor('ご飯')).toEqual(['めし']);
    expect(compositionWordsFor('豚汁')).toEqual(['とん汁']);
  });

  it('言い換える語が無ければ null', () => {
    expect(compositionWordsFor('サーモン')).toBeNull();
  });
});

describe('国の一覧の食品', () => {
  it('id は食品番号から決める。どの環境でも同じ食品は同じ id になる', () => {
    expect(compositionFoodId('01088')).toBe('00000000-0000-4000-8000-000000001088');
  });

  it('100 g あたりで、ブランド名は空、作った人と出典と食品番号を入れる', () => {
    const { sql, binds } = compositionFoodUpsert('01088', 'こめ ［水稲めし］ 精白米 うるち米', { calories: 156 });
    const row = Object.fromEntries(columnsOf(sql).map((column, i) => [column, binds[i]]));
    expect(row).toMatchObject({
      id: '00000000-0000-4000-8000-000000001088', brand_name: '', product_name: 'こめ ［水稲めし］ 精白米 うるち米',
      portion_size: 100, portion_unit: 'g', unique_key: '|こめ ［水稲めし］ 精白米 うるち米|g',
      created_by: COMPOSITION_CREATOR, nutrient_source: 'composition_table', nutrient_source_ref: '01088', calories: 156,
    });
  });

  it('未測定の基本5項目は 0 にし、それ以外の栄養素は分からないのまま', () => {
    const { sql, binds } = compositionFoodUpsert('16001', '＜アルコール飲料類＞ 清酒 普通酒', {
      calories: 107, protein: 0.4, fat: 0, net_carbs: 4.9, dietary_fiber: null, potassium: 5, iodine: null,
    });
    const row = Object.fromEntries(columnsOf(sql).map((column, i) => [column, binds[i]]));
    expect(row).toMatchObject({ dietary_fiber: 0, potassium: 5, iodine: null, vitamin_d: null });
  });
});

/** INSERT 文の列名の並び */
function columnsOf(sql: string): string[] {
  return /\(([^)]*)\)\s*VALUES/.exec(sql)![1].split(',').map((c) => c.trim());
}
