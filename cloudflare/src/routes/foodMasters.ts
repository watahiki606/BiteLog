import { Hono } from 'hono';
import type { Bindings, Variables, FoodMasterRow } from '../types';
import { foodMasterToResponse } from '../types';
import { authMiddleware } from '../middleware/auth';

const foodMasters = new Hono<{ Bindings: Bindings; Variables: Variables }>();
foodMasters.use('*', authMiddleware);

// GET /api/food-masters?q=&limit=20&offset=0
foodMasters.get('/', async (c) => {
  const q = c.req.query('q') ?? '';
  const limit = Math.min(parseInt(c.req.query('limit') ?? '20'), 100);
  const offset = parseInt(c.req.query('offset') ?? '0');

  let rows: FoodMasterRow[];
  let total: number;

  if (q) {
    const pattern = `%${q}%`;
    const [dataResult, countResult] = await Promise.all([
      c.env.DB.prepare(
        `SELECT * FROM food_masters
         WHERE brand_name LIKE ?1 OR product_name LIKE ?1
         ORDER BY usage_count DESC, last_used_date DESC
         LIMIT ?2 OFFSET ?3`
      ).bind(pattern, limit, offset).all<FoodMasterRow>(),
      c.env.DB.prepare(
        `SELECT COUNT(*) as count FROM food_masters
         WHERE brand_name LIKE ?1 OR product_name LIKE ?1`
      ).bind(pattern).first<{ count: number }>(),
    ]);
    rows = dataResult.results;
    total = countResult?.count ?? 0;
  } else {
    const [dataResult, countResult] = await Promise.all([
      c.env.DB.prepare(
        `SELECT * FROM food_masters
         ORDER BY usage_count DESC, last_used_date DESC
         LIMIT ? OFFSET ?`
      ).bind(limit, offset).all<FoodMasterRow>(),
      c.env.DB.prepare(`SELECT COUNT(*) as count FROM food_masters`)
        .first<{ count: number }>(),
    ]);
    rows = dataResult.results;
    total = countResult?.count ?? 0;
  }

  return c.json({
    items: rows.map(foodMasterToResponse),
    total,
    hasMore: offset + rows.length < total,
  });
});

// GET /api/food-masters/:id
foodMasters.get('/:id', async (c) => {
  const row = await c.env.DB.prepare(
    `SELECT * FROM food_masters WHERE id = ?`
  ).bind(c.req.param('id')).first<FoodMasterRow>();

  if (!row) return c.json({ error: 'Not found' }, 404);
  return c.json(foodMasterToResponse(row));
});

// POST /api/food-masters
foodMasters.post('/', async (c) => {
  const body = await c.req.json<{
    id: string;
    brandName: string;
    productName: string;
    calories: number;
    dietaryFiber: number;
    netCarbs: number;
    fat: number;
    protein: number;
    portionSize: number;
    portionUnit: string;
    uniqueKey: string;
  }>();

  await c.env.DB.prepare(
    `INSERT INTO food_masters
      (id, brand_name, product_name, calories, dietary_fiber, net_carbs, fat, protein,
       portion_size, portion_unit, unique_key)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(unique_key) DO NOTHING`
  ).bind(
    body.id, body.brandName, body.productName, body.calories,
    body.dietaryFiber, body.netCarbs, body.fat, body.protein,
    body.portionSize, body.portionUnit, body.uniqueKey
  ).run();

  const row = await c.env.DB.prepare(
    `SELECT * FROM food_masters WHERE unique_key = ?`
  ).bind(body.uniqueKey).first<FoodMasterRow>();

  return c.json(foodMasterToResponse(row!), 201);
});

// POST /api/food-masters/batch（CSV用バッチ作成）
foodMasters.post('/batch', async (c) => {
  const body = await c.req.json<{ items: Array<{
    id: string;
    brandName: string;
    productName: string;
    calories: number;
    dietaryFiber: number;
    netCarbs: number;
    fat: number;
    protein: number;
    portionSize: number;
    portionUnit: string;
    uniqueKey: string;
  }> }>();

  const statements = body.items.map(item =>
    c.env.DB.prepare(
      `INSERT INTO food_masters
        (id, brand_name, product_name, calories, dietary_fiber, net_carbs, fat, protein,
         portion_size, portion_unit, unique_key)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(unique_key) DO NOTHING`
    ).bind(
      item.id, item.brandName, item.productName, item.calories,
      item.dietaryFiber, item.netCarbs, item.fat, item.protein,
      item.portionSize, item.portionUnit, item.uniqueKey
    )
  );

  const results = await c.env.DB.batch(statements);
  const created = results.filter(r => r.meta.changes > 0).length;
  const skipped = results.length - created;

  return c.json({ created, skipped, errors: 0 });
});

