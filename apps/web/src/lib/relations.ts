// 統計ページの「栄養素×体組成の関係」用ロジック。API /statistics/daily の日次行から、
// カロリー源ごとの摂取と体組成の変化の関係を調べ、確かなものだけを文にする純粋関数群。
//
// 同じ日の値どうしは比べない。体組成計は日々のブレが大きく、食べた分は数日〜数週間かけて表れるため、
// 「W週の摂取の平均」と「直前W週の平均 → 直後W週の平均の変化」を組にする。
// カロリー源は kcal に揃える。PFC のどれにも入らない分（お酒など）は「その他」として別に持つ。

import { BODY_METRICS, type BodyMetricKey, type DailyStat } from './correlation';
import {
  PROTEIN_KCAL, FAT_KCAL, NET_CARBS_KCAL, FIBER_KCAL,
  parseDate, formatDate, startOfWeek,
} from './statistics';

/** 合計kcal を構成するカロリー源。合計kcal はこれらの和なので、固定するときは一緒に回帰しない。 */
export const ENERGY_SOURCES = ['protein', 'fat', 'carbs', 'other'] as const;
export type EnergySource = (typeof ENERGY_SOURCES)[number];
export type SourceKey = 'kcal' | EnergySource;
export const SOURCE_KEYS: SourceKey[] = ['kcal', ...ENERGY_SOURCES];

const MIN_KCAL = 800;          // これ未満の日は記録漏れとみなす
const MAX_PFC_RATIO = 1.3;     // PFC 換算が記録カロリーをこれ以上超える日は入力ミスとみなす
const MIN_LOGGED_DAYS = 4;     // 週の摂取として使う最低記録日数
const MIN_BODY_DAYS = 2;       // 週の体組成として使う最低計測日数
const MIN_ROWS = 8;            // これ未満の組では係数を出さない

type BodyValues = Record<BodyMetricKey, number | null>;

export interface RelDay {
  date: string;
  logged: boolean;
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
  other: number;
  body: BodyValues;
}

export interface Week {
  start: string; // 月曜の "yyyy-MM-dd"
  intake: Record<SourceKey, number> | null;
  body: BodyValues;
}

export interface Pair {
  start: string;
  intake: Record<SourceKey, number>;
  delta: BodyValues;
}

/** 1日 1kcal あたりの係数と、その t 値。 */
export interface Estimate {
  coef: number;
  t: number;
  n: number;
}

const BODY_KEYS = BODY_METRICS.map((m) => m.key);

function mean(v: number[]): number {
  return v.reduce((s, x) => s + x, 0) / v.length;
}

function variance(v: number[]): number {
  const m = mean(v);
  return v.reduce((s, x) => s + (x - m) ** 2, 0);
}

// MARK: - 日・週・組

export function toDay(d: DailyStat): RelDay {
  const protein = d.protein * PROTEIN_KCAL;
  const fat = d.fat * FAT_KCAL;
  const carbs = d.netCarbs * NET_CARBS_KCAL + d.dietaryFiber * FIBER_KCAL;
  const pfc = protein + fat + carbs;
  const body = {} as BodyValues;
  for (const k of BODY_KEYS) body[k] = d[k];
  return {
    date: d.date,
    logged: d.calories >= MIN_KCAL && pfc <= d.calories * MAX_PFC_RATIO,
    kcal: d.calories,
    protein, fat, carbs,
    other: Math.max(d.calories - pfc, 0),
    body,
  };
}

function weekStart(date: string): string {
  return formatDate(startOfWeek(parseDate(date)));
}

function addDays(date: string, n: number): string {
  const d = parseDate(date);
  d.setDate(d.getDate() + n);
  return formatDate(d);
}

/** 月曜始まりの週ごとにまとめる。データの無い週も詰めずに並べる（期間の長さを週数で数えるため）。 */
export function buildWeeks(items: DailyStat[]): Week[] {
  if (items.length === 0) return [];
  const byWeek = new Map<string, RelDay[]>();
  for (const it of items) {
    const key = weekStart(it.date);
    const list = byWeek.get(key) ?? [];
    list.push(toDay(it));
    byWeek.set(key, list);
  }
  const keys = [...byWeek.keys()].sort();
  const weeks: Week[] = [];
  for (let k = keys[0]; k <= keys[keys.length - 1]; k = addDays(k, 7)) {
    const days = byWeek.get(k) ?? [];
    const logged = days.filter((d) => d.logged);
    const intake = logged.length >= MIN_LOGGED_DAYS
      ? Object.fromEntries(SOURCE_KEYS.map((s) => [s, mean(logged.map((d) => d[s]))])) as Record<SourceKey, number>
      : null;
    const body = {} as BodyValues;
    for (const b of BODY_KEYS) {
      const v = days.map((d) => d.body[b]).filter((x): x is number => x != null);
      body[b] = v.length >= MIN_BODY_DAYS ? mean(v) : null;
    }
    weeks.push({ start: k, intake, body });
  }
  return weeks;
}

