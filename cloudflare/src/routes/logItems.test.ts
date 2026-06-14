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
    `CREATE TABLE IF NOT EXISTS user_food_stats (
      user_id TEXT NOT NULL,
      food_master_id TEXT NOT NULL COLLATE NOCASE REFERENCES food_masters(id) ON DELETE CASCADE,
      usage_count INTEGER NOT NULL DEFAULT 0,
      last_used_date TEXT,
      last_number_of_servings REAL NOT NULL DEFAULT 1.0,
      PRIMARY KEY (user_id, food_master_id)
    )`
  ).run();
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM user_food_stats'),
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM food_masters'),
  ]);
});

async function jwtFor(userId: string): Promise<string> {
  return issueSessionJwt(userId, TEST_SECRET);
}

function insertLogItem(
  id: string,
  userId: string,
  logDate: string,
  timestamp: string = `${logDate}T00:00:00Z`
) {
  return env.DB.prepare(
    `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type)
     VALUES (?, ?, ?, ?, 'Breakfast')`
  ).bind(id, userId, timestamp, logDate);
}

async function fetchRange(userId: string, from: string, to: string) {
  const res = await SELF.fetch(
    `http://localhost/api/log-items?from=${from}&to=${to}`,
    { headers: { Authorization: `Bearer ${await jwtFor(userId)}` } }
  );
  return res;
}

describe('GET /api/log-items?from&to (期間範囲クエリ)', () => {
  it('from〜to の範囲内のログだけ返す（範囲外は除外）', async () => {
    await env.DB.batch([
      insertLogItem('li-before', 'user-a', '2024-01-04'),
      insertLogItem('li-from', 'user-a', '2024-01-05'),
      insertLogItem('li-mid', 'user-a', '2024-01-07'),
      insertLogItem('li-to', 'user-a', '2024-01-10'),
      insertLogItem('li-after', 'user-a', '2024-01-11'),
    ]);

    const res = await fetchRange('user-a', '2024-01-05', '2024-01-10');
    expect(res.status).toBe(200);
    const { items } = await res.json<{ items: Array<{ id: string }> }>();
    expect(items.map((i) => i.id)).toEqual(['li-from', 'li-mid', 'li-to']);
  });

  it('from==to なら当日のログだけ返す', async () => {
    await env.DB.batch([
      insertLogItem('li-prev', 'user-a', '2024-01-04'),
      insertLogItem('li-day', 'user-a', '2024-01-05'),
      insertLogItem('li-next', 'user-a', '2024-01-06'),
    ]);

    const res = await fetchRange('user-a', '2024-01-05', '2024-01-05');
    const { items } = await res.json<{ items: Array<{ id: string }> }>();
    expect(items.map((i) => i.id)).toEqual(['li-day']);
  });

  it('log_date 昇順で返す', async () => {
    await env.DB.batch([
      insertLogItem('li-c', 'user-a', '2024-01-09'),
      insertLogItem('li-a', 'user-a', '2024-01-05'),
      insertLogItem('li-b', 'user-a', '2024-01-07'),
    ]);

    const res = await fetchRange('user-a', '2024-01-01', '2024-01-31');
    const { items } = await res.json<{ items: Array<{ id: string }> }>();
    expect(items.map((i) => i.id)).toEqual(['li-a', 'li-b', 'li-c']);
  });

  it('他ユーザーのログは含まない', async () => {
    await env.DB.batch([
      insertLogItem('li-a', 'user-a', '2024-01-05'),
      insertLogItem('li-b', 'user-b', '2024-01-05'),
    ]);

    const res = await fetchRange('user-a', '2024-01-01', '2024-01-31');
    const { items } = await res.json<{ items: Array<{ id: string }> }>();
    expect(items.map((i) => i.id)).toEqual(['li-a']);
  });
});
