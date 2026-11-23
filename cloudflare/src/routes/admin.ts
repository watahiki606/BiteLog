// 管理者だけが使う。成分表とのひも付けの作業と、成分表の版を入れ替えたあとの計算し直し。
import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';
import { applyFoodComposition } from '../lib/foodCompositionDb';

const admin = new Hono<{ Bindings: Bindings; Variables: Variables }>()
  .use('*', authMiddleware)
  .use('*', async (c, next) => {
    if (!c.get('isAdmin')) return c.json({ error: 'Forbidden' }, 403);
    await next();
  })
  // ひも付けの無い食品を、全員の記録の数の多い順に返す。誰の記録かは返さない
  .get('/food-masters/unlinked', async (c) => {
    const limit = Math.min(Math.max(parseInt(c.req.query('limit') ?? '50') || 50, 1), 200);
    const offset = Math.max(parseInt(c.req.query('offset') ?? '0') || 0, 0);
    const { results } = await c.env.DB.prepare(
      `SELECT fm.id, fm.brand_name, fm.product_name, fm.portion_size, fm.portion_unit, COUNT(li.id) AS log_count
       FROM food_masters fm
       LEFT JOIN log_items li ON li.food_master_id = fm.id
       WHERE NOT EXISTS (SELECT 1 FROM food_master_components c WHERE c.food_master_id = fm.id)
       GROUP BY fm.id
       ORDER BY log_count DESC, fm.product_name
       LIMIT ? OFFSET ?`,
    ).bind(limit, offset).all<{
      id: string; brand_name: string; product_name: string; portion_size: number; portion_unit: string; log_count: number;
    }>();
    return c.json({
      items: results.map((r) => ({
        id: r.id, brandName: r.brand_name, productName: r.product_name,
        portionSize: r.portion_size, portionUnit: r.portion_unit, logCount: r.log_count,
      })),
    });
  })
  // ひも付けのある食品と、前に成分表で補った食品の値を計算し直す。成分表の版を入れ替えたあとに呼ぶ
  .post('/composition/recompute', async (c) => {
    const { results } = await c.env.DB.prepare(
      `SELECT DISTINCT food_master_id AS id FROM food_master_components
       UNION SELECT id FROM food_masters WHERE nutrient_sources IS NOT NULL`,
    ).all<{ id: string }>();
    for (const { id } of results) await applyFoodComposition(c.env.DB, id);
    return c.json({ recomputed: results.length });
  });

export default admin;
