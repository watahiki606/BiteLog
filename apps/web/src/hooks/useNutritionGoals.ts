import useSWR from 'swr';
import { createClient } from '@/lib/api';
import { PROTEIN_KCAL, FAT_KCAL, NET_CARBS_KCAL, FIBER_KCAL } from '@/lib/statistics';

/** API の /nutrition-goals が返す生の目標値。 */
export interface NutritionGoals {
  targetProtein: number;
  targetFat: number;
  targetNetCarbs: number;
  targetFiber: number;
}

export const ZERO_GOALS: NutritionGoals = {
  targetProtein: 0, targetFat: 0, targetNetCarbs: 0, targetFiber: 0,
};

/** 目標カロリー（iOS の targetCalories 式: P×4 + F×9 + netCarbs×4 + fiber×2）。 */
export function targetCalories(g: NutritionGoals): number {
  return Math.round(
    g.targetProtein * PROTEIN_KCAL + g.targetFat * FAT_KCAL +
    g.targetNetCarbs * NET_CARBS_KCAL + g.targetFiber * FIBER_KCAL
  );
}

async function fetchNutritionGoals(): Promise<NutritionGoals> {
  const res = await createClient().api['nutrition-goals'].$get();
  if (!res.ok) throw new Error('nutrition-goals');
  return await res.json() as NutritionGoals;
}

/**
 * 栄養目標。SWR キーは 'nutrition-goals' に統一しており、統計ページと目標ページで
 * 同一キャッシュを共有する（fetcher も1つだけ）。
 */
export function useNutritionGoals(onError?: () => void) {
  return useSWR<NutritionGoals>('nutrition-goals', fetchNutritionGoals, {
    revalidateOnFocus: false,
    onError,
  });
}
