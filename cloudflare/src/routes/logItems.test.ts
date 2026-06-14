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

function insertLogItem(id: string, userId: string, logDate: string) {
  return env.DB.prepare(
    `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type)
     VALUES (?, ?, ?, ?, 'Breakfast')`
  ).bind(id, userId, `${logDate}T00:00:00Z`, logDate);
}

async function fetchItems(userId: string, queryString: string) {
  const res = await SELF.fetch(`http://localhost/api/log-items?${queryString}`, {
    headers: { Authorization: `Bearer ${await jwtFor(userId)}` },
  });
  expect(res.status).toBe(200);
  const body = (await res.json()) as { items: { id: string }[] };
  return body.items.map((i) => i.id);
}

describe('GET /api/log-items?from&to (期間範囲取得)', () => {
  it('from〜to の範囲内（両端含む）のログだけを返す', async () => {
    await env.DB.batch([
      insertLogItem('before', 'user-a', '2024-01-04'),
      insertLogItem('start', 'user-a', '2024-01-05'),
      insertLogItem('middle', 'user-a', '2024-01-07'),
      insertLogItem('end', 'user-a', '2024-01-11'),
      insertLogItem('after', 'user-a', '2024-01-12'),
    ]);

    const ids = await fetchItems('user-a', 'from=2024-01-05&to=2024-01-11');

    expect(ids.sort()).toEqual(['end', 'middle', 'start']);
  });

  it('他ユーザーのログは範囲内でも返さない', async () => {
    await env.DB.batch([
      insertLogItem('mine', 'user-a', '2024-01-06'),
      insertLogItem('theirs', 'user-b', '2024-01-06'),
    ]);

    const ids = await fetchItems('user-a', 'from=2024-01-01&to=2024-01-31');

    expect(ids).toEqual(['mine']);
  });

  it('timestamp の昇順で返す', async () => {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type)
         VALUES ('later', 'user-a', '2024-01-06T20:00:00Z', '2024-01-06', 'Dinner')`
      ),
      env.DB.prepare(
        `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type)
         VALUES ('earlier', 'user-a', '2024-01-06T07:00:00Z', '2024-01-06', 'Breakfast')`
      ),
    ]);

    const ids = await fetchItems('user-a', 'from=2024-01-06&to=2024-01-06');

    expect(ids).toEqual(['earlier', 'later']);
  });
});
