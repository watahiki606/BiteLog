import useSWR from 'swr';
import { createClient } from '@/lib/api';
import {
  PROTEIN_KCAL, FAT_KCAL, NET_CARBS_KCAL, FIBER_KCAL,
  type DaySummary,
} from '@/lib/statistics';

/** 栄養目標（カロリーは iOS の targetCalories 式で導出）。 */
export interface Goals {
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  fiber: number;
}

async function fetchSummary([, from, to]: [string, string, string]): Promise<DaySummary[]> {
  const res = await createClient().api['log-items'].summary.$get({ query: { from, to } });
  if (!res.ok) throw new Error('summary');
  const data = await res.json();
  return data.items as DaySummary[];
}

async function fetchGoals(): Promise<Goals> {
  const res = await createClient().api['nutrition-goals'].$get();
  if (!res.ok) throw new Error('goals');
  const g = await res.json() as {
    targetProtein: number; targetFat: number; targetNetCarbs: number; targetFiber: number;
  };
  return {
    calories: Math.round(
      g.targetProtein * PROTEIN_KCAL + g.targetFat * FAT_KCAL +
      g.targetNetCarbs * NET_CARBS_KCAL + g.targetFiber * FIBER_KCAL
    ),
    protein: g.targetProtein,
    fat: g.targetFat,
    netCarbs: g.targetNetCarbs,
    fiber: g.targetFiber,
  };
}

/**
 * 表示レンジ [from, to] の日次サマリを取得。レンジが SWR キーなので、
 * ◀▶ で別レンジに移ると自動でキャッシュ/再取得され、bucket/metric/aggregation の
 * 切替（同一レンジ）では再取得が走らない。
 */
export function useSummary(from: string, to: string, onError: () => void) {
  return useSWR<DaySummary[]>(['summary', from, to], fetchSummary, {
    keepPreviousData: true,
    revalidateOnFocus: false,
    onError,
  });
}

export function useGoals() {
  return useSWR<Goals>('nutrition-goals', fetchGoals, {
    revalidateOnFocus: false,
  });
}
