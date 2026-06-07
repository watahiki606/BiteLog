import { Hono } from 'hono';
import type { Bindings, Variables, FoodMasterRow } from '../types';
import { foodMasterToResponse } from '../types';
import { authMiddleware } from '../middleware/auth';

const FM_SELECT = `
  fm.id, fm.brand_name, fm.product_name, fm.calories, fm.dietary_fiber,
  fm.net_carbs, fm.fat, fm.protein, fm.portion_size, fm.portion_unit, fm.unique_key, fm.created_by,
  COALESCE(ufs.usage_count, 0) as usage_count,
  ufs.last_used_date,
  COALESCE(ufs.last_number_of_servings, 1.0) as last_number_of_servings`;

const FM_JOIN = `FROM food_masters fm
  LEFT JOIN user_food_stats ufs ON ufs.food_master_id = fm.id AND ufs.user_id = ?`;

const foodMasters = new Hono<{ Bindings: Bindings; Variables: Variables }>()
  .use('*', authMiddleware)
  .get('/', async (c) => {
    const userId = c.get('userId');
    const q = c.req.query('q') ?? '';
    const limit = Math.min(parseInt(c.req.query('limit') ?? '20'), 500);
    const offset = parseInt(c.req.query('offset') ?? '0');
    const onlyMine = c.req.query('onlyMine') === 'true';

    let rows: FoodMasterRow[];
    let total: number;

    if (q) {
      const pattern = `%${q}%`;
      const mineClause = onlyMine ? 'AND fm.created_by = ?' : '';
      const mineBinds = onlyMine ? [userId] : [];
      const [dataResult, countResult] = await Promise.all([
        c.env.DB.prepare(
          `SELECT ${FM_SELECT} ${FM_JOIN}
           WHERE (fm.brand_name LIKE ? OR fm.product_name LIKE ?) ${mineClause}
           ORDER BY usage_count DESC, ufs.last_used_date DESC
           LIMIT ? OFFSET ?`
        ).bind(userId, pattern, pattern, ...mineBinds, limit, offset).all<FoodMasterRow>(),
        c.env.DB.prepare(
          `SELECT COUNT(*) as count FROM food_masters
           WHERE (brand_name LIKE ? OR product_name LIKE ?) ${mineClause}`
        ).bind(pattern, pattern, ...mineBinds).first<{ count: number }>(),
      ]);
      rows = dataResult.results;
      total = countResult?.count ?? 0;
    } else {
      const mineClause = onlyMine ? 'WHERE fm.created_by = ?' : '';
      const mineBinds = onlyMine ? [userId] : [];
      const countClause = onlyMine ? 'WHERE created_by = ?' : '';
      const [dataResult, countResult] = await Promise.all([
        c.env.DB.prepare(
          `SELECT ${FM_SELECT} ${FM_JOIN} ${mineClause}
           ORDER BY usage_count DESC, ufs.last_used_date DESC
           LIMIT ? OFFSET ?`
        ).bind(userId, ...mineBinds, limit, offset).all<FoodMasterRow>(),
        c.env.DB.prepare(`SELECT COUNT(*) as count FROM food_masters ${countClause}`)
          .bind(...mineBinds).first<{ count: number }>(),
      ]);
      rows = dataResult.results;
      total = countResult?.count ?? 0;
    }

    const isAdmin = c.get('isAdmin');
    return c.json({
      items: rows.map(r => ({
        ...foodMasterToResponse(r),
        isMine: r.created_by === userId,
        ...(isAdmin ? { createdBy: r.created_by } : {}),
      })),
      total,
      hasMore: offset + rows.length < total,
    });
  })
  .get('/:id', async (c) => {
    const userId = c.get('userId');
    const row = await c.env.DB.prepare(
      `SELECT ${FM_SELECT} ${FM_JOIN} WHERE fm.id = ?`
    ).bind(userId, c.req.param('id')).first<FoodMasterRow>();

    if (!row) return c.json({ error: 'Not found' }, 404);
    return c.json(foodMasterToResponse(row));
  })
  .post('/', async (c) => {
    const userId = c.get('userId');
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
         portion_size, portion_unit, unique_key, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(unique_key) DO NOTHING`
    ).bind(
      body.id, body.brandName, body.productName, body.calories,
      body.dietaryFiber, body.netCarbs, body.fat, body.protein,
      body.portionSize, body.portionUnit, body.uniqueKey, userId
    ).run();

    const row = await c.env.DB.prepare(
      `SELECT ${FM_SELECT} ${FM_JOIN} WHERE fm.unique_key = ?`
    ).bind(userId, body.uniqueKey).first<FoodMasterRow>();

    return c.json(foodMasterToResponse(row!), 201);
  })
  .post('/batch', async (c) => {
    const userId = c.get('userId');
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
           portion_size, portion_unit, unique_key, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(unique_key) DO NOTHING`
      ).bind(
        item.id, item.brandName, item.productName, item.calories,
        item.dietaryFiber, item.netCarbs, item.fat, item.protein,
        item.portionSize, item.portionUnit, item.uniqueKey, userId
      )
    );

    const results = await c.env.DB.batch(statements);
    const created = results.filter(r => r.meta.changes > 0).length;
    return c.json({ created, skipped: results.length - created, errors: 0 });
  })
  .put('/:id', async (c) => {
    const userId = c.get('userId');
    const isAdmin = c.get('isAdmin');

    const existing = await c.env.DB.prepare(
      `SELECT created_by FROM food_masters WHERE id = ?`
    ).bind(c.req.param('id')).first<{ created_by: string | null }>();

    if (!existing) return c.json({ error: 'Not found' }, 404);
    if (!isAdmin && existing.created_by !== userId) {
      return c.json({ error: 'Forbidden' }, 403);
    }

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
  })
  .delete('/all', async (c) => {
    if (!c.get('isAdmin')) return c.json({ error: 'Forbidden' }, 403);
    await c.env.DB.prepare(`DELETE FROM food_masters`).run();
    return c.json({ ok: true });
  })
  .delete('/:id', async (c) => {
    const id = c.req.param('id');

    const existing = await c.env.DB.prepare(
      `SELECT created_by FROM food_masters WHERE id = ?`
    ).bind(id).first<{ created_by: string | null }>();

    if (!existing) return c.json({ ok: true });
    if (!c.get('isAdmin') && existing.created_by !== c.get('userId')) {
      return c.json({ error: 'Forbidden' }, 403);
    }

    const { results: relatedLogs } = await c.env.DB.prepare(
      `SELECT li.*, fm.brand_name, fm.product_name, fm.calories,
              fm.dietary_fiber, fm.net_carbs, fm.fat, fm.protein,
              fm.portion_size, fm.portion_unit
       FROM log_items li
       JOIN food_masters fm ON fm.id = li.food_master_id
       WHERE li.food_master_id = ? AND li.is_master_deleted = 0`
    ).bind(id).all<any>();

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
