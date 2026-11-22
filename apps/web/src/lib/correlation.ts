// 統計ページの「栄養素×体組成」相関ダッシュボード用ロジック。
// API /statistics/daily（サーバー側で日次集計・マージ済み）の行を、
// 期間/バケット/集計に応じて二軸グラフ用の系列へ整形する純粋関数群。
//
// 栄養素は lib/statistics.ts の集計と同じ思想（合計 or 暦日数で割った日平均）。
// 体組成は合計に意味が無いため平均のみ。記録の無い日は null（折れ線を欠落させる）。

import type { Bucket } from './statistics';
import { parseDate, formatDate, startOfWeek, startOfMonth } from './statistics';
import type { AddedNutrients, CoreNutrients } from './nutrients';

/** API /statistics/daily が返す日次1行（栄養合計＋体組成平均をマージ済み）。 */
export type DailyStat = CoreNutrients & AddedNutrients & {
  date: string; // "yyyy-MM-dd"
  weightKg: number | null;
  bodyFatPercent: number | null;
  muscleMassKg: number | null;
  muscleScore: number | null;
  visceralFatLevel: number | null;
  basalMetabolismKcal: number | null;
  metabolicAge: number | null;
  boneMassKg: number | null;
  bodyWaterPercent: number | null;
};

/** 折れ線の対象になる体組成指標（DailyStat の number|null フィールド）。 */
export type BodyMetricKey =
  | 'weightKg' | 'bodyFatPercent' | 'muscleMassKg' | 'muscleScore'
  | 'visceralFatLevel' | 'basalMetabolismKcal' | 'metabolicAge'
  | 'boneMassKg' | 'bodyWaterPercent';

export interface BodyMetricConfig {
  key: BodyMetricKey;
  label: string;
  unit: string;
  color: string;
}

// 折れ線（体組成）の色は、栄養素の棒グラフ4色（calories=#ffff00 / protein=#00ff41 /
// fat=#ff00ff / carbs=#00e5ff）と必ず別系統にする。体組成は同時に1本しか描かないため、
// 選択中の栄養素色とだけ被らなければよい。既定の WEIGHT は黄色のカロリー棒と最も
// コントラストが出る青系にしている。
export const BODY_METRICS: BodyMetricConfig[] = [
  { key: 'weightKg',            label: 'WEIGHT',       unit: 'kg',   color: '#38bdf8' },
  { key: 'bodyFatPercent',      label: 'BODY FAT',     unit: '%',    color: '#ff3366' },
  { key: 'muscleMassKg',        label: 'MUSCLE',       unit: 'kg',   color: '#a855f7' },
  { key: 'muscleScore',         label: 'MUSCLE SCORE', unit: '',     color: '#fb923c' },
  { key: 'visceralFatLevel',    label: 'VISCERAL FAT', unit: '',     color: '#f43f5e' },
  { key: 'basalMetabolismKcal', label: 'BMR',          unit: 'kcal', color: '#c084fc' },
  { key: 'metabolicAge',        label: 'META AGE',     unit: 'yr',   color: '#2dd4bf' },
  { key: 'boneMassKg',          label: 'BONE MASS',    unit: 'kg',   color: '#94a3b8' },
  { key: 'bodyWaterPercent',    label: 'BODY WATER',   unit: '%',    color: '#60a5fa' },
];

/** 表示する栄養素軸（StatisticsPage の Metric と揃える）。 */
export type NutrientKey = 'calories' | 'protein' | 'fat' | 'carbs' | 'saltEquivalent';

/** あとから足した栄養素。値の分からない日がある */
function isAddedKey(k: NutrientKey): k is 'saltEquivalent' {
  return k === 'saltEquivalent';
}

/** その日の値。あとから足した栄養素で、どの品も値が分からなければ null */
export function nutrientValue(d: DailyStat, k: NutrientKey): number | null {
  switch (k) {
    case 'calories': return d.calories;
    case 'protein':  return d.protein;
    case 'fat':      return d.fat;
    case 'carbs':    return d.netCarbs + d.dietaryFiber; // iOS の carbs と同じ
    case 'saltEquivalent': return d.saltEquivalent ?? null;
  }
}

