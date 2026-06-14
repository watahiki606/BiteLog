import { Hono } from 'hono';
import type { Bindings, Variables, LogItemRow, FoodMasterRow } from '../types';
import { logItemToResponse } from '../types';
import { authMiddleware } from '../middleware/auth';

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
  ufs_usage_count: number | null;
  ufs_last_used_date: string | null;
  ufs_last_number_of_servings: number | null;
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
    created_by: '',
    usage_count: row.ufs_usage_count ?? 0,
    last_used_date: row.ufs_last_used_date ?? null,
    last_number_of_servings: row.ufs_last_number_of_servings ?? 1.0,
  };
}

const JOIN_SELECT = `SELECT li.*, fm.id as fm_id, fm.brand_name, fm.product_name, fm.calories,
        fm.dietary_fiber, fm.net_carbs, fm.fat, fm.protein,
        fm.portion_size, fm.portion_unit, fm.unique_key,
        ufs.usage_count as ufs_usage_count,
        ufs.last_used_date as ufs_last_used_date,
        ufs.last_number_of_servings as ufs_last_number_of_servings
 FROM log_items li
 LEFT JOIN food_masters fm ON fm.id = li.food_master_id
 LEFT JOIN user_food_stats ufs ON ufs.food_master_id = li.food_master_id AND ufs.user_id = li.user_id`;