// PUT /api/food-masters/:id
foodMasters.put('/:id', async (c) => {
  const body = await c.req.json<Partial<{
    brandName: string;
    productName: string;
    calories: number;
    dietaryFiber: number;
    netCarbs: number;
    fat: number;
    protein: number;
    portionSize: number;
    portionUnit: string;
  }>>();

  await c.env.DB.prepare(
    `UPDATE food_masters SET
      brand_name = COALESCE(?, brand_name),
      product_name = COALESCE(?, product_name),
      calories = COALESCE(?, calories),
      dietary_fiber = COALESCE(?, dietary_fiber),
      net_carbs = COALESCE(?, net_carbs),
      fat = COALESCE(?, fat),
      protein = COALESCE(?, protein),
      portion_size = COALESCE(?, portion_size),
      portion_unit = COALESCE(?, portion_unit)
     WHERE id = ?`
  ).bind(
    body.brandName ?? null, body.productName ?? null, body.calories ?? null,
    body.dietaryFiber ?? null, body.netCarbs ?? null, body.fat ?? null,
    body.protein ?? null, body.portionSize ?? null, body.portionUnit ?? null,
    c.req.param('id')
  ).run();

  const row = await c.env.DB.prepare(
    `SELECT * FROM food_masters WHERE id = ?`
  ).bind(c.req.param('id')).first<FoodMasterRow>();

  if (!row) return c.json({ error: 'Not found' }, 404);
  return c.json(foodMasterToResponse(row));
});

// PUT /api/food-masters/:id/usage（usageCount更新）
foodMasters.put('/:id/usage', async (c) => {
  const { servings } = await c.req.json<{ servings: number }>();
  await c.env.DB.prepare(
    `UPDATE food_masters SET
      usage_count = usage_count + 1,
      last_used_date = datetime('now'),
      last_number_of_servings = ?
     WHERE id = ?`
  ).bind(servings, c.req.param('id')).run();
  return c.json({ ok: true });
});

// DELETE /api/food-masters/all（全件削除）
foodMasters.delete('/all', async (c) => {
  await c.env.DB.prepare(`DELETE FROM food_masters`).run();
  return c.json({ ok: true });
});

// DELETE /api/food-masters/:id（安全削除: 関連LogItemをスナップショット化）
foodMasters.delete('/:id', async (c) => {
  const id = c.req.param('id');

  // 関連する未削除のLogItemを取得
  const { results: relatedLogs } = await c.env.DB.prepare(
    `SELECT li.*, fm.brand_name, fm.product_name, fm.calories,
            fm.dietary_fiber, fm.net_carbs, fm.fat, fm.protein,
            fm.portion_size, fm.portion_unit
     FROM log_items li
     JOIN food_masters fm ON fm.id = li.food_master_id
     WHERE li.food_master_id = ? AND li.is_master_deleted = 0`
  ).bind(id).all<any>();

  // 各LogItemにスナップショットを保存
  for (const log of relatedLogs) {
    const snapshot = JSON.stringify({
      brandName: log.brand_name,
      productName: log.product_name,
      calories: log.calories,
      dietaryFiber: log.dietary_fiber,
      netCarbs: log.net_carbs,
      fat: log.fat,
      protein: log.protein,
      portionSize: log.portion_size,
      portionUnit: log.portion_unit,
    });
    await c.env.DB.prepare(
      `UPDATE log_items SET nutrition_snapshot_json = ?, is_master_deleted = 1, food_master_id = NULL WHERE id = ?`
    ).bind(snapshot, log.id).run();
  }

  await c.env.DB.prepare(`DELETE FROM food_masters WHERE id = ?`).bind(id).run();
  return c.json({ ok: true });
});

export default foodMasters;
