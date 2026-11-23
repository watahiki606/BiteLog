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

/** 食品にひも付けた成分表の食品と重さ */
export type FoodComponent = { foodNumber: string; grams: number; name: string | null };

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

export type FoodDetail = { components: FoodComponent[]; nutrientSources: Record<string, string> };

async function fetchFoodDetail([, id]: [string, string]): Promise<FoodDetail> {
  const res = await createClient().api['food-masters'][':id'].$get({ param: { id } });
  if (!res.ok) throw new Error('food-master');
  const body = (await res.json()) as Partial<FoodDetail>;
  return { components: body.components ?? [], nutrientSources: body.nutrientSources ?? {} };
}

/** 食品のひも付けと、栄養素ごとの出典。一覧には付かないので、編集を開いたときに読む */
export function useFoodDetail(id: string | null) {
  return useSWR<FoodDetail>(id ? ['food-master-detail', id] : null, fetchFoodDetail, { revalidateOnFocus: false });
}
