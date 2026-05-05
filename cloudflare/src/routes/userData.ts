import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';

const userData = new Hono<{ Bindings: Bindings; Variables: Variables }>();
userData.use('*', authMiddleware);

// DELETE /api/user-data/all（管理者専用: 全ユーザーの全データを削除）
userData.delete('/all', async (c) => {
  if (!c.get('isAdmin')) return c.json({ error: 'Forbidden' }, 403);
  await c.env.DB.batch([
    c.env.DB.prepare(`DELETE FROM user_food_stats`),
    c.env.DB.prepare(`DELETE FROM log_items`),
    c.env.DB.prepare(`DELETE FROM food_masters`),
  ]);
  return c.json({ ok: true });
});

// DELETE /api/user-data（ユーザー自身の全データを削除）
// 削除順: user_food_stats → log_items → 孤立した food_masters
userData.delete('/', async (c) => {
  const userId = c.get('userId');

  await c.env.DB.batch([
    c.env.DB.prepare(`DELETE FROM user_food_stats WHERE user_id = ?`).bind(userId),
    c.env.DB.prepare(`DELETE FROM log_items WHERE user_id = ?`).bind(userId),
  ]);

  // 他のユーザーも参照していない孤立した food_masters を削除
  await c.env.DB.prepare(
    `DELETE FROM food_masters
     WHERE id NOT IN (
       SELECT DISTINCT food_master_id FROM log_items
       WHERE food_master_id IS NOT NULL
     )`
  ).run();

  return c.json({ ok: true });
});

export default userData;
