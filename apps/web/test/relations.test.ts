import { describe, it, expect } from 'bun:test';
import {
  toDay, buildWeeks, windowPairs, regress, estimate, findings, findingText, MIN_SHIFTS,
  type Week, type Pair, type SourceKey, type Finding,
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

describe('regress: 切片付きの最小二乗', () => {
  const x1 = [1, 2, 3, 4, 5, 6, 7, 8];
  const x2 = [2, 1, 4, 3, 6, 5, 8, 7];
  const y = [3.1, 4.9, 7.2, 8.8, 11.1, 13.0, 15.2, 16.8];

  it('係数と t 値', () => {
    const r = regress(y, [x1, x2])!;
    expect(r.coef[0]).toBeCloseTo(1.86375, 8);
    expect(r.coef[1]).toBeCloseTo(0.13875, 8);
    expect(r.t[0]).toBeCloseTo(59.601867004, 6);
    expect(r.t[1]).toBeCloseTo(4.437161125, 6);
  });

  it('説明変数より行が少なければ null', () => {
    expect(regress([1, 2, 3], [[1, 2, 3], [3, 1, 2]])).toBeNull();
  });

  it('説明変数が一定なら null', () => {
    expect(regress([1, 2, 3, 4, 5], [[1, 1, 1, 1, 1]])).toBeNull();
  });
});

describe('estimate: 1日 1kcal あたりの係数', () => {
  // タンパク質と脂質が一緒に増減し、体重の変化は脂質だけで決まるデータ。
  const pairs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => {
    const p = 300 + i * 10;
    const f = 400 + i * 20 + (i % 3) * 15;
    return pair(intake(p, f, 400, 0), 0.002 * f + 0.0001 * ((i * 7) % 5));
  });

  it('他の栄養素を固定するので、一緒に増えただけのタンパク質はほぼ0・脂質はほぼ0.002になる', () => {
    expect(estimate(pairs, 'protein', 'weightKg')!.coef).toBeCloseTo(0, 4);
    expect(estimate(pairs, 'fat', 'weightKg')!.coef).toBeCloseTo(0.002, 4);
  });

  it('合計kcal は他の栄養素の合計なので、単独で回帰する', () => {
    const r = regress(pairs.map((p) => p.delta.weightKg!), [pairs.map((p) => p.intake.kcal)])!;
    const e = estimate(pairs, 'kcal', 'weightKg')!;
    expect(e.coef).toBeCloseTo(r.coef[0], 10);
    expect(e.t).toBeCloseTo(r.t[0], 10);
  });

  it('組の数を返す', () => {
    expect(estimate(pairs, 'fat', 'weightKg')!.n).toBe(10);
  });

  it('体組成の無い指標は null', () => {
    expect(estimate(pairs, 'fat', 'muscleMassKg')).toBeNull();
  });
});

/** 再現できる乱数（mulberry32）。標準正規は Box-Muller。 */
function rng(seed: number) {
  let a = seed;
  const uniform = () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return () => Math.sqrt(-2 * Math.log(1 - uniform())) * Math.cos(2 * Math.PI * uniform());
}

/** 数週続けて多い・少ないが続く摂取（kcal/日）。 */
function ar(n: number, base: number, sd: number, normal: () => number): number[] {
  const out: number[] = [];
  let x = 0;
  for (let i = 0; i < n; i++) {
    x = 0.7 * x + Math.sqrt(1 - 0.49) * sd * normal();
    out.push(base + x);
  }
  return out;
}

interface Gen {
  weeks: number;
  seed: number;
  /** 週ごとの体重の動き。carbs・protein はその週の摂取（kcal/日）。 */
  weight?: (i: number, carbs: number, protein: number, prev: number) => number;
  /** タンパク質を炭水化物と一緒に動かす。 */
  proteinFollowsCarbs?: boolean;
}