/** weeks[i, j) の値の平均。半分以上欠けていれば null。 */
function blockMean(values: (number | null)[], i: number, j: number): number | null {
  if (i < 0 || j > values.length) return null;
  const v = values.slice(i, j).filter((x): x is number => x != null);
  return v.length * 2 >= j - i ? mean(v) : null;
}

/** 週 j から W 週の摂取の平均 × 直前 W 週の平均から直後 W 週の平均への変化。 */
export function windowPairs(weeks: Week[], W: number): Pair[] {
  const intakeSeries = Object.fromEntries(
    SOURCE_KEYS.map((s) => [s, weeks.map((w) => w.intake?.[s] ?? null)]),
  ) as Record<SourceKey, (number | null)[]>;
  const bodySeries = Object.fromEntries(
    BODY_KEYS.map((b) => [b, weeks.map((w) => w.body[b])]),
  ) as Record<BodyMetricKey, (number | null)[]>;

  const pairs: Pair[] = [];
  for (let j = W; j + 2 * W <= weeks.length; j++) {
    const intake = {} as Record<SourceKey, number>;
    let ok = true;
    for (const s of SOURCE_KEYS) {
      const v = blockMean(intakeSeries[s], j, j + W);
      if (v == null) { ok = false; break; }
      intake[s] = v;
    }
    if (!ok) continue;
    const delta = {} as BodyValues;
    for (const b of BODY_KEYS) {
      const before = blockMean(bodySeries[b], j - W, j);
      const after = blockMean(bodySeries[b], j + W, j + 2 * W);
      delta[b] = before != null && after != null ? after - before : null;
    }
    pairs.push({ start: weeks[j].start, intake, delta });
  }
  return pairs;
}

// MARK: - 回帰

function inverse(A: number[][]): number[][] | null {
  const p = A.length;
  const M = A.map((row, i) => [...row, ...row.map((_, j) => (i === j ? 1 : 0))]);
  for (let col = 0; col < p; col++) {
    let piv = col;
    for (let r = col + 1; r < p; r++) if (Math.abs(M[r][col]) > Math.abs(M[piv][col])) piv = r;
    [M[col], M[piv]] = [M[piv], M[col]];
    const d = M[col][col];
    if (Math.abs(d) < 1e-10) return null;
    for (let k = 0; k < 2 * p; k++) M[col][k] /= d;
    for (let r = 0; r < p; r++) {
      if (r === col) continue;
      const f = M[r][col];
      if (f !== 0) for (let k = 0; k < 2 * p; k++) M[r][k] -= f * M[col][k];
    }
  }
  return M.map((row) => row.slice(p));
}

/**
 * 切片付き最小二乗の係数（切片を除く）と t 値。
 * 期間を重ねて作った組は互いに独立でないので、この t 値をそのまま正規分布で判定してはいけない。
 * 判定は findings で、摂取を時間方向にずらしたときの t 値と比べて行う。
 */
export function regress(y: number[], cols: number[][]) {
  const n = y.length;
  const p = cols.length + 1;
  if (n <= p + 2) return null;
  // 毎回の行を配列で作らずに X'X と X'y を足し込む（摂取をずらすたびに何千回も呼ぶため）。
  const col = (k: number, i: number) => (k === 0 ? 1 : cols[k - 1][i]);
  const XtX = Array.from({ length: p }, () => new Array<number>(p).fill(0));
  const Xty = new Array<number>(p).fill(0);
  for (let i = 0; i < n; i++) {
    for (let a = 0; a < p; a++) {
      const va = col(a, i);
      Xty[a] += va * y[i];
      for (let b = a; b < p; b++) XtX[a][b] += va * col(b, i);
    }
  }
  for (let a = 0; a < p; a++) for (let b = 0; b < a; b++) XtX[a][b] = XtX[b][a];
  const inv = inverse(XtX);
  if (!inv) return null;
  const beta = inv.map((row) => row.reduce((s, v, b) => s + v * Xty[b], 0));
  let rss = 0;
  for (let i = 0; i < n; i++) {
    let fit = 0;
    for (let k = 0; k < p; k++) fit += beta[k] * col(k, i);
    rss += (y[i] - fit) ** 2;
  }
  const s2 = rss / (n - p);
  return {
    coef: beta.slice(1),
    t: beta.slice(1).map((b, i) => b / Math.sqrt(s2 * inv[i + 1][i + 1])),
  };
}

