import { getToken, getApiUrl } from './auth';

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const res = await fetch(`${getApiUrl()}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${getToken()}`,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json() as Promise<T>;
}

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
  uniqueKey: string;
  usageCount: number;
  createdBy?: string;
}

export interface LogItem {
  id: string;
  timestamp: string;
  logDate: string;
  mealType: string;
  numberOfServings: number;
  isMasterDeleted: boolean;
  foodMaster: Pick<FoodMaster, 'productName' | 'brandName' | 'calories' | 'protein' | 'fat' | 'netCarbs' | 'dietaryFiber' | 'portionSize' | 'portionUnit'> | null;
  nutritionSnapshot: (Pick<FoodMaster, 'productName' | 'brandName' | 'calories' | 'protein' | 'fat' | 'netCarbs' | 'dietaryFiber' | 'portionSize' | 'portionUnit'>) | null;
}

export interface NutritionGoals {
  targetProtein: number;
  targetFat: number;
  targetNetCarbs: number;
  targetFiber: number;
}

export const api = {
  foodMasters: {
    list: (q: string, limit: number, offset: number) =>
      request<{ items: FoodMaster[]; total: number; hasMore: boolean }>(
        `/api/food-masters?q=${encodeURIComponent(q)}&limit=${limit}&offset=${offset}`
      ),
    create: (data: Omit<FoodMaster, 'usageCount' | 'createdBy'>) =>
      request<FoodMaster>('/api/food-masters', { method: 'POST', body: JSON.stringify(data) }),
    update: (id: string, data: Partial<Omit<FoodMaster, 'id' | 'usageCount' | 'createdBy'>>) =>
      request<FoodMaster>(`/api/food-masters/${id}`, { method: 'PUT', body: JSON.stringify(data) }),
    delete: (id: string) =>
      request<{ ok: boolean }>(`/api/food-masters/${id}`, { method: 'DELETE' }),
  },
  logItems: {
    listByDate: (logDate: string) =>
      request<{ items: LogItem[] }>(`/api/log-items?logDate=${logDate}`),
    delete: (id: string) =>
      request<{ ok: boolean }>(`/api/log-items/${id}`, { method: 'DELETE' }),
  },
  nutritionGoals: {
    get: () => request<NutritionGoals>('/api/nutrition-goals'),
    update: (data: NutritionGoals) =>
      request<NutritionGoals>('/api/nutrition-goals', { method: 'PUT', body: JSON.stringify(data) }),
  },
};