/** 体重は、指定が無ければ摂取と無関係にゆっくり勝手に動く。体重計の値には毎週のブレが乗る。 */
function synthetic({ weeks, seed, weight, proteinFollowsCarbs = false }: Gen): Week[] {
  const normal = rng(seed);
  const carbs = ar(weeks, 1000, 120, normal);
  const ownProtein = ar(weeks, 350, 60, normal);
  const protein = proteinFollowsCarbs ? carbs.map((c, i) => 350 + 0.5 * (c - 1000) + 0.3 * (ownProtein[i] - 350)) : ownProtein;
  const fat = ar(weeks, 600, 80, normal);
  const other = ar(weeks, 100, 30, normal);
  const out: Week[] = [];
  let truth = 65;
  for (let i = 0; i < weeks; i++) {
    truth = weight ? weight(i, carbs[i], protein[i], truth) : truth + 0.1 * normal();
    out.push(week(i, intake(protein[i], fat[i], carbs[i], other[i]), truth + 0.3 * normal()));
  }
  return out;
}

function found(weeks: Week[]): Finding[] {
  const r = findings(weeks);
  if (r.kind !== 'ready') throw new Error(`記録が足りない判定になった: ${JSON.stringify(r)}`);
  return r.findings;
}

describe('findings: 確かな関係だけを選ぶ', () => {
  it('炭水化物の多い週の分だけ体重が溜まっていくなら、炭水化物と体重の関係が出る', () => {
    const weeks = synthetic({ weeks: 104, seed: 1, weight: (_i, c, _p, prev) => prev + 0.001 * (c - 1000) });
    const f = found(weeks).find((x) => x.source === 'carbs' && x.body === 'weightKg');
    expect(f).toBeDefined();
    expect(f!.change).toBeGreaterThan(0);
  });

  it('その週の摂取で体重計の値が上下するだけで溜まらないなら、出ない', () => {
    const weeks = synthetic({ weeks: 104, seed: 2, weight: (_i, c) => 65 + 0.002 * (c - 1000) });
    expect(found(weeks).filter((x) => x.source === 'carbs')).toEqual([]);
  });

  it('炭水化物と一緒に動いただけのタンパク質は出ない', () => {
    const weeks = synthetic({
      weeks: 104, seed: 3, proteinFollowsCarbs: true,
      weight: (_i, c, _p, prev) => prev + 0.002 * (c - 1000),
    });
    const sources = found(weeks).filter((x) => x.body === 'weightKg').map((x) => x.source);
    expect(sources.length).toBeGreaterThan(0);
    expect(sources).not.toContain('protein');
  });

  it('摂取と体重が無関係なら、ほとんどの人で何も出ない', () => {
    // 期間を重ねた組をそのまま t 値で判定すると、この条件では大半の人に何かが出てしまう。
    const withAny = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
      .filter((seed) => found(synthetic({ weeks: 78, seed: 100 + seed })).length > 0);
    expect(withAny.length).toBeLessThanOrEqual(1);
  });

  it('ふだんの量は、4週間平均のばらつき1つ分。変化は、その量だけ多いときの4週間の前後の値', () => {
    const weeks = synthetic({ weeks: 104, seed: 1, weight: (_i, c, _p, prev) => prev + 0.001 * (c - 1000) });
    const f = found(weeks).find((x) => x.source === 'carbs' && x.body === 'weightKg')!;
    const x = windowPairs(weeks, 4).map((p) => p.intake.carbs);
    const m = x.reduce((s, v) => s + v, 0) / x.length;
    const sd = Math.sqrt(x.reduce((s, v) => s + (v - m) ** 2, 0) / (x.length - 1));
    expect(f.typical).toBeCloseTo(sd, 8);
    expect(f.change).toBeCloseTo(estimate(windowPairs(weeks, 4), 'carbs', 'weightKg')!.coef * sd, 8);
  });

  it('確かなものから順に並べる', () => {
    const weeks = synthetic({
      weeks: 104, seed: 5,
      weight: (_i, c, p, prev) => prev + 0.002 * (c - 1000) + 0.003 * (p - 350),
    });
    const scores = found(weeks).map((f) => f.score);
    expect(scores.length).toBeGreaterThan(1);
    expect(scores).toEqual([...scores].sort((a, b) => b - a));
  });

  it('摂取をずらす余地が足りないうちは、あと何週分の記録が要るかを返す', () => {
    // 12週以上ずらし、後ろからも12週以上残すので、ずらし方は「週数 − 23」通り。1週ごとに1つ増える。
    expect(findings(synthetic({ weeks: 40, seed: 6 }))).toEqual({ kind: 'short', weeksNeeded: MIN_SHIFTS + 23 - 40 });
    expect(findings(synthetic({ weeks: 40 + MIN_SHIFTS + 23 - 40, seed: 6 })).kind).toBe('ready');
  });

  it('体組成の記録が無ければ、組がそろうまでの週数も見る', () => {
    expect(findings([])).toEqual({ kind: 'short', weeksNeeded: MIN_SHIFTS + 23 });
  });
});

