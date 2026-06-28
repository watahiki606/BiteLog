import useSWR from 'swr';
import { createClient } from '@/lib/api';
import type { DaySummary } from '@/lib/statistics';

async function fetchSummary([, from, to]: [string, string, string]): Promise<DaySummary[]> {
  const res = await createClient().api['log-items'].summary.$get({ query: { from, to } });
  if (!res.ok) throw new Error('summary');
  const data = await res.json();
  return data.items as DaySummary[];
}

/**
 * 表示レンジ [from, to] の日次サマリを取得。レンジが SWR キーなので、
 * ◀▶ で別レンジに移ると自動でキャッシュ/再取得され、bucket/metric/aggregation の
 * 切替（同一レンジ）では再取得が走らない。
 *
 * 栄養目標は useNutritionGoals に統一（同じ 'nutrition-goals' キャッシュを共有）。
 */
export function useSummary(from: string, to: string, onError: () => void) {
  return useSWR<DaySummary[]>(['summary', from, to], fetchSummary, {
    keepPreviousData: true,
    revalidateOnFocus: false,
    onError,
  });
}
