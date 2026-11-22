/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';

// 栄養素の値が、食品の作成から記録、削除、集計まで取り違えずに通るか。
// 5つの栄養素にすべて別の値を入れ、列名とキーの対応がずれたら落ちるようにしている。

const TEST_SECRET = 'dev-and-test-secret';

const CURRY = { calories: 650, protein: 15, fat: 20, netCarbs: 90, dietaryFiber: 3 };

beforeAll(async () => {
  await env.DB.batch([
    env.DB.prepare(
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
      )`),
    env.DB.prepare(
      `CREATE TABLE IF NOT EXISTS user_food_stats (
        user_id TEXT NOT NULL,
        food_master_id TEXT NOT NULL COLLATE NOCASE,
        usage_count INTEGER NOT NULL DEFAULT 0,
        last_used_date TEXT,
        last_number_of_servings REAL NOT NULL DEFAULT 1.0,
        PRIMARY KEY (user_id, food_master_id)
      )`),
    env.DB.prepare(
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
      )`),
    // 日次の統計は体組成も読むので、空の表だけ置く
    env.DB.prepare(
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
      )`),
  ]);
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM user_food_stats'),
    env.DB.prepare('DELETE FROM food_masters'),
  ]);
});

async function call(path: string, init: { method?: string; body?: unknown; text?: string } = {}) {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${await issueSessionJwt('user-a', TEST_SECRET)}`,
  };
  let body: string | undefined;
  if (init.text !== undefined) {
    headers['Content-Type'] = 'text/csv';
    body = init.text;
  } else if (init.body !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(init.body);
  }
  return SELF.fetch(`http://localhost${path}`, { method: init.method ?? 'GET', headers, body });
}

function curry(id: string, values = CURRY) {
  return {
    id, brandName: 'Home', productName: 'カレーライス', ...values,
    portionSize: 1, portionUnit: '皿', uniqueKey: `Home|カレーライス|皿|${id}`,
  };
}

const FOOD_ID = '11111111-1111-1111-1111-111111111111';

async function logCurry(servings = 2) {
  return call('/api/log-items', {
    method: 'POST',
    body: {
      id: 'log-1', timestamp: '2026-11-01T12:00:00Z', logDate: '2026-11-01', mealType: 'Lunch',
      numberOfServings: servings, foodMasterId: FOOD_ID,
      nutritionSnapshot: { brandName: 'Home', productName: 'カレーライス', ...CURRY, portionSize: 1, portionUnit: '皿' },
    },
  });
}

describe('食品の栄養素', () => {
  it('作成した値を、そのままのキーで読み返せる', async () => {
    const created = await call('/api/food-masters', { method: 'POST', body: curry(FOOD_ID) });
    expect(created.status).toBe(201);
    expect(await created.json()).toMatchObject(CURRY);

    const fetched = await call(`/api/food-masters/${FOOD_ID}`);
    expect(await fetched.json()).toMatchObject(CURRY);
  });

  it('一括で作成した値も一覧で読み返せる', async () => {
    await call('/api/food-masters/batch', { method: 'POST', body: { items: [curry(FOOD_ID)] } });

    const list = await (await call('/api/food-masters?q=カレー')).json<{ items: unknown[] }>();
    expect(list.items).toHaveLength(1);
    expect(list.items[0]).toMatchObject(CURRY);
  });

  it('更新では送った栄養素だけが変わり、ほかは元のまま残る', async () => {
    await call('/api/food-masters', { method: 'POST', body: curry(FOOD_ID) });

    const updated = await call(`/api/food-masters/${FOOD_ID}`, { method: 'PUT', body: { fat: 25 } });

    expect(await updated.json()).toMatchObject({ ...CURRY, fat: 25 });
  });

  it('食品を消すと、参照していた記録のスナップショットに全栄養素の値を残す', async () => {
    await call('/api/food-masters', { method: 'POST', body: curry(FOOD_ID) });
    await call(`/api/food-masters/${FOOD_ID}`, { method: 'PUT', body: { protein: 18 } });
    await logCurry();

    await call(`/api/food-masters/${FOOD_ID}`, { method: 'DELETE' });

    const { items } = await (await call('/api/log-items?logDate=2026-11-01')).json<{
      items: { foodMaster: unknown; nutritionSnapshot: Record<string, unknown> }[];
    }>();
    expect(items[0].foodMaster).toBeNull();
    // 記録したときの値ではなく、消す直前の食品の値を残す
    expect(items[0].nutritionSnapshot).toMatchObject({ ...CURRY, protein: 18, portionSize: 1, portionUnit: '皿' });
  });
});

describe('記録の栄養素', () => {
  it('記録の一覧に付く食品は、全栄養素の値を持つ', async () => {
    await call('/api/food-masters', { method: 'POST', body: curry(FOOD_ID) });
    await logCurry();

    const { items } = await (await call('/api/log-items?logDate=2026-11-01')).json<{
      items: { foodMaster: Record<string, unknown> }[];
    }>();
    expect(items[0].foodMaster).toMatchObject(CURRY);
  });

  it('日ごとの集計は、栄養素ごとに食品の値を量で按分して足す', async () => {
    await call('/api/food-masters', { method: 'POST', body: curry(FOOD_ID) });
    await logCurry(2);

    const summary = await (await call('/api/log-items/summary?from=2026-11-01&to=2026-11-01')).json<{
      items: unknown[];
    }>();
    expect(summary.items).toEqual([{
      logDate: '2026-11-01', mealType: 'Lunch',
      calories: 1300, protein: 30, fat: 40, netCarbs: 180, dietaryFiber: 6,
    }]);

    const daily = await (await call('/api/statistics/daily?from=2026-11-01&to=2026-11-01')).json<{
      items: Record<string, unknown>[];
    }>();
    expect(daily.items[0]).toMatchObject({
      date: '2026-11-01', calories: 1300, protein: 30, fat: 40, netCarbs: 180, dietaryFiber: 6,
    });
  });

  it('食品が消えた記録は、スナップショットの値で集計する', async () => {
    await call('/api/food-masters', { method: 'POST', body: curry(FOOD_ID) });
    await logCurry(1);
    await call(`/api/food-masters/${FOOD_ID}`, { method: 'DELETE' });

    const summary = await (await call('/api/log-items/summary?from=2026-11-01&to=2026-11-01')).json<{
      items: unknown[];
    }>();
    expect(summary.items).toEqual([{ logDate: '2026-11-01', mealType: 'Lunch', ...CURRY }]);
  });
});

describe('CSV の読み込み', () => {
  it('炭水化物から食物繊維を引いて糖質にし、ほかの栄養素は列のとおりに入れる', async () => {
    const csv = [
      'date,meal_type,brand_name,product_name,calories,carbs,fat,protein,portion_amount,portion_unit,dietary_fiber',
      '2026-11-01,Lunch,Home,カレーライス,650,93,20,15,1,皿,3',
    ].join('\n');

    const res = await call('/api/csv/import', { method: 'POST', text: csv });
    expect(res.status).toBe(200);

    const list = await (await call('/api/food-masters?q=カレー')).json<{ items: unknown[] }>();
    expect(list.items[0]).toMatchObject(CURRY);
    const { items } = await (await call('/api/log-items?logDate=2026-11-01')).json<{
      items: { nutritionSnapshot: Record<string, unknown> }[];
    }>();
    expect(items[0].nutritionSnapshot).toMatchObject(CURRY);
  });
});
