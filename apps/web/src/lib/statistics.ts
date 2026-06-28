// 統計タブの期間集計ロジック。View から切り離した純粋関数群（テスト容易性のため）。
// iOS の StatisticsCalculator.swift を移植したもので、数値が一致するよう定義を揃えている。
//
// エネルギー換算はアプリの目標カロリー式（NutritionGoals.targetCalories）と揃える:
// タンパク質×4 + 脂質×9 + 糖質(netCarbs)×4 + 食物繊維×2 kcal。

export const PROTEIN_KCAL = 4;
export const FAT_KCAL = 9;
export const NET_CARBS_KCAL = 4;
export const FIBER_KCAL = 2;

/** API の /log-items/summary が返す、日付×食事タイプの集計済み1行。 */
export interface DaySummary {
  logDate: string; // "yyyy-MM-dd"
  mealType: string;
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
}

/** 計算済みの栄養素値。`carbs` は iOS と同じく netCarbs + dietaryFiber。 */
export interface NutritionValues {
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
}

export const ZERO_VALUES: NutritionValues = {
  calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0,
};

/** iOS の NutritionValues.carbs（netCarbs + dietaryFiber）。 */
export function carbs(v: NutritionValues): number {
  return v.netCarbs + v.dietaryFiber;
}

function add(a: NutritionValues, b: NutritionValues): NutritionValues {
  return {
    calories: a.calories + b.calories,
    protein: a.protein + b.protein,
    fat: a.fat + b.fat,
    netCarbs: a.netCarbs + b.netCarbs,
    dietaryFiber: a.dietaryFiber + b.dietaryFiber,
  };
}

function toValues(item: DaySummary): NutritionValues {
  return {
    calories: item.calories,
    protein: item.protein,
    fat: item.fat,
    netCarbs: item.netCarbs,
    dietaryFiber: item.dietaryFiber,
  };
}

/** 1日分の集計結果（トレンドグラフ・平均・達成日数の素材）。 */
export interface DailyNutrition {
  date: string; // "yyyy-MM-dd"
  values: NutritionValues;
}

/** PFC のエネルギー比率（合計100%。記録ゼロなら全て0）。 */
export interface PFCBalance {
  protein: number;
  fat: number;
  carbs: number;
}

export const ZERO_BALANCE: PFCBalance = { protein: 0, fat: 0, carbs: 0 };

// MARK: - 日付ユーティリティ（ローカルタイムの "yyyy-MM-dd"）

export function formatDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** "yyyy-MM-dd" をローカル深夜の Date に。 */
export function parseDate(s: string): Date {
  return new Date(s + 'T00:00:00');
}

/** その週の月曜（iOS の weekOfYear グルーピング相当。週初め＝月曜）。 */
export function startOfWeek(d: Date): Date {
  const r = new Date(d);
  const dow = r.getDay(); // 0=Sun
  r.setDate(r.getDate() - (dow === 0 ? 6 : dow - 1));
  r.setHours(0, 0, 0, 0);
  return r;
}

/** その月の1日。 */
export function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

/** "yyyy-MM-dd"（月初め）の月の暦日数。 */
function daysInMonth(monthStart: string): number {
  const d = parseDate(monthStart);
  return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
}

// MARK: - 集計ロジック

