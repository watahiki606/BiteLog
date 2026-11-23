import { describe, it, expect } from 'vitest';
import {
  COMPOSITION_NUTRIENTS, compositionNutrients, compositionSearchText, compositionSearchWords, normalizeForSearch,
  parseCompositionValue,
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

describe('検索の言葉', () => {
  it('カタカナはひらがなに、括弧と空白は外す', () => {
    expect(normalizeForSearch('＜畜肉類＞　ぶた　［中型種肉］　ロース')).toBe('畜肉類ぶた中型種肉ろーす');
  });

  it('普段の言葉を成分表の書き方に寄せ、語に分ける', () => {
    expect(compositionSearchWords('豚ロース')).toEqual(['ぶた', 'ろーす']);
    expect(compositionSearchWords('鶏むね肉 焼き')).toEqual(['にわとり', 'むね', '焼き']);
    expect(compositionSearchWords('ご飯')).toEqual(['めし']);
    expect(compositionSearchWords('豚汁')).toEqual(['とん汁']);
  });

  it('備考の別名も検索の対象にする', () => {
    expect(compositionSearchText('えんばく　オートミール', '別名： オート、オーツ 米国成分表から推計')).toBe('えんばくおーとみーる おーと おーつ');
  });
});
