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
    `CREATE TABLE IF NOT EXISTS user_food_stats (
      user_id TEXT NOT NULL,
      food_master_id TEXT NOT NULL COLLATE NOCASE,
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
    env.DB.prepare('DELETE FROM food_masters'),
  ]);
});

function insertFoodMaster(id: string, brandName: string, productName: string, createdBy = 'someone-else') {
  return env.DB.prepare(
    `INSERT INTO food_masters (id, brand_name, product_name, unique_key, created_by)
     VALUES (?, ?, ?, ?, ?)`
  ).bind(id, brandName, productName, `${brandName}|${productName}|g`, createdBy);
}

async function search(query: string) {
  const res = await SELF.fetch(`http://localhost/api/food-masters?${query}`, {
    headers: { Authorization: `Bearer ${await issueSessionJwt('user-a', TEST_SECRET)}` },
  });
  expect(res.status).toBe(200);
  const body = await res.json<{ items: Array<{ brandName: string; productName: string }>; total: number }>();
  return { names: body.items.map((i) => `${i.brandName}|${i.productName}`).sort(), total: body.total };
}

describe('GET /api/food-masters の q', () => {
  beforeEach(async () => {
    await env.DB.batch([
      insertFoodMaster('fm-1', 'スシロー', 'サーモンアボカド'),
      insertFoodMaster('fm-2', 'スシロー', 'まぐろ'),
      insertFoodMaster('fm-3', '', 'サーモンアボカド丼'),
    ]);
  });

  it('空白で区切った語が、すべてブランド名か商品名のどちらかに含まれるものを返す', async () => {
    const { names, total } = await search(`q=${encodeURIComponent('スシロー サーモン')}`);
    expect(names).toEqual(['スシロー|サーモンアボカド']);
    expect(total).toBe(1);
  });

  it('全角の空白でも区切る', async () => {
    const { names } = await search(`q=${encodeURIComponent('スシロー　サーモン')}`);
    expect(names).toEqual(['スシロー|サーモンアボカド']);
  });

  it('1語なら、ブランド名か商品名に含まれるものをすべて返す', async () => {
    const { names } = await search(`q=${encodeURIComponent('サーモン')}`);
    expect(names).toEqual(['|サーモンアボカド丼', 'スシロー|サーモンアボカド']);
  });
});

describe('GET /api/food-masters の excludeAI', () => {
  beforeEach(async () => {
    await env.DB.batch([
      insertFoodMaster('fm-1', 'くら寿司', 'サーモン'),
      insertFoodMaster('fm-2', 'AI', 'サーモン（くら寿司）'),
      insertFoodMaster('fm-3', 'AI', 'サーモン（自分の推定）', 'user-a'),
    ]);
  });

  it('true なら、自分のものも含めてブランド名が AI の項目を除く', async () => {
    const { names, total } = await search(`q=${encodeURIComponent('サーモン')}&excludeAI=true`);
    expect(names).toEqual(['くら寿司|サーモン']);
    expect(total).toBe(1);
  });

  it('付けなければ AI の項目も返す', async () => {
    const { total } = await search(`q=${encodeURIComponent('サーモン')}`);
    expect(total).toBe(3);
  });
});
