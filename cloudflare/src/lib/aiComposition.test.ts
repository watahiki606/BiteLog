import { describe, it, expect } from 'vitest';
import { parseComponents, sumComponents } from './aiComposition';

describe('AI が答えた食材の形', () => {
  it('食品番号と重さの組を受け付ける', () => {
    expect(parseComponents([{ foodNumber: '01088', grams: 250 }, { foodNumber: '18030', grams: '200' }]))
      .toEqual([{ foodNumber: '01088', grams: 250 }, { foodNumber: '18030', grams: 200 }]);
  });

  it('空の配列は、食材が無いという意味で受け付ける', () => {
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
