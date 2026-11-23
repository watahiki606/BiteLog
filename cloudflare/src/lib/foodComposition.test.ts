import { describe, it, expect } from 'vitest';
import {
  parseComponents, parseNutrientSources, planCompositionUpdate, serializeNutrientSources, sumComponents, type FoodState,
} from './foodComposition';

describe('送られたひも付けの形', () => {
  it('食品番号と重さの組を受け付ける', () => {
    expect(parseComponents([{ foodNumber: '01088', grams: 250 }, { foodNumber: '18030', grams: '200' }]))
      .toEqual([{ foodNumber: '01088', grams: 250 }, { foodNumber: '18030', grams: 200 }]);
  });

  it('空の配列はひも付けを外すという意味で受け付ける', () => {
    expect(parseComponents([])).toEqual([]);
  });

  it('食品番号が5桁でない、重さが 0 以下、配列でないものは受け付けない', () => {
    expect(parseComponents([{ foodNumber: '1088', grams: 250 }])).toBeNull();
    expect(parseComponents([{ foodNumber: '01088', grams: 0 }])).toBeNull();
    expect(parseComponents([{ foodNumber: '01088' }])).toBeNull();
    expect(parseComponents({ foodNumber: '01088', grams: 1 })).toBeNull();
  });
});

describe('食材を重さで足す', () => {
  // 親子丼 1人前 = めし 250 g + 親子丼の具 200 g
  const rice = { calories: 156, potassium: 29, vitamin_d: 0, salt_equivalent: 0 };
  const topping = { calories: 101, potassium: 120, vitamin_d: 0.7, salt_equivalent: 1.0 };

  it('100 g あたりの値に重さを掛けて足す', () => {
    const totals = sumComponents([{ grams: 250, per100g: rice }, { grams: 200, per100g: topping }]);
    expect(totals).toMatchObject({ calories: 592, potassium: 312.5, vitamin_d: 1.4, salt_equivalent: 2 });
  });

  it('1つでも値の分からない食材があれば、その栄養素は分からない', () => {
    const totals = sumComponents([{ grams: 250, per100g: rice }, { grams: 60, per100g: { calories: 541, vitamin_d: null } }]);
    expect(totals.vitamin_d).toBeNull();
    expect(totals.calories).toBe(714.6);
  });

  it('成分表に無い食材は、すべての栄養素を分からないにする', () => {
    expect(sumComponents([{ grams: 250, per100g: rice }, { grams: 10, per100g: null }]).calories).toBeNull();
  });
});

describe('どの栄養素に書き込むか', () => {
  const label: FoodState = {
    values: { calories: 336, protein: 3.2, salt_equivalent: 0.6, potassium: null, calcium: 25, vitamin_d: null },
    nutrientSource: 'label',
    nutrientSources: {},
  };
  const totals = { calories: 324.6, protein: 2.8, salt_equivalent: 0.6, potassium: 720, calcium: 10.2, vitamin_d: null };

  it('ラベルの食品は、分からない栄養素だけを補い、印を付ける', () => {
    const plan = planCompositionUpdate(label, totals);
    expect(plan.values).toEqual({ potassium: 720, vitamin_d: null, saturated_fat: null, magnesium: null, iron: null, vitamin_a: null, vitamin_c: null });
    expect(plan.nutrientSources).toEqual({ potassium: 'composition_table' });
  });

  it('ラベルの値も最初の5項目も書き換えない', () => {
    const plan = planCompositionUpdate(label, totals);
    expect(plan.values).not.toHaveProperty('calories');
    expect(plan.values).not.toHaveProperty('calcium');
    expect(plan.values).not.toHaveProperty('salt_equivalent');
  });

  it('前に補った栄養素は計算し直し、ひも付けが無くなれば分からないに戻す', () => {
    const supplemented: FoodState = { ...label, values: { ...label.values, potassium: 700 }, nutrientSources: { potassium: 'composition_table' } };
    expect(planCompositionUpdate(supplemented, totals).values.potassium).toBe(720);

    const unlinked = planCompositionUpdate(supplemented, null);
    expect(unlinked.values.potassium).toBeNull();
    expect(unlinked.nutrientSources).toEqual({});
  });

  it('値をすべて成分表から取った食品は、最初の5項目も含めて全部を書く。5項目の不明は 0', () => {
    const table: FoodState = { values: {}, nutrientSource: 'composition_table', nutrientSources: {} };
    const plan = planCompositionUpdate(table, { ...totals, fat: null });
    expect(plan.values).toMatchObject({ calories: 324.6, fat: 0, potassium: 720, calcium: 10.2, vitamin_d: null });
    expect(plan.nutrientSources).toEqual({});
  });

  it('成分表から取った食品のひも付けが外れても、値は残す', () => {
    const table: FoodState = { values: { calories: 300 }, nutrientSource: 'composition_table', nutrientSources: {} };
    expect(planCompositionUpdate(table, null).values).toEqual({});
  });
});

describe('栄養素ごとの出典の列', () => {
  it('読み書きできる。空なら NULL', () => {
    expect(parseNutrientSources('{"potassium":"composition_table"}')).toEqual({ potassium: 'composition_table' });
    expect(parseNutrientSources(null)).toEqual({});
    expect(parseNutrientSources('壊れた')).toEqual({});
    expect(serializeNutrientSources({})).toBeNull();
    expect(serializeNutrientSources({ vitaminC: 'composition_table', calcium: 'composition_table' }))
      .toBe('{"calcium":"composition_table","vitaminC":"composition_table"}');
  });
});
