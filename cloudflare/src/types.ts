export type Bindings = {
  DB: D1Database;
  WORKER_JWT_SECRET: string;
  ADMIN_API_KEY: string;
  ADMIN_USER_ID: string;
};

export type Variables = {
  userId: string;
};

export type FoodMasterRow = {
  id: string;
  brand_name: string;
  product_name: string;
  calories: number;
  dietary_fiber: number;
  net_carbs: number;
  fat: number;
  protein: number;
  portion_size: number;
  portion_unit: string;
  unique_key: string;
  usage_count: number;
  last_used_date: string | null;
  last_number_of_servings: number;
};

export type LogItemRow = {
  id: string;
  user_id: string;
  timestamp: string;
  log_date: string;
  meal_type: string;
  number_of_servings: number;
  food_master_id: string | null;
  nutrition_snapshot_json: string | null;
  is_master_deleted: number;
};

export type NutritionGoalsRow = {
  user_id: string;
  target_protein: number;
  target_fat: number;
  target_net_carbs: number;
  target_fiber: number;
};

export function foodMasterToResponse(row: FoodMasterRow) {
  return {
    id: row.id,
    brandName: row.brand_name,
    productName: row.product_name,
    calories: row.calories,
    dietaryFiber: row.dietary_fiber,
    netCarbs: row.net_carbs,
    fat: row.fat,
    protein: row.protein,
    portionSize: row.portion_size,
    portionUnit: row.portion_unit,
    uniqueKey: row.unique_key,
    usageCount: row.usage_count,
    lastUsedDate: row.last_used_date,
    lastNumberOfServings: row.last_number_of_servings,
  };
}

export function logItemToResponse(row: LogItemRow, foodMaster?: FoodMasterRow | null) {
  return {
    id: row.id,
    timestamp: row.timestamp,
    logDate: row.log_date,
    mealType: row.meal_type,
    numberOfServings: row.number_of_servings,
    isMasterDeleted: row.is_master_deleted === 1,
    foodMaster: foodMaster ? foodMasterToResponse(foodMaster) : null,
    nutritionSnapshot: row.nutrition_snapshot_json
      ? JSON.parse(row.nutrition_snapshot_json)
      : null,
  };
}
