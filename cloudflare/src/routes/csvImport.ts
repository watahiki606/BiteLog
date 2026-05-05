import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';

const csvImport = new Hono<{ Bindings: Bindings; Variables: Variables }>();
csvImport.use('*', authMiddleware);

const VALID_MEAL_TYPES = new Set(['Breakfast', 'Lunch', 'Dinner', 'Snack', 'Other']);
const BATCH_SIZE = 100;

function parseCSVLine(line: string): string[] {
  const columns: string[] = [];
  let current = '';
  let inQuotes = false;
  for (const char of line) {
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      columns.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  columns.push(current.trim());
  return columns;
}

// "Meal Type" → "meal_type"、"brand_name" → "brand_name" に正規化
function normalizeHeader(h: string): string {
  return h.toLowerCase().replace(/[\s\-]+/g, '_');
}

function colIdx(headers: string[], ...candidates: string[]): number {
  for (const c of candidates) {
    const i = headers.indexOf(c);
    if (i >= 0) return i;
  }
  return -1;
}

// POST /api/csv/import
csvImport.post('/import', async (c) => {
  const userId = c.get('userId');
  const csvText = await c.req.text();

  const lines = csvText.split(/\r?\n/).filter(l => l.trim());
  if (lines.length < 2) return c.json({ error: 'CSV has no data rows' }, 400);

  const headers = parseCSVLine(lines[0]).map(normalizeHeader);

  // カラムインデックスを検出（フォールバックあり）
  const dateI        = colIdx(headers, 'date') >= 0               ? colIdx(headers, 'date')               : 0;
  const mealTypeI    = colIdx(headers, 'meal_type', 'mealtype') >= 0 ? colIdx(headers, 'meal_type', 'mealtype') : 1;
  const brandI       = colIdx(headers, 'brand_name', 'brand') >= 0   ? colIdx(headers, 'brand_name', 'brand')   : 2;
  const productI     = colIdx(headers, 'product_name', 'product') >= 0 ? colIdx(headers, 'product_name', 'product') : 3;
  const caloriesI    = colIdx(headers, 'calories') >= 0            ? colIdx(headers, 'calories')            : 4;
  const carbsI       = colIdx(headers, 'carbs') >= 0               ? colIdx(headers, 'carbs')               : 5;
  const fiberI       = colIdx(headers, 'dietary_fiber');
  const fatI         = colIdx(headers, 'fat') >= 0                 ? colIdx(headers, 'fat')                 : 6;
  const proteinI     = colIdx(headers, 'protein') >= 0             ? colIdx(headers, 'protein')             : 7;
  const portionAmtI  = colIdx(headers, 'portion_amount', 'portionamount') >= 0 ? colIdx(headers, 'portion_amount', 'portionamount') : 8;
  const portionUnitI = colIdx(headers, 'portion_unit', 'portionunit') >= 0  ? colIdx(headers, 'portion_unit', 'portionunit')  : 9;

  type FoodMasterData = {
    id: string; brandName: string; productName: string;
    calories: number; dietaryFiber: number; netCarbs: number;
    fat: number; protein: number; portionSize: number;
    portionUnit: string; uniqueKey: string;
  };

  type LogRow = {
    id: string; timestamp: string; logDate: string;
    mealType: string; numberOfServings: number;
    foodMasterUniqueKey: string; nutritionSnapshot: object;
  };

  const foodMasterMap = new Map<string, FoodMasterData>();
  const logRows: LogRow[] = [];
  let skipped = 0;

  for (const line of lines.slice(1)) {
    const cols = parseCSVLine(line);
    if (cols.length < 9) { skipped++; continue; }

    const dateStr  = cols[dateI]?.trim();
    const mealType = cols[mealTypeI]?.trim();
    if (!dateStr || !mealType || !VALID_MEAL_TYPES.has(mealType)) { skipped++; continue; }

    const date = new Date(dateStr + 'T00:00:00Z');
    if (isNaN(date.getTime())) { skipped++; continue; }

    const calories    = parseFloat(cols[caloriesI])    || 0;
    const carbs       = parseFloat(cols[carbsI])       || 0;
    const fiber       = fiberI >= 0 && fiberI < cols.length ? parseFloat(cols[fiberI]) || 0 : 0;
    const netCarbs    = Math.max(0, carbs - fiber);
    const fat         = parseFloat(cols[fatI])         || 0;
    const protein     = parseFloat(cols[proteinI])     || 0;
    const portionAmt  = parseFloat(cols[portionAmtI])  || 1.0;
    const portionUnit = cols[portionUnitI]?.trim()     || 'g';
    const brandName   = cols[brandI]?.trim()           || '';
    const productName = cols[productI]?.trim()         || '';
    const uniqueKey   = `${brandName}|${productName}|${portionUnit}`;

    if (!foodMasterMap.has(uniqueKey)) {
      foodMasterMap.set(uniqueKey, {
        id: crypto.randomUUID(), brandName, productName,
        calories, dietaryFiber: fiber, netCarbs, fat, protein,
        portionSize: portionAmt, portionUnit, uniqueKey,
      });
    }

    logRows.push({
      id: crypto.randomUUID(),
      timestamp: dateStr + 'T00:00:00.000Z',
      logDate: dateStr,
      mealType,
      numberOfServings: portionAmt,
      foodMasterUniqueKey: uniqueKey,
      nutritionSnapshot: {
        brandName, productName, calories, dietaryFiber: fiber,
        netCarbs, fat, protein, portionSize: portionAmt, portionUnit,
      },
    });
  }

  // 1. FoodMasters をバッチ挿入（100件ずつ）
  const foodMasters = [...foodMasterMap.values()];
  let foodMastersCreated = 0;
  for (let i = 0; i < foodMasters.length; i += BATCH_SIZE) {
    const chunk = foodMasters.slice(i, i + BATCH_SIZE);
    const results = await c.env.DB.batch(chunk.map(fm =>
      c.env.DB.prepare(
        `INSERT INTO food_masters
          (id, brand_name, product_name, calories, dietary_fiber, net_carbs, fat, protein,
           portion_size, portion_unit, unique_key, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(unique_key) DO NOTHING`
      ).bind(fm.id, fm.brandName, fm.productName, fm.calories, fm.dietaryFiber,
             fm.netCarbs, fm.fat, fm.protein, fm.portionSize, fm.portionUnit, fm.uniqueKey, userId)
    ));
    foodMastersCreated += results.filter(r => r.meta.changes > 0).length;
  }

  // 2. unique_key → id マップを取得（挿入済み含む既存全件）
  const { results: fmRows } = await c.env.DB.prepare(
    `SELECT id, unique_key FROM food_masters`
  ).all<{ id: string; unique_key: string }>();
  const fmIdMap = new Map(fmRows.map(r => [r.unique_key, r.id]));

  // 3. LogItems をバッチ挿入（100件ずつ）
  let created = 0;
  const affectedFoodMasterIds = new Set<string>();

  for (let i = 0; i < logRows.length; i += BATCH_SIZE) {
    const chunk = logRows.slice(i, i + BATCH_SIZE);
    const stmts: D1PreparedStatement[] = [];

    for (const row of chunk) {
      const fmId = fmIdMap.get(row.foodMasterUniqueKey);
      if (!fmId) { skipped++; continue; }
      affectedFoodMasterIds.add(fmId);
      stmts.push(
        c.env.DB.prepare(
          `INSERT OR IGNORE INTO log_items
            (id, user_id, timestamp, log_date, meal_type, number_of_servings,
             food_master_id, nutrition_snapshot_json, is_master_deleted)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)`
        ).bind(row.id, userId, row.timestamp, row.logDate, row.mealType,
               row.numberOfServings, fmId, JSON.stringify(row.nutritionSnapshot))
      );
    }

    if (stmts.length === 0) continue;
    const results = await c.env.DB.batch(stmts);
    created += results.filter(r => r.meta.changes > 0).length;
  }

  // 4. user_food_stats を一括UPSERT（全バッチ完了後に1回）
  const fmIds = [...affectedFoodMasterIds];
  for (let i = 0; i < fmIds.length; i += BATCH_SIZE) {
    await c.env.DB.batch(fmIds.slice(i, i + BATCH_SIZE).map(fmId =>
      c.env.DB.prepare(
        `INSERT INTO user_food_stats
          (user_id, food_master_id, usage_count, last_used_date, last_number_of_servings)
         SELECT ?, ?, COUNT(*), MAX(timestamp),
           (SELECT number_of_servings FROM log_items
            WHERE user_id = ? AND food_master_id = ?
            ORDER BY timestamp DESC LIMIT 1)
         FROM log_items
         WHERE user_id = ? AND food_master_id = ?
         ON CONFLICT(user_id, food_master_id) DO UPDATE SET
           usage_count = excluded.usage_count,
           last_used_date = excluded.last_used_date,
           last_number_of_servings = excluded.last_number_of_servings`
      ).bind(userId, fmId, userId, fmId, userId, fmId)
    ));
  }

  return c.json({ created, skipped, foodMastersCreated });
});

export default csvImport;