/**
 * 体組成の指標1つについて、全てのカロリー源の係数を出す。
 * P・F・C・その他は、その期間に変動のあるものを全て入れた1本の回帰で互いを固定する。
 * 合計kcal はそれらの和なので、一緒には入れず単独で回帰する。
 */
function fitAll(pairs: Pair[], body: BodyMetricKey): Partial<Record<SourceKey, Estimate>> {
  const rows = pairs.filter((p) => p.delta[body] != null);
  if (rows.length < MIN_ROWS) return {};
  const y = rows.map((p) => p.delta[body]!);
  const n = rows.length;
  const out: Partial<Record<SourceKey, Estimate>> = {};
  const k = regress(y, [rows.map((p) => p.intake.kcal)]);
  if (k) out.kcal = { coef: k.coef[0], t: k.t[0], n };
  const xs = ENERGY_SOURCES.filter((s) => variance(rows.map((p) => p.intake[s])) > 0);
  const r = regress(y, xs.map((s) => rows.map((p) => p.intake[s])));
  if (r) xs.forEach((s, i) => { out[s] = { coef: r.coef[i], t: r.t[i], n }; });
  return out;
}

export function estimate(pairs: Pair[], source: SourceKey, body: BodyMetricKey): Estimate | null {
  return fitAll(pairs, body)[source] ?? null;
}

// MARK: - 文にする関係

const SHORT_WEEKS = 2;
/** 文の値に使う期間。2週間でも4週間でも同じ向きに出ることを求め、数週で戻る変化を除く。 */
export const LONG_WEEKS = 4;
/** 摂取をこれ以上ずらせば、元の摂取と体組成の期間が重ならない。 */
const MIN_SHIFT = 3 * LONG_WEEKS;
/**
 * ずらしたときの最大値の 99% 点を超えたものだけを文にする。
 * 関係の無い合成データで、文が出てしまう人が5%以下になる厳しさ（95% 点では1割近くになる）。
 */
const QUANTILE = 0.99;
/** ずらし方がこれだけ取れるまでは判定しない。少ないと 99% 点が荒くなる。 */
export const MIN_SHIFTS = 30;
// 計算量を抑えるため、記録が長い人もずらし方はこの数までにする（等間隔に間引く）。
const MAX_SHIFTS = 100;
/** 4週間の期間でこれだけ組がそろった指標だけを判定する。 */
const MIN_PAIRS = 20;

export interface Finding {
  source: SourceKey;
  body: BodyMetricKey;
  /** ふだんの増減の幅。4週間平均の摂取（kcal/日）の標準偏差。 */
  typical: number;
  /** 摂取が typical だけ多いときの、4週間の前後の変化（指標の単位）。 */
  change: number;
  /** 2週間と4週間の t 値の小さい方。並べる順に使う。 */
  score: number;
}

export type FindingsResult =
  | { kind: 'ready'; findings: Finding[] }
  | { kind: 'short'; weeksNeeded: number };

function sd(v: number[]): number {
  return Math.sqrt(variance(v) / (v.length - 1));
}

interface Scored { source: SourceKey; body: BodyMetricKey; score: number; long: Estimate }

/** 2週間と4週間の両方で同じ向きなら、t 値の小さい方。向きが違えば 0。 */
function score(weeks: Week[], bodies: BodyMetricKey[]): Scored[] {
  const short = windowPairs(weeks, SHORT_WEEKS);
  const long = windowPairs(weeks, LONG_WEEKS);
  const out: Scored[] = [];
  for (const body of bodies) {
    const s = fitAll(short, body);
    const l = fitAll(long, body);
    for (const source of SOURCE_KEYS) {
      const a = s[source], b = l[source];
      if (!a || !b) continue;
      const same = Math.sign(a.t) === Math.sign(b.t);
      out.push({ source, body, score: same ? Math.min(Math.abs(a.t), Math.abs(b.t)) : 0, long: b });
    }
  }
  return out;
}

/** 摂取だけを s 週ずらす（末尾は先頭へ回す）。体組成との関係だけが壊れ、それぞれの続き方は残る。 */
function shiftIntake(weeks: Week[], s: number): Week[] {
  return weeks.map((w, i) => ({ ...w, intake: weeks[(i + s) % weeks.length].intake }));
}

