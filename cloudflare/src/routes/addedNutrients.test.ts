/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';

// 最初の5項目のあとに足した栄養素。値が無ければ「分からない」として扱い、0 とは区別する。
// 公開中の古い版のアプリは新しい栄養素を送らないので、送られなかったら分からないまま残す。

beforeAll(() => applySchema(env.DB));

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM user_food_stats'),
    env.DB.prepare('DELETE FROM food_masters'),
  ]);
});

async function call(path: string, init: { method?: string; body?: unknown; text?: string } = {}) {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${await issueSessionJwt('user-a', 'dev-and-test-secret')}`,
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

const CORE = { calories: 650, protein: 15, fat: 20, netCarbs: 90, dietaryFiber: 3 };

function food(id: string, extra: Record<string, unknown> = {}) {
  return {
    id, brandName: 'Home', productName: `カレー ${id}`, ...CORE,
    portionSize: 1, portionUnit: '皿', uniqueKey: `Home|カレー ${id}|皿`, ...extra,
  };
}

const A = '11111111-1111-1111-1111-111111111111';
const B = '22222222-2222-2222-2222-222222222222';
const C = '33333333-3333-3333-3333-333333333333';

async function create(id: string, extra: Record<string, unknown> = {}) {
  return call('/api/food-masters', { method: 'POST', body: food(id, extra) });
}

async function get(id: string) {
  return (await call(`/api/food-masters/${id}`)).json<Record<string, unknown>>();
}

async function log(id: string, foodId: string, servings: number, mealType = 'Lunch', date = '2026-11-01') {
  const f = await get(foodId);
  return call('/api/log-items', {
    method: 'POST',
    body: {
      id, timestamp: `${date}T12:00:00Z`, logDate: date, mealType, numberOfServings: servings,
      foodMasterId: foodId, nutritionSnapshot: f,
    },
  });
}

describe('食品の新しい栄養素', () => {
  it('送られた値を保存して返す', async () => {
    const res = await create(A, { saltEquivalent: 2.5, saturatedFat: 8 });

    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({ ...CORE, saltEquivalent: 2.5, saturatedFat: 8 });
  });

  it('送られなければ分からないとして、応答から省く', async () => {
    await create(A);

    const fetched = await get(A);
    expect(fetched).toMatchObject(CORE);
    expect(fetched).not.toHaveProperty('saltEquivalent');
    expect(fetched).not.toHaveProperty('saturatedFat');
  });

  it('0 は分からないとは区別して返す', async () => {
    await create(A, { saltEquivalent: 0 });

    expect(await get(A)).toMatchObject({ saltEquivalent: 0 });
  });

  it('一括で作るときも受け取る', async () => {
    await call('/api/food-masters/batch', { method: 'POST', body: { items: [food(A, { saturatedFat: 8 })] } });

    expect(await get(A)).toMatchObject({ saturatedFat: 8 });
  });
});

describe('食品の更新', () => {
  it('送られた新しい栄養素だけを変え、送られなかったものは元のまま残す', async () => {
    await create(A, { saltEquivalent: 2.5, saturatedFat: 8 });

    const res = await call(`/api/food-masters/${A}`, { method: 'PUT', body: { saltEquivalent: 3 } });

    expect(await res.json()).toMatchObject({ ...CORE, saltEquivalent: 3, saturatedFat: 8 });
  });

  it('null が送られた新しい栄養素は、分からないに戻す', async () => {
    await create(A, { saltEquivalent: 2.5, saturatedFat: 8 });

    const res = await call(`/api/food-masters/${A}`, { method: 'PUT', body: { saltEquivalent: null } });

    const body = await res.json<Record<string, unknown>>();
    expect(body).not.toHaveProperty('saltEquivalent');
    expect(body).toMatchObject({ saturatedFat: 8 });
  });

  it('最初の5項目は null が送られても変えない', async () => {
    // 5項目は必ず値を持つ。古い版のアプリは送らない項目を null にはしないが、念のため今の値を守る
    await create(A);

    const res = await call(`/api/food-masters/${A}`, { method: 'PUT', body: { protein: null, fat: 25 } });

    expect(await res.json()).toMatchObject({ ...CORE, fat: 25 });
  });
});

describe('値の出典', () => {
  it('作成で受け取り、返す', async () => {
    await create(A, { nutrientSource: 'manual', nutrientSourceRef: 'https://example.com/curry' });

    expect(await get(A)).toMatchObject({ nutrientSource: 'manual', nutrientSourceRef: 'https://example.com/curry' });
  });

  it('送られなければ null で返す', async () => {
    await create(A);

    expect(await get(A)).toMatchObject({ nutrientSource: null, nutrientSourceRef: null });
  });

  it('決まった種類以外は受け付けない', async () => {
    const res = await create(A, { nutrientSource: 'guess' });

    expect(res.status).toBe(400);
  });

  it('更新では送られたときだけ変える', async () => {
    await create(A, { nutrientSource: 'label' });

    await call(`/api/food-masters/${A}`, { method: 'PUT', body: { fat: 25 } });
    expect(await get(A)).toMatchObject({ nutrientSource: 'label' });

    await call(`/api/food-masters/${A}`, { method: 'PUT', body: { nutrientSource: null } });
    expect(await get(A)).toMatchObject({ nutrientSource: null });
  });
});

describe('記録のスナップショット', () => {
  it('定義にある栄養素と、名前と量だけを保存する', async () => {
    await create(A, { saltEquivalent: 2.5 });
    await call('/api/log-items', {
      method: 'POST',
      body: {
        id: 'log-1', timestamp: '2026-11-01T12:00:00Z', logDate: '2026-11-01', mealType: 'Lunch',
        numberOfServings: 1, foodMasterId: A,
        nutritionSnapshot: {
          brandName: 'Home', productName: 'カレー', ...CORE, saltEquivalent: 2.5,
          portionSize: 1, portionUnit: '皿', somethingElse: 'x',
        },
      },
    });

    const { items } = await (await call('/api/log-items?logDate=2026-11-01')).json<{
      items: { nutritionSnapshot: Record<string, unknown> }[];
    }>();
    expect(items[0].nutritionSnapshot).toEqual({
      brandName: 'Home', productName: 'カレー', ...CORE, saltEquivalent: 2.5, portionSize: 1, portionUnit: '皿',
    });
  });

  it('食品を消すと、分かっている新しい栄養素もスナップショットに残す', async () => {
    await create(A, { saturatedFat: 8 });
    await log('log-1', A, 1);

    await call(`/api/food-masters/${A}`, { method: 'DELETE' });

    const { items } = await (await call('/api/log-items?logDate=2026-11-01')).json<{
      items: { nutritionSnapshot: Record<string, unknown> }[];
    }>();
    expect(items[0].nutritionSnapshot).toMatchObject({ ...CORE, saturatedFat: 8 });
    expect(items[0].nutritionSnapshot).not.toHaveProperty('saltEquivalent');
  });
});

describe('集計', () => {
  async function threeMeals() {
    await create(A, { saltEquivalent: 2.5, saturatedFat: 8 });
    await create(B, { saltEquivalent: 1 });
    await create(C);
    await log('log-a', A, 2);
    await log('log-b', B, 1);
    await log('log-c', C, 1);
  }

  it('新しい栄養素は、値の分かっている品だけを足し、品数を添える', async () => {
    await threeMeals();

    const { items } = await (await call('/api/log-items/summary?from=2026-11-01&to=2026-11-01')).json<{
      items: Record<string, unknown>[];
    }>();
    expect(items).toEqual([{
      logDate: '2026-11-01', mealType: 'Lunch',
      calories: 2600, protein: 60, fat: 80, netCarbs: 360, dietaryFiber: 12,
      saltEquivalent: 6, saturatedFat: 16,
      itemCount: 3, knownCounts: { saltEquivalent: 2, saturatedFat: 1 },
    }]);
  });

  it('どの品も分からない栄養素は、合計を省き、品数を 0 にする', async () => {
    await create(C);
    await log('log-c', C, 1);

    const { items } = await (await call('/api/log-items/summary?from=2026-11-01&to=2026-11-01')).json<{
      items: Record<string, unknown>[];
    }>();
    expect(items[0]).not.toHaveProperty('saltEquivalent');
    expect(items[0]).toMatchObject({ itemCount: 1, knownCounts: { saltEquivalent: 0, saturatedFat: 0 } });
  });

  it('日次の統計も同じ形で返す。記録の無い日は品数を 0 にする', async () => {
    await threeMeals();
    await env.DB.prepare(
      `INSERT INTO body_measurements (id, user_id, source_date, measured_at, weight_kg) VALUES ('m1', 'user-a', '2026-11-02', '2026-11-02T00:00:00Z', 60)`,
    ).run();

    const { items } = await (await call('/api/statistics/daily?from=2026-11-01&to=2026-11-02')).json<{
      items: Record<string, unknown>[];
    }>();
    expect(items[0]).toMatchObject({
      date: '2026-11-01', calories: 2600, saltEquivalent: 6, saturatedFat: 16,
      itemCount: 3, knownCounts: { saltEquivalent: 2, saturatedFat: 1 },
    });
    expect(items[1]).toMatchObject({ date: '2026-11-02', calories: 0, itemCount: 0, weightKg: 60 });
    expect(items[1]).not.toHaveProperty('saltEquivalent');
  });
});

describe('CSV の読み込み', () => {
  const header = 'date,meal_type,brand_name,product_name,calories,carbs,fat,protein,portion_amount,portion_unit,dietary_fiber';

  it('見出しに新しい栄養素の列があれば読み、空のセルは分からないにする', async () => {
    const csv = [
      `${header},salt_equivalent,saturated_fat`,
      '2026-11-01,Lunch,Home,カレー,650,93,20,15,1,皿,3,2.5,',
    ].join('\n');

    await call('/api/csv/import', { method: 'POST', text: csv });

    const list = await (await call('/api/food-masters?q=カレー')).json<{ items: Record<string, unknown>[] }>();
    expect(list.items[0]).toMatchObject({ saltEquivalent: 2.5 });
    expect(list.items[0]).not.toHaveProperty('saturatedFat');
    const { items } = await (await call('/api/log-items?logDate=2026-11-01')).json<{
      items: { nutritionSnapshot: Record<string, unknown> }[];
    }>();
    expect(items[0].nutritionSnapshot).toMatchObject({ saltEquivalent: 2.5 });
    expect(items[0].nutritionSnapshot).not.toHaveProperty('saturatedFat');
  });

  it('列が無い古い CSV では、新しい栄養素を分からないにする', async () => {
    await call('/api/csv/import', { method: 'POST', text: `${header}\n2026-11-01,Lunch,Home,カレー,650,93,20,15,1,皿,3` });

    const list = await (await call('/api/food-masters?q=カレー')).json<{ items: Record<string, unknown>[] }>();
    expect(list.items[0]).toMatchObject(CORE);
    expect(list.items[0]).not.toHaveProperty('saltEquivalent');
  });
});
