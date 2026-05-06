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

function insertFoodMaster(id: string, createdBy: string) {
  return env.DB.prepare(
    `INSERT INTO food_masters (id, product_name, unique_key, created_by)
     VALUES (?, ?, ?, ?)`
  ).bind(id, `Food ${id}`, `|Food ${id}|g`, createdBy);
}

function insertLogItem(id: string, userId: string, foodMasterId: string | null = null) {
  return env.DB.prepare(
    `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type, food_master_id)
     VALUES (?, ?, '2024-01-01T00:00:00Z', '2024-01-01', 'Breakfast', ?)`
  ).bind(id, userId, foodMasterId);
}

describe('DELETE /api/user-data', () => {
  it('他ユーザーが作成した food_master は削除されない', async () => {
    await env.DB.batch([
      insertFoodMaster('fm-other', 'user-b'),
      insertLogItem('li-a', 'user-a'),
    ]);

    const res = await SELF.fetch('http://localhost/api/user-data', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${await jwtFor('user-a')}` },
    });

    expect(res.status).toBe(200);
    const remaining = await env.DB.prepare(
      'SELECT id FROM food_masters WHERE id = ?'
    ).bind('fm-other').first();
    expect(remaining).not.toBeNull();
  });

  it('自分が作成した孤立 food_master は削除される', async () => {
    await insertFoodMaster('fm-own', 'user-a').run();

    const res = await SELF.fetch('http://localhost/api/user-data', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${await jwtFor('user-a')}` },
    });

    expect(res.status).toBe(200);
    const remaining = await env.DB.prepare(
      'SELECT id FROM food_masters WHERE id = ?'
    ).bind('fm-own').first();
    expect(remaining).toBeNull();
  });

  it('他ユーザーのログに参照されている自分の food_master は削除されない', async () => {
    await env.DB.batch([
      insertFoodMaster('fm-shared', 'user-a'),
      insertLogItem('li-b', 'user-b', 'fm-shared'),
    ]);

    const res = await SELF.fetch('http://localhost/api/user-data', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${await jwtFor('user-a')}` },
    });

    expect(res.status).toBe(200);
    const remaining = await env.DB.prepare(
      'SELECT id FROM food_masters WHERE id = ?'
    ).bind('fm-shared').first();
    expect(remaining).not.toBeNull();
  });

  it('自分の log_items と user_food_stats が削除される', async () => {
    await env.DB.batch([
      insertFoodMaster('fm-ref', 'user-a'),
      insertLogItem('li-a', 'user-a', 'fm-ref'),
      env.DB.prepare(
        `INSERT INTO user_food_stats (user_id, food_master_id, usage_count)
         VALUES ('user-a', 'fm-ref', 3)`
      ),
    ]);

    const res = await SELF.fetch('http://localhost/api/user-data', {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${await jwtFor('user-a')}` },
    });

    expect(res.status).toBe(200);
    const logItem = await env.DB.prepare(
      'SELECT id FROM log_items WHERE user_id = ?'
    ).bind('user-a').first();
    const stats = await env.DB.prepare(
      'SELECT user_id FROM user_food_stats WHERE user_id = ?'
    ).bind('user-a').first();
    expect(logItem).toBeNull();
    expect(stats).toBeNull();
  });
});