function shiftsFor(n: number): number[] {
  const all = n - 2 * MIN_SHIFT + 1;
  const count = Math.min(all, MAX_SHIFTS);
  return Array.from({ length: count }, (_, i) => MIN_SHIFT + Math.round((i * (all - 1)) / Math.max(count - 1, 1)));
}

/**
 * 確かな関係だけを、確かな順に返す。
 *
 * 期間を1週ずつずらして組を作るので、組どうしは独立でなく、t 値を正規分布で判定すると
 * 関係が無くても大半の人で何かが「確か」に出てしまう。Newey-West の補正も、この記録の長さでは偶然を抑えきれない。
 * そこで、摂取を何週もずらして体組成との関係だけを壊したデータを作り、全ての組み合わせの最大値と比べる。
 * 組み合わせの多さによる偶然も、これで一緒に抑えられる。
 */
export function findings(weeks: Week[]): FindingsResult {
  const pairs = windowPairs(weeks, LONG_WEEKS);
  const pairCount = (b: BodyMetricKey) => pairs.filter((p) => p.delta[b] != null).length;
  const bodies = BODY_KEYS.filter((b) => pairCount(b) >= MIN_PAIRS);
  // 1週増えるごとに、ずらし方も組も1つずつ増える。
  const shiftsShort = MIN_SHIFTS - (weeks.length - 2 * MIN_SHIFT + 1);
  if (bodies.length === 0 || shiftsShort > 0) {
    const pairsShort = bodies.length > 0 ? 0 : MIN_PAIRS - Math.max(0, ...BODY_KEYS.map(pairCount));
    return { kind: 'short', weeksNeeded: Math.max(shiftsShort, pairsShort) };
  }

  const maxes = shiftsFor(weeks.length)
    .map((s) => Math.max(0, ...score(shiftIntake(weeks, s), bodies).map((x) => x.score)))
    .sort((a, b) => a - b);
  const threshold = maxes[Math.ceil(QUANTILE * maxes.length) - 1];

  const out = score(weeks, bodies)
    .filter((x) => x.score > threshold)
    .map(({ source, body, score, long }) => {
      const typical = sd(pairs.filter((p) => p.delta[body] != null).map((p) => p.intake[source]));
      return { source, body, typical, change: long.coef * typical, score };
    });
  return { kind: 'ready', findings: out.sort((a, b) => b.score - a.score) };
}

// MARK: - 文

const SOURCE_TEXT: Record<SourceKey, { lead: string; kcalPerGram?: number }> = {
  kcal:    { lead: 'たくさん食べた' },
  protein: { lead: 'タンパク質を多くとった', kcalPerGram: PROTEIN_KCAL },
  fat:     { lead: '脂質を多くとった', kcalPerGram: FAT_KCAL },
  carbs:   { lead: '炭水化物を多くとった', kcalPerGram: NET_CARBS_KCAL },
  other:   { lead: 'PFC 以外のカロリーが多い' },
};

const METRIC_TEXT: Record<BodyMetricKey, { name: string; unit: string }> = {
  weightKg:            { name: '体重',           unit: 'kg' },
  bodyFatPercent:      { name: '体脂肪率',       unit: '%' },
  muscleMassKg:        { name: '筋肉量',         unit: 'kg' },
  muscleScore:         { name: '筋肉スコア',     unit: '' },
  visceralFatLevel:    { name: '内臓脂肪レベル', unit: '' },
  basalMetabolismKcal: { name: '基礎代謝',       unit: 'kcal' },
  metabolicAge:        { name: '体内年齢',       unit: '歳' },
  boneMassKg:          { name: '推定骨量',       unit: 'kg' },
  bodyWaterPercent:    { name: '体水分率',       unit: '%' },
};

function amount(source: SourceKey, kcal: number): string {
  const g = SOURCE_TEXT[source].kcalPerGram;
  if (!g) return `${Math.round(kcal / 10) * 10}kcal`;
  const grams = kcal / g;
  return `${grams >= 10 ? Math.round(grams / 5) * 5 : Math.max(Math.round(grams), 1)}g`;
}

export function findingText(f: Finding): { headline: string; detail: string } {
  const metric = METRIC_TEXT[f.body];
  const up = f.change > 0;
  const value = Number(Math.abs(f.change).toPrecision(2));
  return {
    headline: `${SOURCE_TEXT[f.source].lead}${LONG_WEEKS}週間の前後で、${metric.name}が${up ? '増える' : '減る'}傾向があります`,
    detail: `ふだんより1日約${amount(f.source, f.typical)} 多いと、${up ? '+' : '−'}${value}${metric.unit} ほど`,
  };
}
