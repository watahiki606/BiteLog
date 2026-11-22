import { Hono } from 'hono';
import type { Bindings, Variables, FoodMasterRow } from '../types';
import { foodMasterToResponse } from '../types';
import { authMiddleware } from '../middleware/auth';
import { nutrientsFromRow } from '../lib/nutrients';
import { FM_NUTRIENT_SELECT, insertFoodMaster, nutrientUpdate, type FoodMasterInput } from '../lib/foodMasterSql';

const FM_SELECT = `
  fm.id, fm.brand_name, fm.product_name, ${FM_NUTRIENT_SELECT},
  fm.portion_size, fm.portion_unit, fm.unique_key, fm.created_by,
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

    // 「スシロー サーモン」のように店名と品名を並べて探せるよう、語ごとにブランド名か商品名に含まれることを求める
    const words = q.split(/\s+/).filter(Boolean);
    const conditions: string[] = [];
    const binds: string[] = [];
    for (const word of words) {
      // LIKE は D1 でパターン長に上限があり、長い商品名で探すと SQL がエラーになる。
      // instr なら長さの上限が無い。lower で英字の大文字小文字を区別しない点は LIKE と同じにする
      conditions.push('(instr(lower(fm.brand_name), lower(?)) > 0 OR instr(lower(fm.product_name), lower(?)) > 0)');
      binds.push(word, word);
    }
    if (onlyMine) {
      conditions.push('fm.created_by = ?');
      binds.push(userId);
    }
    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const [dataResult, countResult] = await Promise.all([
      c.env.DB.prepare(
        `SELECT ${FM_SELECT} ${FM_JOIN} ${where}
         ORDER BY usage_count DESC, ufs.last_used_date DESC
         LIMIT ? OFFSET ?`
      ).bind(userId, ...binds, limit, offset).all<FoodMasterRow>(),
      c.env.DB.prepare(`SELECT COUNT(*) as count FROM food_masters fm ${where}`)
        .bind(...binds).first<{ count: number }>(),
    ]);
    const rows = dataResult.results;
    const total = countResult?.count ?? 0;

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
    const body = await c.req.json<FoodMasterInput & { onConflict?: 'reject' }>();

    await insertFoodMaster(c.env.DB, body, userId).run();

    const row = await c.env.DB.prepare(
      `SELECT ${FM_SELECT} ${FM_JOIN} WHERE fm.unique_key = ?`
    ).bind(userId, body.uniqueKey).first<FoodMasterRow>();
    const existing = foodMasterToResponse(row!);

    // 別の食品を返すと、呼ぶ側は送った値で作れたと思い込み、その値で記録してしまう。
    // 既存の食品の値を書き換えるとそれを参照する他の人の記録まで変わるので、上書きもしない。
    // 同じ id なら送り直しなので、作れたものとして返す。
    // 409 は onConflict: 'reject' を送ってきたときだけ返す。公開中の古い版のアプリは
    // 409 を扱えず、名前が重なった食品を保存できなくなるため、印が無ければ既存の食品を返す。
    const isAnotherFood = existing.id.toLowerCase() !== body.id.toLowerCase();
    if (body.onConflict === 'reject' && isAnotherFood) {
      return c.json({ error: 'A food with the same brand, name and unit already exists', existing }, 409);
    }
    return c.json(existing, 201);
  })
  .post('/batch', async (c) => {
    const userId = c.get('userId');
    const body = await c.req.json<{ items: FoodMasterInput[] }>();

    const statements = body.items.map(item => insertFoodMaster(c.env.DB, item, userId));

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

    const body = await c.req.json<Partial<FoodMasterInput>>();
    const nutrients = nutrientUpdate(body);

    await c.env.DB.prepare(
      `UPDATE food_masters SET
        brand_name = COALESCE(?, brand_name),
        product_name = COALESCE(?, product_name),
        ${nutrients.sql},
        portion_size = COALESCE(?, portion_size),
        portion_unit = COALESCE(?, portion_unit)
       WHERE id = ?`
    ).bind(
      body.brandName ?? null, body.productName ?? null, ...nutrients.binds,
      body.portionSize ?? null, body.portionUnit ?? null,
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
      `SELECT li.*, fm.brand_name, fm.product_name, ${FM_NUTRIENT_SELECT},
              fm.portion_size, fm.portion_unit
       FROM log_items li
       JOIN food_masters fm ON fm.id = li.food_master_id
       WHERE li.food_master_id = ? AND li.is_master_deleted = 0`
    ).bind(id).all<any>();

    for (const log of relatedLogs) {
      const snapshot = JSON.stringify({
        brandName: log.brand_name,
        productName: log.product_name,
        ...nutrientsFromRow(log),
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
