import useSWR from 'swr';
import { createClient } from '@/lib/api';

export interface FoodMaster {
  id: string;
  brandName: string;
  productName: string;
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
  portionSize: number;
  portionUnit: string;
  usageCount: number;
  isMine: boolean;
  createdBy?: string;
}

export const FOOD_MASTER_LIMIT = 30;

interface FoodMastersResult {
  items: FoodMaster[];
  total: number;
}

async function fetchFoodMasters(
  [, q, offset]: [string, string, number]
): Promise<FoodMastersResult> {
  const res = await createClient().api['food-masters'].$get({
    query: { q, limit: String(FOOD_MASTER_LIMIT), offset: String(offset) },
  });
  if (!res.ok) throw new Error('food-masters');
  const data = await res.json();
  return { items: data.items as FoodMaster[], total: data.total };
}

/** 検索語・オフセットを SWR キーにした食品マスタ一覧。前のページを保持しつつ再取得する。 */
export function useFoodMasters(q: string, offset: number, onError: () => void) {
  return useSWR<FoodMastersResult>(['food-masters', q, offset], fetchFoodMasters, {
    revalidateOnFocus: false,
    keepPreviousData: true,
    onError,
  });
}