/** 日別合計。logDate でグルーピングし、各日の値を合算。日付昇順で返す。 */
export function dailyTotals(items: DaySummary[]): DailyNutrition[] {
  const map = new Map<string, NutritionValues>();
  for (const item of items) {
    map.set(item.logDate, add(map.get(item.logDate) ?? ZERO_VALUES, toValues(item)));
  }
  return Array.from(map.entries())
    .map(([date, values]) => ({ date, values }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

/** [from, to]（両端含む）の各日を、記録があればその値・無ければ0で埋めた連続系列。 */
export function fillDays(daily: DailyNutrition[], from: string, to: string): DailyNutrition[] {
  const byDate = new Map(daily.map((d) => [d.date, d]));
  const result: DailyNutrition[] = [];
  let current = from;
  while (current <= to) {
    result.push(byDate.get(current) ?? { date: current, values: ZERO_VALUES });
    const d = parseDate(current);
    d.setDate(d.getDate() + 1);
    current = formatDate(d);
  }
  return result;
}

export type Bucket = 'day' | 'week' | 'month';

/**
 * 日別系列を週/月バケットに集計し直す（トレンドグラフの単位切替用）。
 * 各バケットの代表日は期間先頭（月なら1日、週なら週初め）。`average` のときは
 * バケットの暦日数（週=7、月=その月の日数）で割った日平均（記録のない日も母数に含める）、
 * それ以外は合計を返す。日付昇順。
 */
export function bucketed(
  daily: DailyNutrition[],
  by: 'week' | 'month',
  average: boolean
): DailyNutrition[] {
  const groups = new Map<string, NutritionValues>();
  for (const d of daily) {
    const date = parseDate(d.date);
    const start = by === 'week' ? startOfWeek(date) : startOfMonth(date);
    const key = formatDate(start);
    groups.set(key, add(groups.get(key) ?? ZERO_VALUES, d.values));
  }
  return Array.from(groups.entries())
    .map(([key, sum]) => {
      if (!average) return { date: key, values: sum };
      const n = by === 'week' ? 7 : daysInMonth(key);
      const div = Math.max(n, 1);
      return {
        date: key,
        values: {
          calories: sum.calories / div,
          protein: sum.protein / div,
          fat: sum.fat / div,
          netCarbs: sum.netCarbs / div,
          dietaryFiber: sum.dietaryFiber / div,
        },
      };
    })
    .sort((a, b) => a.date.localeCompare(b.date));
}

/** 期間全体の合計。 */
export function periodTotal(items: DaySummary[]): NutritionValues {
  return items.reduce((acc, item) => add(acc, toValues(item)), ZERO_VALUES);
}

/** 1日平均（期間合計 ÷ 対象日数）。dayCount は記録の有無に依らない母数。 */
export function dailyAverage(items: DaySummary[], dayCount: number): NutritionValues {
  if (dayCount <= 0) return ZERO_VALUES;
  const total = periodTotal(items);
  return {
    calories: total.calories / dayCount,
    protein: total.protein / dayCount,
    fat: total.fat / dayCount,
    netCarbs: total.netCarbs / dayCount,
    dietaryFiber: total.dietaryFiber / dayCount,
  };
}

/** 目標達成日数。各日の合計カロリーが目標 ±tolerance に収まる日を数える。 */
export function goalAchievedDays(
  items: DaySummary[],
  targetCalories: number,
  tolerance = 0.1
): number {
  if (targetCalories <= 0) return 0;
  const lower = targetCalories * (1 - tolerance);
  const upper = targetCalories * (1 + tolerance);
  return dailyTotals(items).filter(
    (d) => d.values.calories >= lower && d.values.calories <= upper
  ).length;
}

/** PFC のエネルギー比率（合計100%）。記録が無い/エネルギー0なら全て0。 */
export function pfcBalance(items: DaySummary[]): PFCBalance {
  const total = periodTotal(items);
  const pCal = total.protein * PROTEIN_KCAL;
  const fCal = total.fat * FAT_KCAL;
  const cCal = total.netCarbs * NET_CARBS_KCAL + total.dietaryFiber * FIBER_KCAL;
  const sum = pCal + fCal + cCal;
  if (sum <= 0) return ZERO_BALANCE;
  return { protein: (pCal / sum) * 100, fat: (fCal / sum) * 100, carbs: (cCal / sum) * 100 };
}

/** 食事タイプ別の合計。記録のないタイプはキーに含まれない。 */
export function mealTypeTotals(items: DaySummary[]): Record<string, NutritionValues> {
  const map: Record<string, NutritionValues> = {};
  for (const item of items) {
    map[item.mealType] = add(map[item.mealType] ?? ZERO_VALUES, toValues(item));
  }
  return map;
}
