import useSWR from 'swr';
import { createClient } from '@/lib/api';

export interface NutritionSource {
  productName: string;
  brandName: string;
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
  portionSize: number;
}

export interface LogItem {
  id: string;
  timestamp: string;
  mealType: string;
  numberOfServings: number;
  isMasterDeleted: boolean;
  foodMaster: NutritionSource | null;
  nutritionSnapshot: NutritionSource | null;
}

async function fetchLogItems([, logDate]: [string, string]): Promise<LogItem[]> {
  const res = await createClient().api['log-items'].$get({ query: { logDate } });
  if (!res.ok) throw new Error('log-items');
  const data = await res.json();
  return data.items as LogItem[];
}

/** 指定日の食事ログ。date が SWR キーなので、日付変更で自動再取得される。 */
export function useLogItems(date: string, onError: () => void) {
  return useSWR<LogItem[]>(['log-items', date], fetchLogItems, {
    revalidateOnFocus: false,
    onError,
  });
}
