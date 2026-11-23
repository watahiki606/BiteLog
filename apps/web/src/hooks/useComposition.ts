import useSWR from 'swr';
import { createClient } from '@/lib/api';

/** 成分表の1食品。値は 100 g あたりで、未測定の栄養素はキーが無い */
export type CompositionFood = {
  foodNumber: string;
  foodGroup: string;
  name: string;
  edition: string;
  per100g: Record<string, number>;
};

async function searchComposition([, q]: [string, string]): Promise<CompositionFood[]> {
  const res = await createClient().api['composition-foods'].$get({ query: { q, limit: '20' } });
  if (!res.ok) throw new Error('composition-foods');
  return (await res.json()).items as CompositionFood[];
}

/** 成分表を名前で探す。空の検索語では探さない */
export function useCompositionSearch(q: string) {
  return useSWR<CompositionFood[]>(q.trim() ? ['composition-foods', q.trim()] : null, searchComposition, {
    revalidateOnFocus: false,
    keepPreviousData: true,
  });
}
