import { describe, it, expect } from 'bun:test';
import {
  toDay, buildWeeks, windowPairs, regress, estimate, relationMatrix, windowProfile,
  nextDayEffects, intakeRelations, scatterPoints, WINDOWS,
  type Week, type Pair, type SourceKey,
} from '../src/lib/relations';
import type { DailyStat, BodyMetricKey } from '../src/lib/correlation';

function stat(over: Partial<DailyStat>): DailyStat {
  return {
    date: '2025-01-06', calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0,
    weightKg: null, bodyFatPercent: null, muscleMassKg: null, muscleScore: null,
    visceralFatLevel: null, basalMetabolismKcal: null, metabolicAge: null,
    boneMassKg: null, bodyWaterPercent: null, ...over,
  };
}

/** 2025-01-06（月）から n 日後の "yyyy-MM-dd"。 */
function day(n: number): string {
  const d = new Date(2025, 0, 6 + n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

const NO_BODY: Record<BodyMetricKey, number | null> = {
  weightKg: null, bodyFatPercent: null, muscleMassKg: null, muscleScore: null,
  visceralFatLevel: null, basalMetabolismKcal: null, metabolicAge: null,
  boneMassKg: null, bodyWaterPercent: null,
};

function intake(p: number, f: number, c: number, o: number): Record<SourceKey, number> {
  return { kcal: p + f + c + o, protein: p, fat: f, carbs: c, other: o };
}

function week(i: number, inTake: Record<SourceKey, number> | null, weight: number | null): Week {
  return { start: day(7 * i), intake: inTake, body: { ...NO_BODY, weightKg: weight } };
}

function pair(inTake: Record<SourceKey, number>, dWeight: number): Pair {
  return { start: day(0), intake: inTake, delta: { ...NO_BODY, weightKg: dWeight } };
}

describe('toDay: 日次をカロリー源に分ける', () => {
  it('P×4・F×9・糖質×4＋食物繊維×2 を kcal にし、残りを「その他」にする', () => {
    const d = toDay(stat({ calories: 2000, protein: 100, fat: 50, netCarbs: 200, dietaryFiber: 20 }));
    expect(d.protein).toBe(400);
    expect(d.fat).toBe(450);
    expect(d.carbs).toBe(840);
    expect(d.other).toBe(310);
    expect(d.logged).toBe(true);
  });

  it('PFC 換算が記録カロリーを少し超えても「その他」はマイナスにしない', () => {
    expect(toDay(stat({ calories: 1000, protein: 260 })).other).toBe(0);
  });

  it('800kcal 未満の日は記録漏れとして使わない', () => {
    expect(toDay(stat({ calories: 799, protein: 50 })).logged).toBe(false);
  });

  it('PFC 換算が記録カロリーの1.3倍を超える日は入力ミスとして使わない', () => {
    expect(toDay(stat({ calories: 1000, fat: 145 })).logged).toBe(false);
  });

  it('体組成はそのまま持つ', () => {
    expect(toDay(stat({ weightKg: 60.5 })).body.weightKg).toBe(60.5);
  });
});

describe('buildWeeks: 月曜始まりの週にまとめる', () => {
  const logged = (n: number, protein: number, weightKg: number | null = null) =>
    stat({ date: day(n), calories: 2000, protein, weightKg });

  it('摂取は記録のある日の平均', () => {
    const weeks = buildWeeks([0, 1, 2, 3].map((n) => logged(n, 100 + n * 10)));
    expect(weeks).toHaveLength(1);
    expect(weeks[0].start).toBe(day(0));
    expect(weeks[0].intake!.protein).toBe(4 * 115);
  });

  it('記録が4日未満の週は摂取を null にする', () => {
    expect(buildWeeks([0, 1, 2].map((n) => logged(n, 100)))[0].intake).toBeNull();
  });

  it('体組成は値のある日の平均。2日未満なら null', () => {
    const weeks = buildWeeks([logged(0, 100, 60), logged(1, 100, 62), logged(7, 100, 70)]);
    expect(weeks[0].body.weightKg).toBe(61);
    expect(weeks[1].body.weightKg).toBeNull();
  });

  it('データの無い週も詰めずに空の週として並べる', () => {
    const weeks = buildWeeks([logged(0, 100), logged(21, 100)]);
    expect(weeks.map((w) => w.start)).toEqual([day(0), day(7), day(14), day(21)]);
  });
});

describe('windowPairs: W週の摂取 × 直前W週から直後W週への変化', () => {
  const inTake = (k: number) => intake(k, 0, 0, 0);

  it('W=1 は、その週の摂取と前の週から次の週への変化', () => {
    const weeks = [week(0, inTake(1), 60), week(1, inTake(2), 61), week(2, inTake(3), 63)];
    const pairs = windowPairs(weeks, 1);
    expect(pairs).toHaveLength(1);
    expect(pairs[0].intake.protein).toBe(2);
    expect(pairs[0].delta.weightKg).toBe(3);
  });

  it('W=2 は2週ずつ平均する', () => {
    const w = [60, 62, 0, 0, 70, 72];
    const weeks = w.map((v, i) => week(i, inTake(i), v));
    const pairs = windowPairs(weeks, 2);
    expect(pairs[0].intake.protein).toBe(2.5);
    expect(pairs[0].delta.weightKg).toBe(10);
  });

  it('摂取が欠けている期間は組にしない', () => {
    const weeks = [week(0, inTake(1), 60), week(1, null, 61), week(2, inTake(3), 63)];
    expect(windowPairs(weeks, 1)).toHaveLength(0);
  });
});

describe('regress: 切片付きの最小二乗と Newey-West の標準誤差', () => {
  const x1 = [1, 2, 3, 4, 5, 6, 7, 8];
  const x2 = [2, 1, 4, 3, 6, 5, 8, 7];
  const y = [3.1, 4.9, 7.2, 8.8, 11.1, 13.0, 15.2, 16.8];

  it('係数は通常の最小二乗と同じ', () => {
    const r = regress(y, [x1, x2], 0)!;
    expect(r.coef[0]).toBeCloseTo(1.86375, 8);
    expect(r.coef[1]).toBeCloseTo(0.13875, 8);
  });

  it('lag 0 の標準誤差', () => {
    const r = regress(y, [x1, x2], 0)!;
    expect(r.se[0]).toBeCloseTo(0.0262024868, 8);
    expect(r.se[1]).toBeCloseTo(0.0227556655, 8);
  });

  it('lag 2 では隣り合う残差の相関も入れる', () => {
    const r = regress(y, [x1, x2], 2)!;
    expect(r.se[0]).toBeCloseTo(0.0219400224, 8);
    expect(r.se[1]).toBeCloseTo(0.0169668795, 8);
  });

  it('説明変数より行が少なければ null', () => {
    expect(regress([1, 2, 3], [[1, 2, 3], [3, 1, 2]], 0)).toBeNull();
  });

  it('説明変数が一定なら null', () => {
    expect(regress([1, 2, 3, 4, 5], [[1, 1, 1, 1, 1]], 0)).toBeNull();
  });
});

describe('estimate: 1日 +100kcal あたりの係数', () => {
  // タンパク質と脂質が一緒に増減し、体重の変化は脂質だけで決まるデータ。
  const pairs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => {
    const p = 300 + i * 10;
    const f = 400 + i * 20 + (i % 3) * 15;
    return pair(intake(p, f, 400, 0), 0.002 * f);
  });

  it('単独では、一緒に増える脂質の分までタンパク質に乗る', () => {
    expect(estimate(pairs, 'protein', 'weightKg', 'single', 0)!.coef).toBeGreaterThan(0.3);
  });

  it('他の栄養素を固定すると、タンパク質は0・脂質は0.2になる', () => {
    expect(estimate(pairs, 'protein', 'weightKg', 'adjusted', 0)!.coef).toBeCloseTo(0, 8);
    expect(estimate(pairs, 'fat', 'weightKg', 'adjusted', 0)!.coef).toBeCloseTo(0.2, 8);
  });

  it('合計kcal は他の栄養素の合計なので、固定するときも単独で回帰する', () => {
    const single = estimate(pairs, 'kcal', 'weightKg', 'single', 0)!;
    expect(estimate(pairs, 'kcal', 'weightKg', 'adjusted', 0)!.coef).toBeCloseTo(single.coef, 10);
  });

  it('信頼区間と組の数を返す', () => {
    const e = estimate(pairs, 'fat', 'weightKg', 'single', 0)!;
    expect(e.n).toBe(10);
    expect(e.lo).toBeLessThanOrEqual(e.coef);
    expect(e.hi).toBeGreaterThanOrEqual(e.coef);
  });

  it('体組成の無い指標は null', () => {
    expect(estimate(pairs, 'fat', 'muscleMassKg', 'single', 0)).toBeNull();
  });
});

/** 52週分。体重は「その週のタンパク質 kcal × 0.001」だけ翌週に増える。 */
function syntheticWeeks(): Week[] {
  const weeks: Week[] = [];
  let w = 60;
  for (let i = 0; i < 52; i++) {
    const p = 300 + ((i * 37) % 11) * 10;
    const f = 400 + ((i * 53) % 7) * 20;
    weeks.push(week(i, intake(p, f, 400, 100), w));
    w += 0.001 * (p - 350);
  }
  return weeks;
}

describe('relationMatrix / windowProfile', () => {
  it('全てのカロリー源 × 体組成指標のマスを返す', () => {
    const cells = relationMatrix(syntheticWeeks(), 1, 'adjusted');
    expect(cells).toHaveLength(5 * 9);
    const pw = cells.find((c) => c.source === 'protein' && c.body === 'weightKg')!;
    expect(pw.estimate!.coef).toBeGreaterThan(0);
    expect(cells.find((c) => c.body === 'muscleMassKg')!.estimate).toBeNull();
  });

  it('期間ごとの係数を、期間の短い順に返す', () => {
    const prof = windowProfile(syntheticWeeks(), 'protein', 'weightKg', 'adjusted');
    expect(prof.map((p) => p.weeks)).toEqual([...WINDOWS]);
  });
});

describe('nextDayEffects: 翌朝の変化', () => {
  // 体重は、その日の炭水化物 kcal × 0.001 だけ翌朝に増える。
  const items: DailyStat[] = [];
  let w = 60;
  for (let i = 0; i < 40; i++) {
    const c = 400 + ((i * 7) % 5) * 50;
    const p = 300 + ((i * 3) % 4) * 25;
    items.push(stat({ date: day(i), calories: p + 500 + c, protein: p / 4, fat: 500 / 9, netCarbs: c / 4, weightKg: w }));
    w += 0.001 * c;
  }

  it('当日の摂取がそのまま翌朝に出て、前日・前々日の分は0', () => {
    const eff = nextDayEffects(items, 'carbs', 'weightKg', 'adjusted');
    expect(eff.map((e) => e.lag)).toEqual([0, 1, 2]);
    expect(eff[0].estimate!.coef).toBeCloseTo(0.1, 6);
    expect(eff[1].estimate!.coef).toBeCloseTo(0, 6);
  });
});

describe('intakeRelations: ある源が増えた時期に他の源がどう動くか', () => {
  // 炭水化物は脂質が増えた分だけ減る。
  const weeks = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) => {
    const f = 400 + ((i * 5) % 7) * 20;
    return week(i, intake(300, f, 900 - f, 100), null);
  });

  it('脂質 +100kcal あたり、炭水化物は −100kcal', () => {
    const rel = intakeRelations(weeks, 1);
    const fc = rel.find((r) => r.x === 'fat' && r.y === 'carbs')!;
    expect(fc.estimate!.coef).toBeCloseTo(-100, 6);
  });

  it('「残りの合計」は合計kcal から自分を引いたもの', () => {
    const rel = intakeRelations(weeks, 1);
    const rest = rel.find((r) => r.x === 'fat' && r.y === 'rest')!;
    expect(rest.estimate!.coef).toBeCloseTo(-100, 6);
  });
});

describe('scatterPoints: 散布図の点', () => {
  const pairs = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => {
    const p = 300 + i * 10;
    const f = 400 + i * 20 + (i % 3) * 15;
    return pair(intake(p, f, 400, 0), 0.002 * f + 0.001 * p);
  });

  it('単独では摂取量と変化そのもの', () => {
    const pts = scatterPoints(pairs, 'protein', 'weightKg', 'single');
    expect(pts[0]).toEqual({ x: 300, y: pairs[0].delta.weightKg! });
  });

  it('固定するときは他の栄養素で説明できない分どうしで、傾きが係数と一致する', () => {
    const pts = scatterPoints(pairs, 'protein', 'weightKg', 'adjusted');
    const mx = pts.reduce((s, p) => s + p.x, 0) / pts.length;
    const my = pts.reduce((s, p) => s + p.y, 0) / pts.length;
    const slope = pts.reduce((s, p) => s + (p.x - mx) * (p.y - my), 0)
      / pts.reduce((s, p) => s + (p.x - mx) ** 2, 0);
    expect(slope * 100).toBeCloseTo(estimate(pairs, 'protein', 'weightKg', 'adjusted', 0)!.coef, 8);
  });
});
