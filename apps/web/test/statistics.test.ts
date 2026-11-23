import { describe, it, expect } from 'bun:test';
import {
  dailyTotals, fillDays, bucketed, periodTotal, dailyAverage, mealTypeTotals, ZERO_VALUES,
  type DaySummary,
} from '../src/lib/statistics';

// 5つの栄養素にすべて別の値を入れ、栄養素の取り違えにも気づけるようにする
const CURRY = { calories: 650, protein: 15, fat: 20, netCarbs: 90, dietaryFiber: 3 };

function row(logDate: string, mealType: string, scale = 1): DaySummary {
  return {
    logDate, mealType,
    calories: CURRY.calories * scale, protein: CURRY.protein * scale, fat: CURRY.fat * scale,
    netCarbs: CURRY.netCarbs * scale, dietaryFiber: CURRY.dietaryFiber * scale,
  };
}

describe('統計の集計', () => {
  it('同じ日の食事を栄養素ごとに足す', () => {
    const daily = dailyTotals([row('2026-11-02', 'Lunch'), row('2026-11-02', 'Dinner', 2)]);

    expect(daily).toEqual([{ date: '2026-11-02', values: { calories: 1950, protein: 45, fat: 60, netCarbs: 270, dietaryFiber: 9 } }]);
  });

  it('記録の無い日は 0 で埋める', () => {
    const filled = fillDays(dailyTotals([row('2026-11-02', 'Lunch')]), '2026-11-01', '2026-11-02');

    expect(filled[0]).toEqual({ date: '2026-11-01', values: ZERO_VALUES });
    expect(ZERO_VALUES).toEqual({ calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0 });
  });

  it('週の平均は、記録の無い日も含めた7日で割る', () => {
    // 2026-11-02 は月曜
    const weeks = bucketed(dailyTotals([row('2026-11-02', 'Lunch', 7)]), 'week', true);

    expect(weeks).toEqual([{ date: '2026-11-02', values: CURRY }]);
  });

  it('期間の合計と1日平均', () => {
    const items = [row('2026-11-01', 'Lunch'), row('2026-11-02', 'Lunch')];

    expect(periodTotal(items)).toEqual({ calories: 1300, protein: 30, fat: 40, netCarbs: 180, dietaryFiber: 6 });
    expect(dailyAverage(items, 2)).toEqual(CURRY);
    expect(dailyAverage(items, 0)).toEqual(ZERO_VALUES);
  });

  it('食事の種類ごとに足す', () => {
    const totals = mealTypeTotals([row('2026-11-01', 'Lunch'), row('2026-11-02', 'Lunch'), row('2026-11-02', 'Dinner')]);

    expect(totals).toEqual({
      Lunch: { calories: 1300, protein: 30, fat: 40, netCarbs: 180, dietaryFiber: 6 },
      Dinner: CURRY,
    });
  });
});
