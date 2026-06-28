import useSWR from 'swr';
import { createClient } from '@/lib/api';
import type { DailyStat } from '@/lib/correlation';

async function fetchDailyStats([, from, to]: [string, string, string]): Promise<DailyStat[]> {
  const res = await createClient().api.statistics.daily.$get({ query: { from, to } });
  if (!res.ok) throw new Error('statistics/daily');
  const data = await res.json();
  return data.items as DailyStat[];
}

/**
 * 表示レンジ [from, to] の日次サマリ（栄養合計＋体組成平均をサーバー側でマージ済み）を取得。
 * useSummary と同様、レンジを SWR キーにして ◀▶ のレンジ移動だけ再取得し、
 * bucket/metric 切替（同一レンジ）では再取得しない。
 */
export function useDailyStats(from: string, to: string, onError: () => void) {
  return useSWR<DailyStat[]>(['stats-daily', from, to], fetchDailyStats, {
    keepPreviousData: true,
    revalidateOnFocus: false,
    onError,
  });
}