/** 期間内に体組成データが1つでもあるか（無ければセクションを出さない判定に使う）。 */
export function hasBodyData(items: DailyStat[]): boolean {
  return items.some((d) => BODY_METRICS.some((m) => d[m.key] != null));
}

function nextDay(s: string): string {
  const d = parseDate(s);
  d.setDate(d.getDate() + 1);
  return formatDate(d);
}

function daysInMonth(monthStart: string): number {
  const d = parseDate(monthStart);
  return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
}

export interface CorrelationPoint {
  date: string;
  /** 値の分からない日は null。折れ線を欠落させる */
  nutrient: number | null;
  body: number | null;
}

/**
 * 二軸グラフ用の系列を生成。
 * - day: [from, to] を1日刻みで埋める（栄養＝値 or 0、体組成＝値 or null）。
 * - week/month: バケット集計。栄養は average なら暦日数で割った日平均、それ以外は合計。
 *   体組成はバケット内の非 null 値の平均（無ければ null）。
 */
export function correlationSeries(
  items: DailyStat[],
  from: string,
  to: string,
  bucket: Bucket,
  average: boolean,
  nutrient: NutrientKey,
  body: BodyMetricKey,
): CorrelationPoint[] {
  const byDate = new Map(items.map((d) => [d.date, d]));

  // まず [from, to] の連続日次系列に展開。
  const daily: CorrelationPoint[] = [];
  let cur = from;
  while (cur <= to) {
    const d = byDate.get(cur);
    // 記録の無い日は、最初の5項目なら 0、あとから足した栄養素なら分からない
    daily.push({
      date: cur,
      nutrient: d ? nutrientValue(d, nutrient) : isAddedKey(nutrient) ? null : 0,
      body: d ? d[body] : null,
    });
    cur = nextDay(cur);
  }

  if (bucket === 'day') return daily;

  // 週/月バケットへ集計。
  const groups = new Map<string, { nSum: number; nCount: number; bSum: number; bCount: number }>();
  for (const p of daily) {
    const date = parseDate(p.date);
    const start = bucket === 'week' ? startOfWeek(date) : startOfMonth(date);
    const key = formatDate(start);
    const g = groups.get(key) ?? { nSum: 0, nCount: 0, bSum: 0, bCount: 0 };
    if (p.nutrient != null) {
      g.nSum += p.nutrient;
      g.nCount += 1;
    }
    if (p.body != null) {
      g.bSum += p.body;
      g.bCount += 1;
    }
    groups.set(key, g);
  }

  return [...groups.entries()]
    .map(([key, g]) => {
      // あとから足した栄養素は、値の分かっている日だけで割る。分からない日を 0 の日として数えない
      const div = isAddedKey(nutrient) ? g.nCount : bucket === 'week' ? 7 : daysInMonth(key);
      const value = average ? g.nSum / Math.max(div, 1) : g.nSum;
      return {
        date: key,
        nutrient: isAddedKey(nutrient) && g.nCount === 0 ? null : value,
        body: g.bCount > 0 ? g.bSum / g.bCount : null,
      };
    })
    .sort((a, b) => a.date.localeCompare(b.date));
}

/** 期間内の体組成指標について、最新値と期間始端比の差分を返す（サマリ表示用）。 */
export interface BodyDelta {
  key: BodyMetricKey;
  latest: number | null;
  delta: number | null; // latest - earliest（同一日のみだと null）
}

export function bodyDeltas(items: DailyStat[]): BodyDelta[] {
  return BODY_METRICS.map((m) => {
    const present = items.filter((d) => d[m.key] != null) as (DailyStat & Record<BodyMetricKey, number>)[];
    if (present.length === 0) return { key: m.key, latest: null, delta: null };
    const earliest = present[0][m.key];
    const latest = present[present.length - 1][m.key];
    return {
      key: m.key,
      latest,
      delta: present.length > 1 ? latest - earliest : null,
    };
  });
}