describe('findingText: 文にする', () => {
  const base: Finding = { source: 'carbs', body: 'weightKg', typical: 120, change: 0.4, score: 4 };

  it('栄養素を多くとった4週間の前後で、指標が増える傾向がある', () => {
    expect(findingText(base)).toEqual({
      headline: '炭水化物を多くとった4週間の前後で、体重が増える傾向があります',
      detail: 'ふだんより1日約30g 多いと、+0.4kg ほど',
    });
  });

  it('減るときは「減る」とマイナスの値', () => {
    const t = findingText({ ...base, change: -0.25 });
    expect(t.headline).toBe('炭水化物を多くとった4週間の前後で、体重が減る傾向があります');
    expect(t.detail).toBe('ふだんより1日約30g 多いと、−0.25kg ほど');
  });

  it('脂質の g は kcal を9で割る', () => {
    expect(findingText({ ...base, source: 'fat', typical: 90 }).detail).toBe('ふだんより1日約10g 多いと、+0.4kg ほど');
  });

  it('g は10以上なら5刻み、10未満なら1刻みで丸める', () => {
    expect(findingText({ ...base, source: 'protein', typical: 90 }).detail).toMatch(/約25g/);
    expect(findingText({ ...base, source: 'protein', typical: 26 }).detail).toMatch(/約7g/);
  });

  it('合計カロリーは「たくさん食べた」、量は10kcal 刻み', () => {
    expect(findingText({ ...base, source: 'kcal', typical: 153 })).toEqual({
      headline: 'たくさん食べた4週間の前後で、体重が増える傾向があります',
      detail: 'ふだんより1日約150kcal 多いと、+0.4kg ほど',
    });
  });

  it('その他は「PFC 以外のカロリー」で、量は kcal', () => {
    expect(findingText({ ...base, source: 'other', typical: 48 })).toEqual({
      headline: 'PFC 以外のカロリーが多い4週間の前後で、体重が増える傾向があります',
      detail: 'ふだんより1日約50kcal 多いと、+0.4kg ほど',
    });
  });

  it('変化は有効数字2桁。指標ごとの単位を付ける', () => {
    expect(findingText({ ...base, body: 'bodyFatPercent', change: 0.4321 }).detail).toMatch(/\+0\.43% ほど$/);
    expect(findingText({ ...base, body: 'basalMetabolismKcal', change: 12.6 }).detail).toMatch(/\+13kcal ほど$/);
    expect(findingText({ ...base, body: 'metabolicAge', change: 1.04 }).detail).toMatch(/\+1歳 ほど$/);
    expect(findingText({ ...base, body: 'visceralFatLevel', change: 0.3 }).detail).toMatch(/\+0\.3 ほど$/);
  });

  it('指標名は日本語', () => {
    expect(findingText({ ...base, body: 'muscleMassKg' }).headline).toMatch(/筋肉量が/);
    expect(findingText({ ...base, body: 'bodyWaterPercent' }).headline).toMatch(/体水分率が/);
  });
});