const logItems = new Hono<{ Bindings: Bindings; Variables: Variables }>()
  .use('*', authMiddleware)
  .get('/', async (c) => {
    const userId = c.get('userId');
    const logDate = c.req.query('logDate');
    const limit = parseInt(c.req.query('limit') ?? '0');
    const offset = parseInt(c.req.query('offset') ?? '0');

    if (logDate) {
      const { results } = await c.env.DB.prepare(
        `${JOIN_SELECT} WHERE li.user_id = ? AND li.log_date = ? ORDER BY li.timestamp ASC`
      ).bind(userId, logDate).all<LogItemJoinRow>();
      const items = results.map(row => logItemToResponse(row, rowToFm(row)));
      return c.json({ items });
    } else {
      const pageLimit = limit > 0 ? Math.min(limit, 500) : 500;
      const { results } = await c.env.DB.prepare(
        `${JOIN_SELECT} WHERE li.user_id = ? ORDER BY li.timestamp DESC LIMIT ? OFFSET ?`
      ).bind(userId, pageLimit, offset).all<LogItemJoinRow>();
      const items = results.map(row => logItemToResponse(row, rowToFm(row)));
      return c.json({ items, hasMore: results.length === pageLimit });
    }
  })
  // 統計タブ用の期間集計。日付×食事タイプごとの栄養合計を SQL 側で算出して返す。
  // 生ログを期間分そのまま返すと Worker の CPU 制限を超える（exceededCpu/503）ため、
  // 集計を D1 に寄せて返却行数と JS の処理量を最小化する。
  // 栄養値は iOS の NutritionSnapshot.scaled(by:) と同じく ratio = servings / portionSize で按分。
  // FoodMaster が結合できればそれを優先し、無ければ nutrition_snapshot_json を使う（iOS と同順）。
  .get('/summary', async (c) => {
    const userId = c.get('userId');
    const from = c.req.query('from');
    const to = c.req.query('to');
    if (!from || !to) {
      return c.json({ error: 'from and to are required' }, 400);
    }

    const { results } = await c.env.DB.prepare(
      `WITH base AS (
         SELECT li.log_date AS log_date, li.meal_type AS meal_type,
           li.number_of_servings AS s,
           COALESCE(fm.calories,      json_extract(li.nutrition_snapshot_json, '$.calories'))     AS cal,
           COALESCE(fm.protein,       json_extract(li.nutrition_snapshot_json, '$.protein'))      AS pro,
           COALESCE(fm.fat,           json_extract(li.nutrition_snapshot_json, '$.fat'))          AS fat,
           COALESCE(fm.net_carbs,     json_extract(li.nutrition_snapshot_json, '$.netCarbs'))     AS nc,
           COALESCE(fm.dietary_fiber, json_extract(li.nutrition_snapshot_json, '$.dietaryFiber')) AS fib,
           COALESCE(fm.portion_size,  json_extract(li.nutrition_snapshot_json, '$.portionSize'))  AS psize
         FROM log_items li
         LEFT JOIN food_masters fm ON fm.id = li.food_master_id
         WHERE li.user_id = ? AND li.log_date >= ? AND li.log_date <= ?
       )
       SELECT log_date, meal_type,
         SUM(CASE WHEN psize > 0 THEN cal * s / psize ELSE 0 END) AS calories,
         SUM(CASE WHEN psize > 0 THEN pro * s / psize ELSE 0 END) AS protein,
         SUM(CASE WHEN psize > 0 THEN fat * s / psize ELSE 0 END) AS fat,
         SUM(CASE WHEN psize > 0 THEN nc  * s / psize ELSE 0 END) AS netCarbs,
         SUM(CASE WHEN psize > 0 THEN fib * s / psize ELSE 0 END) AS dietaryFiber
       FROM base
       GROUP BY log_date, meal_type
       ORDER BY log_date ASC`
    ).bind(userId, from, to).all<{
      log_date: string; meal_type: string;
      calories: number; protein: number; fat: number; netCarbs: number; dietaryFiber: number;
    }>();

    const items = results.map(r => ({
      logDate: r.log_date,
      mealType: r.meal_type,
      calories: r.calories ?? 0,
      protein: r.protein ?? 0,
      fat: r.fat ?? 0,
      netCarbs: r.netCarbs ?? 0,
      dietaryFiber: r.dietaryFiber ?? 0,
    }));
    return c.json({ items });
  })
  .post('/', async (c) => {
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

    if (body.foodMasterId) {
      await c.env.DB.prepare(
        `INSERT INTO user_food_stats (user_id, food_master_id, usage_count, last_used_date, last_number_of_servings)
         VALUES (?, ?, 1, datetime('now'), ?)
         ON CONFLICT(user_id, food_master_id) DO UPDATE SET
           usage_count = usage_count + 1,
           last_used_date = datetime('now'),
           last_number_of_servings = excluded.last_number_of_servings`
      ).bind(userId, body.foodMasterId, body.numberOfServings).run();
    }

    const row = await c.env.DB.prepare(
      `${JOIN_SELECT} WHERE li.id = ?`
    ).bind(body.id).first<LogItemJoinRow>();

    return c.json(logItemToResponse(row!, rowToFm(row!)), 201);
  })
  .post('/batch', async (c) => {
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
  })
  .delete('/all', async (c) => {
    const userId = c.get('userId');
    await c.env.DB.batch([
      c.env.DB.prepare(`DELETE FROM log_items WHERE user_id = ?`).bind(userId),
      c.env.DB.prepare(`DELETE FROM user_food_stats WHERE user_id = ?`).bind(userId),
    ]);
    return c.json({ ok: true });
  })
  .put('/:id', async (c) => {
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
      `${JOIN_SELECT} WHERE li.id = ?`
    ).bind(c.req.param('id')).first<LogItemJoinRow>();

    return c.json(logItemToResponse(row!, rowToFm(row!)));
  })
  .delete('/:id', async (c) => {
    const userId = c.get('userId');
    const id = c.req.param('id');

    const existing = await c.env.DB.prepare(
      `SELECT food_master_id, is_master_deleted FROM log_items WHERE id = ? AND user_id = ?`
    ).bind(id, userId).first<{ food_master_id: string | null; is_master_deleted: number }>();

    if (!existing) return c.json({ error: 'Not found' }, 404);

    if (existing.food_master_id && existing.is_master_deleted === 0) {
      await c.env.DB.prepare(
        `UPDATE user_food_stats
         SET usage_count = MAX(0, usage_count - 1)
         WHERE user_id = ? AND food_master_id = ?`
      ).bind(userId, existing.food_master_id).run();
    }

    await c.env.DB.prepare(`DELETE FROM log_items WHERE id = ? AND user_id = ?`)
      .bind(id, userId).run();

    return c.json({ ok: true });
  });

export default logItems;
