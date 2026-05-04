import { Hono } from 'hono';
import type { Bindings, Variables, LogItemRow, FoodMasterRow } from '../types';
import { logItemToResponse } from '../types';
import { authMiddleware } from '../middleware/auth';

const logItems = new Hono<{ Bindings: Bindings; Variables: Variables }>();
logItems.use('*', authMiddleware);

type LogItemJoinRow = LogItemRow & {
  fm_id: string | null;
  brand_name: string | null;
  product_name: string | null;
  calories: number | null;
  dietary_fiber: number | null;
  net_carbs: number | null;
  fat: number | null;
  protein: number | null;
  portion_size: number | null;
  portion_unit: string | null;
  unique_key: string | null;
  usage_count: number | null;
  last_used_date: string | null;
  last_number_of_servings: number | null;
};

function rowToFm(row: LogItemJoinRow): FoodMasterRow | null {
  if (!row.fm_id) return null;
  return {
    id: row.fm_id,
    brand_name: row.brand_name!,
    product_name: row.product_name!,
    calories: row.calories!,
    dietary_fiber: row.dietary_fiber!,
    net_carbs: row.net_carbs!,
    fat: row.fat!,
    protein: row.protein!,
    portion_size: row.portion_size!,
    portion_unit: row.portion_unit!,
    unique_key: row.unique_key!,
    usage_count: row.usage_count!,
    last_used_date: row.last_used_date,
    last_number_of_servings: row.last_number_of_servings!,
  };
}

const JOIN_SELECT = `SELECT li.*, fm.id as fm_id, fm.brand_name, fm.product_name, fm.calories,
        fm.dietary_fiber, fm.net_carbs, fm.fat, fm.protein,
        fm.portion_size, fm.portion_unit, fm.unique_key,
        fm.usage_count, fm.last_used_date, fm.last_number_of_servings
 FROM log_items li
 LEFT JOIN food_masters fm ON fm.id = li.food_master_id`;

// GET /api/log-items?logDate=yyyy-MM-dd  OR  ?limit=N&offset=N (export all)
logItems.get('/', async (c) => {
  const userId = c.get('userId');
  const logDate = c.req.query('logDate');
  const limit = parseInt(c.req.query('limit') ?? '0');
  const offset = parseInt(c.req.query('offset') ?? '0');

  if (logDate) {
    // 通常の日付フィルタ
    const { results } = await c.env.DB.prepare(
      `${JOIN_SELECT} WHERE li.user_id = ? AND li.log_date = ? ORDER BY li.timestamp ASC`
    ).bind(userId, logDate).all<LogItemJoinRow>();

    const items = results.map(row => logItemToResponse(row, rowToFm(row)));
    return c.json({ items });
  } else {
    // エクスポート用: 全件 (limit/offset でページング)
    const pageLimit = limit > 0 ? Math.min(limit, 500) : 500;
    const { results } = await c.env.DB.prepare(
      `${JOIN_SELECT} WHERE li.user_id = ? ORDER BY li.timestamp DESC LIMIT ? OFFSET ?`
    ).bind(userId, pageLimit, offset).all<LogItemJoinRow>();

    const items = results.map(row => logItemToResponse(row, rowToFm(row)));
    return c.json({ items, hasMore: results.length === pageLimit });
  }
});

// POST /api/log-items
logItems.post('/', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{
    id: string;
    timestamp: string;
    logDate: string;
    mealType: string;
    numberOfServings: number;
    foodMasterId?: string;
    nutritionSnapshot?: object;
  }>();

  await c.env.DB.prepare(
    `INSERT INTO log_items
      (id, user_id, timestamp, log_date, meal_type, number_of_servings,
       food_master_id, nutrition_snapshot_json, is_master_deleted)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)`
  ).bind(
    body.id, userId, body.timestamp, body.logDate, body.mealType,
    body.numberOfServings, body.foodMasterId ?? null,
    body.nutritionSnapshot ? JSON.stringify(body.nutritionSnapshot) : null
  ).run();

  // usageCountをインクリメント
  if (body.foodMasterId) {
    await c.env.DB.prepare(
      `UPDATE food_masters SET
        usage_count = usage_count + 1,
        last_used_date = datetime('now'),
        last_number_of_servings = ?
       WHERE id = ?`
    ).bind(body.numberOfServings, body.foodMasterId).run();
  }

  // 作成したLogItemをJOINして返す
  const row = await c.env.DB.prepare(
    `SELECT li.*, fm.id as fm_id, fm.brand_name, fm.product_name, fm.calories,
            fm.dietary_fiber, fm.net_carbs, fm.fat, fm.protein,
            fm.portion_size, fm.portion_unit, fm.unique_key,
            fm.usage_count, fm.last_used_date, fm.last_number_of_servings
     FROM log_items li
     LEFT JOIN food_masters fm ON fm.id = li.food_master_id
     WHERE li.id = ?`
  ).bind(body.id).first<any>();

  const fm: FoodMasterRow | null = row?.fm_id ? {
    id: row.fm_id, brand_name: row.brand_name, product_name: row.product_name,
    calories: row.calories, dietary_fiber: row.dietary_fiber, net_carbs: row.net_carbs,
    fat: row.fat, protein: row.protein, portion_size: row.portion_size,
    portion_unit: row.portion_unit, unique_key: row.unique_key,
    usage_count: row.usage_count, last_used_date: row.last_used_date,
    last_number_of_servings: row.last_number_of_servings,
  } : null;

  return c.json(logItemToResponse(row, fm), 201);
});

