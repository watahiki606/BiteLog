/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';

const TEST_SECRET = 'dev-and-test-secret';

beforeAll(() => applySchema(env.DB));

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM food_masters'),
  ]);
});

async function jwtFor(userId: string): Promise<string> {
  return issueSessionJwt(userId, TEST_SECRET);
}

function insertFoodMaster(
  id: string,
  vals: { calories?: number; protein?: number; fat?: number; netCarbs?: number; fiber?: number; portionSize?: number } = {}
) {
  return env.DB.prepare(
    `INSERT INTO food_masters
       (id, product_name, unique_key, created_by, calories, protein, fat, net_carbs, dietary_fiber, portion_size)
     VALUES (?, ?, ?, 'tester', ?, ?, ?, ?, ?, ?)`
  ).bind(
    id, `Food ${id}`, `|Food ${id}|g`,
    vals.calories ?? 0, vals.protein ?? 0, vals.fat ?? 0,
    vals.netCarbs ?? 0, vals.fiber ?? 0, vals.portionSize ?? 100
  );
}

function insertLogItemWithMaster(
  id: string, userId: string, logDate: string, mealType: string,
  foodMasterId: string, servings: number
) {
  return env.DB.prepare(
    `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type, number_of_servings, food_master_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(id, userId, `${logDate}T00:00:00Z`, logDate, mealType, servings, foodMasterId);
}

function insertLogItemWithSnapshot(
  id: string, userId: string, logDate: string, mealType: string,
  servings: number, snapshot: Record<string, unknown>
) {
  return env.DB.prepare(
    `INSERT INTO log_items
       (id, user_id, timestamp, log_date, meal_type, number_of_servings, food_master_id, nutrition_snapshot_json, is_master_deleted)
     VALUES (?, ?, ?, ?, ?, ?, NULL, ?, 1)`
  ).bind(id, userId, `${logDate}T00:00:00Z`, logDate, mealType, servings, JSON.stringify(snapshot));
}

type SummaryRow = {
  logDate: string; mealType: string;
  calories: number; protein: number; fat: number; netCarbs: number; dietaryFiber: number;
};

async function fetchSummary(userId: string, from: string, to: string) {
  return SELF.fetch(
    `http://localhost/api/log-items/summary?from=${from}&to=${to}`,
    { headers: { Authorization: `Bearer ${await jwtFor(userId)}` } }
  );
}

describe('GET /api/log-items/summary (期間集計)', () => {
  it('from/to が無ければ 400', async () => {
    const res = await SELF.fetch('http://localhost/api/log-items/summary', {
      headers: { Authorization: `Bearer ${await jwtFor('user-a')}` },
    });
    expect(res.status).toBe(400);
  });

  it('FoodMaster の栄養を servings/portionSize で按分して集計する', async () => {
    // calories=200/100g の食品を 50g 摂取 → 100kcal
    await insertFoodMaster('fm-1', { calories: 200, protein: 20, portionSize: 100 }).run();
    await insertLogItemWithMaster('li-1', 'user-a', '2024-01-01', 'Breakfast', 'fm-1', 50).run();

    const res = await fetchSummary('user-a', '2024-01-01', '2024-01-31');
    expect(res.status).toBe(200);
    const { items } = await res.json<{ items: SummaryRow[] }>();
    expect(items).toHaveLength(1);
    expect(items[0].calories).toBeCloseTo(100, 6);
    expect(items[0].protein).toBeCloseTo(10, 6);
  });

  it('同じ日・同じ食事タイプの複数ログを合算する', async () => {
    await insertFoodMaster('fm-1', { calories: 100, portionSize: 100 }).run();
    await env.DB.batch([
      insertLogItemWithMaster('li-1', 'user-a', '2024-01-01', 'Lunch', 'fm-1', 100),
      insertLogItemWithMaster('li-2', 'user-a', '2024-01-01', 'Lunch', 'fm-1', 50),
    ]);

    const res = await fetchSummary('user-a', '2024-01-01', '2024-01-31');
    const { items } = await res.json<{ items: SummaryRow[] }>();
    expect(items).toHaveLength(1);
    expect(items[0].mealType).toBe('Lunch');
    expect(items[0].calories).toBeCloseTo(150, 6); // 100 + 50
  });

  it('日付・食事タイプごとに行を分けて返す', async () => {
    await insertFoodMaster('fm-1', { calories: 100, portionSize: 100 }).run();
    await env.DB.batch([
      insertLogItemWithMaster('li-1', 'user-a', '2024-01-01', 'Breakfast', 'fm-1', 100),
      insertLogItemWithMaster('li-2', 'user-a', '2024-01-01', 'Dinner', 'fm-1', 100),
      insertLogItemWithMaster('li-3', 'user-a', '2024-01-02', 'Breakfast', 'fm-1', 100),
    ]);

    const res = await fetchSummary('user-a', '2024-01-01', '2024-01-31');
    const { items } = await res.json<{ items: SummaryRow[] }>();
    expect(items).toHaveLength(3);
    // log_date 昇順
    expect(items[0].logDate).toBe('2024-01-01');
    expect(items[2].logDate).toBe('2024-01-02');
  });

  it('FoodMaster が無いログは nutrition_snapshot_json を使う', async () => {
    await insertLogItemWithSnapshot('li-1', 'user-a', '2024-01-01', 'Snack', 50, {
      calories: 200, protein: 8, fat: 4, netCarbs: 10, dietaryFiber: 2, portionSize: 100,
    }).run();

    const res = await fetchSummary('user-a', '2024-01-01', '2024-01-31');
    const { items } = await res.json<{ items: SummaryRow[] }>();
    expect(items).toHaveLength(1);
    expect(items[0].calories).toBeCloseTo(100, 6); // 200 * 50/100
    expect(items[0].dietaryFiber).toBeCloseTo(1, 6); // 2 * 50/100
  });

  it('from〜to の範囲外は集計しない', async () => {
    await insertFoodMaster('fm-1', { calories: 100, portionSize: 100 }).run();
    await env.DB.batch([
      insertLogItemWithMaster('li-before', 'user-a', '2024-01-04', 'Breakfast', 'fm-1', 100),
      insertLogItemWithMaster('li-in', 'user-a', '2024-01-05', 'Breakfast', 'fm-1', 100),
      insertLogItemWithMaster('li-after', 'user-a', '2024-01-11', 'Breakfast', 'fm-1', 100),
    ]);

    const res = await fetchSummary('user-a', '2024-01-05', '2024-01-10');
    const { items } = await res.json<{ items: SummaryRow[] }>();
    expect(items.map(i => i.logDate)).toEqual(['2024-01-05']);
  });

  it('他ユーザーのログは集計に含めない', async () => {
    await insertFoodMaster('fm-1', { calories: 100, portionSize: 100 }).run();
    await env.DB.batch([
      insertLogItemWithMaster('li-a', 'user-a', '2024-01-01', 'Breakfast', 'fm-1', 100),
      insertLogItemWithMaster('li-b', 'user-b', '2024-01-01', 'Breakfast', 'fm-1', 100),
    ]);

    const res = await fetchSummary('user-a', '2024-01-01', '2024-01-31');
    const { items } = await res.json<{ items: SummaryRow[] }>();
    expect(items).toHaveLength(1);
    expect(items[0].calories).toBeCloseTo(100, 6);
  });
});

