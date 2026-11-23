/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';

const TEST_SECRET = 'dev-and-test-secret';

beforeAll(() => applySchema(env.DB));

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

  it('50バイトを超える長い語でも探せる', async () => {
    // D1 は LIKE のパターン長に上限があり、超えると SQL がエラーになる
    await insertFoodMaster('fm-long', 'ロイヤルホスト', '国産鶏むね肉のグリルチキンサラダ（ｸﾞﾘｰﾝｺﾞｯﾃﾞｽﾄﾞﾚｯｼﾝｸﾞ) ').run();

    const { names } = await search(
      `q=${encodeURIComponent('ロイヤルホスト 国産鶏むね肉のグリルチキンサラダ（ｸﾞﾘｰﾝｺﾞｯﾃﾞｽﾄﾞﾚｯｼﾝｸﾞ)')}`
    );
    expect(names).toEqual(['ロイヤルホスト|国産鶏むね肉のグリルチキンサラダ（ｸﾞﾘｰﾝｺﾞｯﾃﾞｽﾄﾞﾚｯｼﾝｸﾞ) ']);
  });

  it('% や _ は文字そのものとして探す', async () => {
    await insertFoodMaster('fm-percent', '', '果汁100%ジュース').run();

    const { names } = await search(`q=${encodeURIComponent('100%')}`);
    expect(names).toEqual(['|果汁100%ジュース']);
  });

  it('英字の大文字と小文字は区別しない', async () => {
    await insertFoodMaster('fm-ascii', 'Starbucks', 'Latte').run();

    const { names } = await search('q=starbucks%20latte');
    expect(names).toEqual(['Starbucks|Latte']);
  });

  it('1語なら、ブランド名か商品名に含まれるものをすべて返す', async () => {
    const { names } = await search(`q=${encodeURIComponent('サーモン')}`);
    expect(names).toEqual(['|サーモンアボカド丼', 'スシロー|サーモンアボカド']);
  });
});

describe('POST /api/food-masters', () => {
  async function create(body: Record<string, unknown>) {
    return SELF.fetch('http://localhost/api/food-masters', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await issueSessionJwt('user-a', TEST_SECRET)}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  }

  function curry(id: string, calories: number) {
    return {
      id, brandName: 'AI', productName: 'カレーライス',
      calories, dietaryFiber: 3, netCarbs: 90, fat: 20, protein: 15,
      portionSize: 1, portionUnit: '皿', uniqueKey: 'AI|カレーライス|皿',
    };
  }

  it('新しい食品を作って 201 で返す', async () => {
    const res = await create(curry('11111111-1111-1111-1111-111111111111', 650));
    expect(res.status).toBe(201);
    const body = await res.json<{ id: string; calories: number }>();
    expect(body.id).toBe('11111111-1111-1111-1111-111111111111');
    expect(body.calories).toBe(650);
  });

  it('onConflict が reject なら、同じブランド名・商品名・単位の別の食品があるとき上書きせず 409 と既存の食品を返す', async () => {
    await create(curry('11111111-1111-1111-1111-111111111111', 650));

    const res = await create({ ...curry('22222222-2222-2222-2222-222222222222', 800), onConflict: 'reject' });

    expect(res.status).toBe(409);
    const body = await res.json<{ existing: { id: string; calories: number } }>();
    expect(body.existing.id).toBe('11111111-1111-1111-1111-111111111111');
    expect(body.existing.calories).toBe(650);
  });

  it('onConflict が reject でも、同じ id で送り直したときは作成済みの食品を 201 で返す', async () => {
    await create(curry('11111111-1111-1111-1111-111111111111', 650));

    const res = await create({ ...curry('11111111-1111-1111-1111-111111111111', 650), onConflict: 'reject' });

    expect(res.status).toBe(201);
    const body = await res.json<{ id: string }>();
    expect(body.id).toBe('11111111-1111-1111-1111-111111111111');
  });

  it('onConflict が無ければ、公開中の古い版のアプリのために既存の食品を 201 で返す', async () => {
    await create(curry('11111111-1111-1111-1111-111111111111', 650));

    const res = await create(curry('22222222-2222-2222-2222-222222222222', 800));

    expect(res.status).toBe(201);
    const body = await res.json<{ id: string; calories: number }>();
    expect(body.id).toBe('11111111-1111-1111-1111-111111111111');
    expect(body.calories).toBe(650);
  });
});