// POST /api/log-items/batch（CSV用）
logItems.post('/batch', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{ items: Array<{
    id: string;
    timestamp: string;
    logDate: string;
    mealType: string;
    numberOfServings: number;
    foodMasterId?: string;
    nutritionSnapshot?: object;
  }> }>();

  const statements = body.items.map(item =>
    c.env.DB.prepare(
      `INSERT OR IGNORE INTO log_items
        (id, user_id, timestamp, log_date, meal_type, number_of_servings,
         food_master_id, nutrition_snapshot_json, is_master_deleted)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)`
    ).bind(
      item.id, userId, item.timestamp, item.logDate, item.mealType,
      item.numberOfServings, item.foodMasterId ?? null,
      item.nutritionSnapshot ? JSON.stringify(item.nutritionSnapshot) : null
    )
  );

  const results = await c.env.DB.batch(statements);
  const created = results.filter(r => r.meta.changes > 0).length;

  return c.json({ created, skipped: body.items.length - created, errors: 0 });
});

// DELETE /api/log-items/all（ユーザーの全ログ削除）
logItems.delete('/all', async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare(`DELETE FROM log_items WHERE user_id = ?`).bind(userId).run();
  return c.json({ ok: true });
});

// PUT /api/log-items/:id
logItems.put('/:id', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{
    numberOfServings?: number;
    mealType?: string;
    timestamp?: string;
  }>();

  const result = await c.env.DB.prepare(
    `UPDATE log_items SET
      number_of_servings = COALESCE(?, number_of_servings),
      meal_type = COALESCE(?, meal_type),
      timestamp = COALESCE(?, timestamp)
     WHERE id = ? AND user_id = ?`
  ).bind(
    body.numberOfServings ?? null, body.mealType ?? null,
    body.timestamp ?? null, c.req.param('id'), userId
  ).run();

  if (result.meta.changes === 0) return c.json({ error: 'Not found' }, 404);

  const row = await c.env.DB.prepare(
    `SELECT li.*, fm.id as fm_id, fm.brand_name, fm.product_name, fm.calories,
            fm.dietary_fiber, fm.net_carbs, fm.fat, fm.protein,
            fm.portion_size, fm.portion_unit, fm.unique_key,
            fm.usage_count, fm.last_used_date, fm.last_number_of_servings
     FROM log_items li
     LEFT JOIN food_masters fm ON fm.id = li.food_master_id
     WHERE li.id = ?`
  ).bind(c.req.param('id')).first<any>();

  const fm: FoodMasterRow | null = row?.fm_id ? {
    id: row.fm_id, brand_name: row.brand_name, product_name: row.product_name,
    calories: row.calories, dietary_fiber: row.dietary_fiber, net_carbs: row.net_carbs,
    fat: row.fat, protein: row.protein, portion_size: row.portion_size,
    portion_unit: row.portion_unit, unique_key: row.unique_key,
    usage_count: row.usage_count, last_used_date: row.last_used_date,
    last_number_of_servings: row.last_number_of_servings,
  } : null;

  return c.json(logItemToResponse(row, fm));
});

// DELETE /api/log-items/:id
logItems.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const id = c.req.param('id');

  // 削除前にfood_master_idを取得
  const existing = await c.env.DB.prepare(
    `SELECT food_master_id, is_master_deleted FROM log_items WHERE id = ? AND user_id = ?`
  ).bind(id, userId).first<{ food_master_id: string | null; is_master_deleted: number }>();

  if (!existing) return c.json({ error: 'Not found' }, 404);

  // usageCountをデクリメント（マスター未削除の場合のみ）
  if (existing.food_master_id && existing.is_master_deleted === 0) {
    await c.env.DB.prepare(
      `UPDATE food_masters SET usage_count = MAX(0, usage_count - 1) WHERE id = ?`
    ).bind(existing.food_master_id).run();
  }

  await c.env.DB.prepare(`DELETE FROM log_items WHERE id = ? AND user_id = ?`)
    .bind(id, userId).run();

  return c.json({ ok: true });
});

export default logItems;
