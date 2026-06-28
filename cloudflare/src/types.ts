export type Bindings = {
  DB: D1Database;
  WORKER_JWT_SECRET: string;
  ADMIN_USER_ID: string;
  GOOGLE_CLIENT_ID: string;
  // Web管理画面のソーシャルログイン用（未設定の場合はWebからのサインイン不可）
  GOOGLE_WEB_CLIENT_ID?: string;
  APPLE_WEB_SERVICE_ID?: string;
  OPENAI_API_KEY: string;
};

export type Variables = {
  userId: string;
  isAdmin: boolean;
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
  created_by: string | null;
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

export type BodyMeasurementRow = {
  id: string;
  user_id: string;
  source_date: string | null;
  measured_at: string;
  measurement_date_raw: string | null;
  measurement_time_raw: string | null;
  measurement_index: number | null;
  item_count: number | null;
  input_method: string | null;
  weight_kg: number | null;
  body_fat_percent: number | null;
  muscle_mass_kg: number | null;
  muscle_score: number | null;
  visceral_fat_level: number | null;
  basal_metabolism_kcal: number | null;
  metabolic_age: number | null;
  bone_mass_kg: number | null;
  body_water_percent: number | null;
  page_url: string | null;
};

export function bodyMeasurementToResponse(row: BodyMeasurementRow) {
  return {
    id: row.id,
    sourceDate: row.source_date,
    measuredAt: row.measured_at,
    measurementDateRaw: row.measurement_date_raw,
    measurementTimeRaw: row.measurement_time_raw,
    measurementIndex: row.measurement_index,
    itemCount: row.item_count,
    inputMethod: row.input_method,
    weightKg: row.weight_kg,
    bodyFatPercent: row.body_fat_percent,
    muscleMassKg: row.muscle_mass_kg,
    muscleScore: row.muscle_score,
    visceralFatLevel: row.visceral_fat_level,
    basalMetabolismKcal: row.basal_metabolism_kcal,
    metabolicAge: row.metabolic_age,
    boneMassKg: row.bone_mass_kg,
    bodyWaterPercent: row.body_water_percent,
    pageUrl: row.page_url,
  };
}

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
    lastUsedDate: row.last_used_date ? row.last_used_date.replace(' ', 'T') + 'Z' : null,
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
