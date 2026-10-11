// 統計ページの「栄養素×体組成の関係」用ロジック。API /statistics/daily の日次行から、
// カロリー源ごとの摂取と体組成の変化の関係（1日 +100kcal あたりの係数と 95% 信頼区間）を出す純粋関数群。
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

/** single: その源だけで回帰 / adjusted: 他のカロリー源を同時に入れて固定する。 */
export type Mode = 'single' | 'adjusted';

export const WINDOWS = [1, 2, 4, 8, 13] as const;

const MIN_KCAL = 800;          // これ未満の日は記録漏れとみなす
const MAX_PFC_RATIO = 1.3;     // PFC 換算が記録カロリーをこれ以上超える日は入力ミスとみなす
const MIN_LOGGED_DAYS = 4;     // 週の摂取として使う最低記録日数
const MIN_BODY_DAYS = 2;       // 週の体組成として使う最低計測日数
const MIN_ROWS = 8;            // これ未満の組では係数を出さない
const Z95 = 1.96;

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

/** 1日 +100kcal あたりの係数と 95% 信頼区間。 */
export interface Estimate {
  coef: number;
  lo: number;
  hi: number;
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

/** 切片付き最小二乗。beta[0] が切片。 */
function ols(y: number[], cols: number[][]) {
  const n = y.length;
  const p = cols.length + 1;
  if (n <= p + 2) return null;
  const X = y.map((_, i) => [1, ...cols.map((c) => c[i])]);
  const XtX = Array.from({ length: p }, (_, a) =>
    Array.from({ length: p }, (_, b) => X.reduce((s, row) => s + row[a] * row[b], 0)));
  const inv = inverse(XtX);
  if (!inv) return null;
  const Xty = Array.from({ length: p }, (_, a) => X.reduce((s, row, i) => s + row[a] * y[i], 0));
  const beta = inv.map((row) => row.reduce((s, v, b) => s + v * Xty[b], 0));
  const resid = X.map((row, i) => y[i] - row.reduce((s, v, k) => s + v * beta[k], 0));
  return { X, inv, beta, resid };
}

/**
 * 係数（切片を除く）と Newey-West の標準誤差。
 * 窓をずらしながら作った組は隣どうしで期間が重なり残差が相関するため、通常の標準誤差だと狭く出すぎる。
 */
export function regress(y: number[], cols: number[][], lag: number) {
  const fit = ols(y, cols);
  if (!fit) return null;
  const { X, inv, beta, resid } = fit;
  const p = beta.length;
  const u = X.map((row, i) => row.map((v) => v * resid[i]));
  const S = Array.from({ length: p }, () => new Array<number>(p).fill(0));
  for (let l = 0; l <= lag; l++) {
    const w = l === 0 ? 1 : 1 - l / (lag + 1);
    for (let i = l; i < u.length; i++) {
      const ui = u[i], uj = u[i - l];
      for (let a = 0; a < p; a++) {
        for (let b = 0; b < p; b++) {
          S[a][b] += w * (l === 0 ? ui[a] * uj[b] : ui[a] * uj[b] + uj[a] * ui[b]);
        }
      }
    }
  }
  const IS = inv.map((row) => Array.from({ length: p }, (_, b) => row.reduce((s, v, k) => s + v * S[k][b], 0)));
  const V = IS.map((row) => Array.from({ length: p }, (_, b) => row.reduce((s, v, k) => s + v * inv[k][b], 0)));
  return {
    coef: beta.slice(1),
    se: V.slice(1).map((row, i) => Math.sqrt(Math.max(row[i + 1], 0))),
  };
}

/** 回帰に入れる説明変数。固定するときは、その期間に変動のある他のカロリー源を全て入れる。 */
function regressors(source: SourceKey, mode: Mode, rows: Record<SourceKey, number>[]): SourceKey[] {
  if (source === 'kcal' || mode === 'single') return [source];
  return ENERGY_SOURCES.filter((s) => s === source || variance(rows.map((r) => r[s])) > 0);
}

function toEstimate(r: ReturnType<typeof regress>, idx: number, n: number): Estimate | null {
  if (!r) return null;
  const coef = r.coef[idx] * 100;
  const half = Z95 * r.se[idx] * 100;
  return { coef, lo: coef - half, hi: coef + half, n };
}

export function estimate(
  pairs: Pair[], source: SourceKey, body: BodyMetricKey, mode: Mode, lag: number,
): Estimate | null {
  const rows = pairs.filter((p) => p.delta[body] != null);
  if (rows.length < MIN_ROWS) return null;
  const xs = regressors(source, mode, rows.map((r) => r.intake));
  const r = regress(rows.map((p) => p.delta[body]!), xs.map((s) => rows.map((p) => p.intake[s])), lag);
  return toEstimate(r, xs.indexOf(source), rows.length);
}

// MARK: - 画面用

export interface RelationCell {
  source: SourceKey;
  body: BodyMetricKey;
  estimate: Estimate | null;
}

export function relationMatrix(weeks: Week[], W: number, mode: Mode): RelationCell[] {
  const pairs = windowPairs(weeks, W);
  return SOURCE_KEYS.flatMap((source) =>
    BODY_KEYS.map((body) => ({ source, body, estimate: estimate(pairs, source, body, mode, 2 * W) })));
}

/** 期間を変えたときの係数。溜まり続けるものは期間に比例して大きくなり、一時的なものは頭打ちになる。 */
export function windowProfile(weeks: Week[], source: SourceKey, body: BodyMetricKey, mode: Mode) {
  return WINDOWS.map((W) => ({ weeks: W, estimate: estimate(windowPairs(weeks, W), source, body, mode, 2 * W) }));
}

/** 朝→翌朝の変化を、当日(0)・前日(1)・前々日(2)の摂取で説明する。 */
export function nextDayEffects(items: DailyStat[], source: SourceKey, body: BodyMetricKey, mode: Mode) {
  const lags = [0, 1, 2] as const;
  const days = new Map(items.map((it) => [it.date, toDay(it)]));
  const ys: number[] = [];
  const rows: Record<SourceKey, number>[][] = [];
  for (const d of days.values()) {
    const next = days.get(addDays(d.date, 1));
    const a = d.body[body], b = next?.body[body];
    if (a == null || b == null) continue;
    const back = lags.map((l) => days.get(addDays(d.date, -l)));
    if (back.some((x) => !x?.logged)) continue;
    ys.push(b - a);
    rows.push(back.map((x) => Object.fromEntries(SOURCE_KEYS.map((s) => [s, x![s]])) as Record<SourceKey, number>));
  }
  const empty = lags.map((lag) => ({ lag, estimate: null as Estimate | null }));
  if (ys.length < MIN_ROWS) return empty;
  const xs = regressors(source, mode, rows.map((r) => r[0]));
  const cols = lags.flatMap((_, li) => xs.map((s) => rows.map((r) => r[li][s])));
  const r = regress(ys, cols, 2);
  return lags.map((lag, li) => ({ lag, estimate: toEstimate(r, li * xs.length + xs.indexOf(source), ys.length) }));
}

export type IntakeTarget = EnergySource | 'rest';

/** ある源が +100kcal の時期に、他の源（と自分以外の合計）が何 kcal 動くか。-100 なら完全に相殺している。 */
export function intakeRelations(weeks: Week[], W: number) {
  const rows = windowPairs(weeks, W).map((p) => p.intake);
  return ENERGY_SOURCES.flatMap((x) => {
    const targets: IntakeTarget[] = [...ENERGY_SOURCES.filter((s) => s !== x), 'rest'];
    return targets.map((y) => {
      const ys = rows.map((r) => (y === 'rest' ? r.kcal - r[x] : r[y]));
      const est = rows.length >= MIN_ROWS ? toEstimate(regress(ys, [rows.map((r) => r[x])], W), 0, rows.length) : null;
      return { x, y, estimate: est };
    });
  });
}

/**
 * 散布図の点。固定するときは、他のカロリー源で説明できない分どうしを描く（傾きが係数と一致する）。
 * 単位が分かるよう、どちらも平均を足して元の水準に戻す。
 */
export function scatterPoints(pairs: Pair[], source: SourceKey, body: BodyMetricKey, mode: Mode) {
  const rows = pairs.filter((p) => p.delta[body] != null);
  const x = rows.map((p) => p.intake[source]);
  const y = rows.map((p) => p.delta[body]!);
  const others = regressors(source, mode, rows.map((r) => r.intake)).filter((s) => s !== source);
  if (others.length === 0) return x.map((xi, i) => ({ x: xi, y: y[i] }));
  const cols = others.map((s) => rows.map((p) => p.intake[s]));
  const fx = ols(x, cols), fy = ols(y, cols);
  if (!fx || !fy) return x.map((xi, i) => ({ x: xi, y: y[i] }));
  const mx = mean(x), my = mean(y);
  return fx.resid.map((rx, i) => ({ x: rx + mx, y: fy.resid[i] + my }));
}
