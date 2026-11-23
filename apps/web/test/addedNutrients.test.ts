import { describe, it, expect } from 'bun:test';
import { correlationSeries, type DailyStat } from '../src/lib/correlation';
import { ADDED_NUTRIENT_IDS, addedInputsFrom, addedInputsToBody, emptyAddedInputs, sumKnown } from '../src/lib/nutrients';

// あとから足した栄養素は、値の分からない品や日がある。0 として扱わず、分かっているものだけで出す

function stat(date: string, over: Partial<DailyStat> = {}): DailyStat {
  return {
    date, calories: 500, protein: 20, fat: 10, netCarbs: 60, dietaryFiber: 5,
    weightKg: null, bodyFatPercent: null, muscleMassKg: null, muscleScore: null,
    visceralFatLevel: null, basalMetabolismKcal: null, metabolicAge: null,
    boneMassKg: null, bodyWaterPercent: null, ...over,
  };
}

describe('分かっている値だけを足す', () => {
  it('分からない値を飛ばして足す', () => {
    expect(sumKnown([2.1, undefined, 1.3, null])).toBeCloseTo(3.4);
  });

  it('どれも分からなければ合計も分からない', () => {
    expect(sumKnown([undefined, null])).toBeNull();
  });
});

describe('食塩の推移', () => {
  // 2026-11-02 は月曜
  const items = [stat('2026-11-02', { saltEquivalent: 6 }), stat('2026-11-03'), stat('2026-11-04', { saltEquivalent: 8 })];

  it('日ごとでは、値の分からない日を 0 にせず null にして線を切る', () => {
    const series = correlationSeries(items, '2026-11-02', '2026-11-05', 'day', false, 'saltEquivalent', 'weightKg');

    expect(series.map((p) => p.nutrient)).toEqual([6, null, 8, null]);
  });

  it('週の平均は、値の分かっている日だけで割る', () => {
    const series = correlationSeries(items, '2026-11-02', '2026-11-08', 'week', true, 'saltEquivalent', 'weightKg');

    expect(series).toEqual([{ date: '2026-11-02', nutrient: 7, body: null }]);
  });

  it('値の分かる日が無い週は null にする', () => {
    const series = correlationSeries([stat('2026-11-02')], '2026-11-02', '2026-11-08', 'week', false, 'saltEquivalent', 'weightKg');

    expect(series[0].nutrient).toBeNull();
  });

  it('カロリーは今までどおり記録の無い日を 0 にし、暦日数で割る', () => {
    const series = correlationSeries([stat('2026-11-02')], '2026-11-02', '2026-11-08', 'week', true, 'calories', 'weightKg');

    expect(series[0].nutrient).toBeCloseTo(500 / 7);
  });
});

describe('食品の入力欄', () => {
  it('作るときは、数として読めた欄だけを送る', () => {
    expect(addedInputsToBody({ ...emptyAddedInputs(), saltEquivalent: '2.5', potassium: 'abc' }, false)).toEqual({ saltEquivalent: 2.5 });
  });

  it('直すときは、空欄を null で送って分からないに戻す', () => {
    const body = addedInputsToBody({ ...emptyAddedInputs(), saltEquivalent: '0', saturatedFat: ' ' }, true);
    expect(body.saltEquivalent).toBe(0);
    expect(body.saturatedFat).toBeNull();
    expect(Object.keys(body)).toEqual([...ADDED_NUTRIENT_IDS]);
  });

  it('食品の値から欄を埋め、分からない値は空欄にする', () => {
    expect(addedInputsFrom({ saltEquivalent: 1.2, potassium: 0 })).toEqual({ ...emptyAddedInputs(), saltEquivalent: '1.2', potassium: '0' });
  });
});