describe('PUT /api/log-items/:id と前回の量', () => {
  // 食品を選ぶと前回の量で記録する。選んでから量を直すのがふつうの使い方なので、
  // 直した量を前回の量にしないと、次も食品の分量で記録されてしまう
  const FM = 'fm-prev';

  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM user_food_stats').run();
    await insertFoodMaster(FM, { calories: 100, portionSize: 100 }).run();
  });

  async function call(userId: string, path: string, method: string, body?: unknown) {
    return SELF.fetch(`http://localhost${path}`, {
      method,
      headers: { Authorization: `Bearer ${await jwtFor(userId)}`, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  async function record(userId: string, id: string, servings: number) {
    const res = await call(userId, '/api/log-items', 'POST', {
      id, timestamp: '2026-11-24T08:00:00Z', logDate: '2026-11-24', mealType: 'Breakfast',
      numberOfServings: servings, foodMasterId: FM,
    });
    expect(res.status).toBe(201);
  }

  async function food(userId: string) {
    return (await call(userId, `/api/food-masters/${FM}`, 'GET')).json<{ usageCount: number; lastNumberOfServings: number }>();
  }

  it('記録の量を直すと、その食品の前回の量も直した量になる', async () => {
    await record('user-a', 'log-1', 100);

    const res = await call('user-a', '/api/log-items/log-1', 'PUT', { numberOfServings: 30 });

    expect(res.status).toBe(200);
    expect(await food('user-a')).toMatchObject({ usageCount: 1, lastNumberOfServings: 30 });
  });

  it('量を送らない直し方では、前回の量を変えない', async () => {
    await record('user-a', 'log-1', 40);

    await call('user-a', '/api/log-items/log-1', 'PUT', { mealType: 'Lunch' });

    expect(await food('user-a')).toMatchObject({ lastNumberOfServings: 40 });
  });

  it('ほかの人の前回の量は変えない', async () => {
    await record('user-a', 'log-a', 100);
    await record('user-b', 'log-b', 50);

    await call('user-a', '/api/log-items/log-a', 'PUT', { numberOfServings: 30 });

    expect(await food('user-b')).toMatchObject({ lastNumberOfServings: 50 });
  });

  it('ほかの人の記録は直せず、前回の量も変わらない', async () => {
    await record('user-a', 'log-a', 100);

    const res = await call('user-b', '/api/log-items/log-a', 'PUT', { numberOfServings: 30 });

    expect(res.status).toBe(404);
    expect(await food('user-a')).toMatchObject({ lastNumberOfServings: 100 });
  });
});
