/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';

const TEST_SECRET = 'dev-and-test-secret';

beforeAll(async () => {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS food_masters (
      id TEXT PRIMARY KEY COLLATE NOCASE,
      brand_name TEXT NOT NULL DEFAULT '',
      product_name TEXT NOT NULL,
      calories REAL NOT NULL DEFAULT 0,
      dietary_fiber REAL NOT NULL DEFAULT 0,
      net_carbs REAL NOT NULL DEFAULT 0,
      fat REAL NOT NULL DEFAULT 0,
      protein REAL NOT NULL DEFAULT 0,
      portion_size REAL NOT NULL DEFAULT 1.0,
      portion_unit TEXT NOT NULL DEFAULT 'g',
      unique_key TEXT NOT NULL UNIQUE,
      created_by TEXT NOT NULL
    )`
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS log_items (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      log_date TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      number_of_servings REAL NOT NULL DEFAULT 1.0,
      food_master_id TEXT COLLATE NOCASE REFERENCES food_masters(id) ON DELETE SET NULL,
      nutrition_snapshot_json TEXT,
      is_master_deleted INTEGER NOT NULL DEFAULT 0
    )`
  ).run();
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS body_measurements (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      source_date TEXT,
      measured_at TEXT NOT NULL,
      measurement_date_raw TEXT,
      measurement_time_raw TEXT,
      measurement_index INTEGER,
      item_count INTEGER,
      input_method TEXT,
      weight_kg REAL,
      body_fat_percent REAL,
      muscle_mass_kg REAL,
      muscle_score REAL,
      visceral_fat_level REAL,
      basal_metabolism_kcal REAL,
      metabolic_age INTEGER,
      bone_mass_kg REAL,
      body_water_percent REAL,
      page_url TEXT,
      UNIQUE(user_id, measured_at)
    )`
  ).run();
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM food_masters'),
    env.DB.prepare('DELETE FROM body_measurements'),
  ]);
});

async function jwtFor(userId: string): Promise<string> {
  return issueSessionJwt(userId, TEST_SECRET);
}

async function authedFetch(userId: string, path: string) {
  return SELF.fetch(`http://localhost${path}`, {
    headers: { Authorization: `Bearer ${await jwtFor(userId)}` },
  });
}

function insertFoodMaster(id: string, vals: { calories?: number; protein?: number; portionSize?: number } = {}) {
  return env.DB.prepare(
    `INSERT INTO food_masters
       (id, product_name, unique_key, created_by, calories, protein, fat, net_carbs, dietary_fiber, portion_size)
     VALUES (?, ?, ?, 'tester', ?, ?, 0, 0, 0, ?)`
  ).bind(id, `Food ${id}`, `|Food ${id}|g`, vals.calories ?? 0, vals.protein ?? 0, vals.portionSize ?? 100);
}

function insertLog(id: string, userId: string, logDate: string, foodMasterId: string, servings: number) {
  return env.DB.prepare(
    `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type, number_of_servings, food_master_id)
     VALUES (?, ?, ?, ?, 'Breakfast', ?, ?)`
  ).bind(id, userId, `${logDate}T00:00:00Z`, logDate, servings, foodMasterId);
}

function insertBody(id: string, userId: string, measuredAt: string, weightKg: number, bodyFat?: number) {
  return env.DB.prepare(
    `INSERT INTO body_measurements (id, user_id, measured_at, weight_kg, body_fat_percent)
     VALUES (?, ?, ?, ?, ?)`
  ).bind(id, userId, measuredAt, weightKg, bodyFat ?? null);
}

type DailyRow = {
  date: string;
  calories: number; protein: number; fat: number; netCarbs: number; dietaryFiber: number;
  weightKg: number | null; bodyFatPercent: number | null;
};

async function getDaily(userId: string, from: string, to: string): Promise<DailyRow[]> {
  const res = await authedFetch(userId, `/api/statistics/daily?from=${from}&to=${to}`);
  expect(res.status).toBe(200);
  const { items } = await res.json<{ items: DailyRow[] }>();
  return items;
}

