import { Hono } from 'hono';
import type { Bindings, Variables, NutritionGoalsRow } from '../types';
import { authMiddleware } from '../middleware/auth';

const nutritionGoals = new Hono<{ Bindings: Bindings; Variables: Variables }>();
nutritionGoals.use('*', authMiddleware);

function goalsToResponse(row: NutritionGoalsRow) {
  return {
    targetProtein: row.target_protein,
    targetFat: row.target_fat,
    targetNetCarbs: row.target_net_carbs,
    targetFiber: row.target_fiber,
  };
}

// GET /api/nutrition-goals
nutritionGoals.get('/', async (c) => {
  const userId = c.get('userId');
  let row = await c.env.DB.prepare(
    `SELECT * FROM nutrition_goals WHERE user_id = ?`
  ).bind(userId).first<NutritionGoalsRow>();

  if (!row) {
    // 初回アクセス時にデフォルト値でレコードを作成
    await c.env.DB.prepare(
      `INSERT INTO nutrition_goals (user_id) VALUES (?)`
    ).bind(userId).run();
    row = await c.env.DB.prepare(
      `SELECT * FROM nutrition_goals WHERE user_id = ?`
    ).bind(userId).first<NutritionGoalsRow>();
  }

  return c.json(goalsToResponse(row!));
});

// PUT /api/nutrition-goals
nutritionGoals.put('/', async (c) => {
  const userId = c.get('userId');
  const body = await c.req.json<{
    targetProtein: number;
    targetFat: number;
    targetNetCarbs: number;
    targetFiber: number;
  }>();

  await c.env.DB.prepare(
    `INSERT INTO nutrition_goals (user_id, target_protein, target_fat, target_net_carbs, target_fiber)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       target_protein = excluded.target_protein,
       target_fat = excluded.target_fat,
       target_net_carbs = excluded.target_net_carbs,
       target_fiber = excluded.target_fiber`
  ).bind(userId, body.targetProtein, body.targetFat, body.targetNetCarbs, body.targetFiber).run();

  const row = await c.env.DB.prepare(
    `SELECT * FROM nutrition_goals WHERE user_id = ?`
  ).bind(userId).first<NutritionGoalsRow>();

  return c.json(goalsToResponse(row!));
});

export default nutritionGoals;