describe('認証', () => {
  it('未認証は 401', async () => {
    const res = await SELF.fetch('http://localhost/api/statistics/daily?from=2025-01-01&to=2025-01-31');
    expect(res.status).toBe(401);
  });
});

describe('GET /api/statistics/daily', () => {
  it('from/to が無ければ 400', async () => {
    const res = await authedFetch('user-a', '/api/statistics/daily');
    expect(res.status).toBe(400);
  });

  it('栄養と体組成が同じ日でマージされる', async () => {
    await env.DB.batch([
      insertFoodMaster('f1', { calories: 200, protein: 10, portionSize: 1 }),
      insertLog('l1', 'user-a', '2025-01-05', 'f1', 1),
      insertBody('b1', 'user-a', '2025-01-05T09:00:00.000Z', 50.0, 20.0),
    ]);
    const items = await getDaily('user-a', '2025-01-01', '2025-01-31');
    expect(items).toHaveLength(1);
    expect(items[0].date).toBe('2025-01-05');
    expect(items[0].calories).toBe(200);
    expect(items[0].protein).toBe(10);
    expect(items[0].weightKg).toBe(50.0);
    expect(items[0].bodyFatPercent).toBe(20.0);
  });

  it('栄養のみの日は体組成が null、体組成のみの日は栄養が 0', async () => {
    await env.DB.batch([
      insertFoodMaster('f1', { calories: 300, portionSize: 1 }),
      insertLog('l1', 'user-a', '2025-01-05', 'f1', 1),
      insertBody('b1', 'user-a', '2025-01-10T09:00:00.000Z', 51.0),
    ]);
    const items = await getDaily('user-a', '2025-01-01', '2025-01-31');
    expect(items.map((i) => i.date)).toEqual(['2025-01-05', '2025-01-10']);

    const nutriOnly = items[0];
    expect(nutriOnly.calories).toBe(300);
    expect(nutriOnly.weightKg).toBeNull();

    const bodyOnly = items[1];
    expect(bodyOnly.calories).toBe(0);
    expect(bodyOnly.weightKg).toBe(51.0);
  });

  it('同日に複数の体組成計測がある場合は平均される', async () => {
    await env.DB.batch([
      insertBody('b1', 'user-a', '2025-01-05T08:00:00.000Z', 50.0, 20.0),
      insertBody('b2', 'user-a', '2025-01-05T20:00:00.000Z', 52.0, 22.0),
    ]);
    const items = await getDaily('user-a', '2025-01-01', '2025-01-31');
    expect(items).toHaveLength(1);
    expect(items[0].weightKg).toBe(51.0);
    expect(items[0].bodyFatPercent).toBe(21.0);
  });

  it('期間外のデータは含まれず、他ユーザーのデータも混ざらない', async () => {
    await env.DB.batch([
      insertBody('b1', 'user-a', '2024-12-31T09:00:00.000Z', 49.0),
      insertBody('b2', 'user-a', '2025-01-05T09:00:00.000Z', 50.0),
      insertBody('b3', 'user-a', '2025-02-01T09:00:00.000Z', 53.0),
      insertBody('b4', 'user-b', '2025-01-05T09:00:00.000Z', 80.0),
    ]);
    const items = await getDaily('user-a', '2025-01-01', '2025-01-31');
    expect(items).toHaveLength(1);
    expect(items[0].date).toBe('2025-01-05');
    expect(items[0].weightKg).toBe(50.0);
  });

  it('結果は date 昇順で返る', async () => {
    await env.DB.batch([
      insertBody('b1', 'user-a', '2025-01-20T09:00:00.000Z', 50.0),
      insertBody('b2', 'user-a', '2025-01-05T09:00:00.000Z', 51.0),
      insertBody('b3', 'user-a', '2025-01-12T09:00:00.000Z', 52.0),
    ]);
    const items = await getDaily('user-a', '2025-01-01', '2025-01-31');
    expect(items.map((i) => i.date)).toEqual(['2025-01-05', '2025-01-12', '2025-01-20']);
  });
});
