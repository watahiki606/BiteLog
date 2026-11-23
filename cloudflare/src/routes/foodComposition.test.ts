/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';

// 食品を成分表の食品と重さの組にひも付け、分からない栄養素を成分表で補う。
// ラベルや手入力の値は書き換えず、補った栄養素には印を付ける。

beforeAll(() => applySchema(env.DB));

const RICE = '01088';
const OYAKO = '18030';
const CHIPS = '15103';

async function insertComposition(foodNumber: string, name: string, values: Record<string, number | null>) {
  const columns = Object.keys(values);
  await env.DB.prepare(
    `INSERT INTO composition_foods (food_number, food_group, name, search_text, edition, ${columns.join(', ')}, raw_json)
     VALUES (?, ?, ?, ?, 'test', ${columns.map(() => '?').join(', ')}, '{}')`,
  ).bind(foodNumber, foodNumber.slice(0, 2), name, name, ...Object.values(values)).run();
}

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM food_master_components'),
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM user_food_stats'),
    env.DB.prepare('DELETE FROM food_masters'),
    env.DB.prepare('DELETE FROM composition_foods'),
  ]);
  await insertComposition(RICE, 'めし', {
    calories: 156, protein: 2.5, fat: 0.3, net_carbs: 35.6, dietary_fiber: 1.5, salt_equivalent: 0, saturated_fat: 0.1,
    potassium: 29, calcium: 3, magnesium: 7, iron: 0.1, vitamin_a: 0, vitamin_d: 0, vitamin_c: 0,
  });
  await insertComposition(OYAKO, '親子丼の具', {
    calories: 101, protein: 8.4, fat: 5.2, net_carbs: 5.2, dietary_fiber: 0.4, salt_equivalent: 1.0, saturated_fat: 1.4,
    potassium: 120, calcium: 21, magnesium: 12, iron: 0.7, vitamin_a: 57, vitamin_d: 0.7, vitamin_c: 2,
  });
  await insertComposition(CHIPS, 'ポテトチップス', {
    calories: 541, protein: 4.7, fat: 35.2, net_carbs: 50.5, dietary_fiber: 4.2, salt_equivalent: 1.0, saturated_fat: 3.86,
    potassium: 1200, calcium: 17, magnesium: 70, iron: 1.7, vitamin_a: 0, vitamin_d: null, vitamin_c: 15,
  });
});

async function call(path: string, init: { method?: string; body?: unknown; user?: string } = {}) {
  return SELF.fetch(`http://localhost${path}`, {
    method: init.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${await issueSessionJwt(init.user ?? 'user-a', 'dev-and-test-secret')}`,
      'Content-Type': 'application/json',
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
}

const OYAKODON = '11111111-1111-1111-1111-111111111111';
const POTATO_CHIPS = '22222222-2222-2222-2222-222222222222';

function food(id: string, name: string, extra: Record<string, unknown>) {
  return {
    id, brandName: 'Home', productName: name, calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0,
    portionSize: 1, portionUnit: '人前', uniqueKey: `Home|${name}|人前`, ...extra,
  };
}

async function get(id: string) {
  return (await call(`/api/food-masters/${id}`)).json<Record<string, unknown>>();
}

/** ラベルに5項目と食塩だけが書かれたポテトチップス 60 g */
async function labelChips(extra: Record<string, unknown> = {}) {
  return call('/api/food-masters', {
    method: 'POST',
    body: food(POTATO_CHIPS, 'ポテトチップス うすしお', {
      calories: 336, protein: 3.2, fat: 21.6, netCarbs: 31.4, dietaryFiber: 2.4, saltEquivalent: 0.6,
      nutrientSource: 'label', portionUnit: '袋', uniqueKey: 'Home|ポテトチップス うすしお|袋', ...extra,
    }),
  });
}

describe('成分表だけから値を取る食品', () => {
  it('食材と重さから、最初の5項目も含めて全部を計算する', async () => {
    const res = await call('/api/food-masters', {
      method: 'POST',
      body: food(OYAKODON, '親子丼', {
        nutrientSource: 'composition_table',
        components: [{ foodNumber: RICE, grams: 250 }, { foodNumber: OYAKO, grams: 200 }],
      }),
    });
    expect(res.status).toBe(201);

    const fetched = await get(OYAKODON);
    expect(fetched).toMatchObject({
      calories: 592, protein: 23.05, fat: 11.15, netCarbs: 99.4, dietaryFiber: 4.55, saltEquivalent: 2,
      potassium: 312.5, calcium: 49.5, vitaminA: 114, vitaminD: 1.4, vitaminC: 4,
      nutrientSource: 'composition_table', nutrientSources: {},
    });
    expect(fetched.components).toEqual([
      { foodNumber: RICE, grams: 250, name: 'めし' },
      { foodNumber: OYAKO, grams: 200, name: '親子丼の具' },
    ]);
  });

  it('食材が1つなら、その食品番号を参照先にする', async () => {
    await call('/api/food-masters', {
      method: 'POST',
      body: food(OYAKODON, 'ごはん', { nutrientSource: 'composition_table', components: [{ foodNumber: RICE, grams: 150 }] }),
    });
    expect(await get(OYAKODON)).toMatchObject({ calories: 234, nutrientSourceRef: RICE });
  });
});

describe('ラベルの値を持つ食品を成分表で補う', () => {
  it('分からない栄養素だけを補い、ラベルの値は残す', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });

    const fetched = await get(POTATO_CHIPS);
    expect(fetched).toMatchObject({
      calories: 336, protein: 3.2, saltEquivalent: 0.6,
      potassium: 720, calcium: 10.2, saturatedFat: 2.316,
      nutrientSource: 'label',
    });
    expect(fetched.nutrientSources).toMatchObject({ potassium: 'composition_table', saturatedFat: 'composition_table' });
    expect(fetched.nutrientSources).not.toHaveProperty('saltEquivalent');
  });

  it('成分表でも未測定の栄養素は分からないまま', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    expect(await get(POTATO_CHIPS)).not.toHaveProperty('vitaminD');
  });

  it('補った値を手で直すと、印が外れ、ひも付けを直しても書き換えない', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    await call(`/api/food-masters/${POTATO_CHIPS}`, { method: 'PUT', body: { potassium: 650 } });
    expect(await get(POTATO_CHIPS)).toMatchObject({ potassium: 650 });
    expect((await get(POTATO_CHIPS)).nutrientSources).not.toHaveProperty('potassium');

    await call(`/api/food-masters/${POTATO_CHIPS}`, { method: 'PUT', body: { components: [{ foodNumber: CHIPS, grams: 30 }] } });
    expect(await get(POTATO_CHIPS)).toMatchObject({ potassium: 650, calcium: 5.1 });
  });

  it('ひも付けを外すと、補っていた値は分からないに戻る', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    await call(`/api/food-masters/${POTATO_CHIPS}`, { method: 'PUT', body: { components: [] } });

    const fetched = await get(POTATO_CHIPS);
    expect(fetched).not.toHaveProperty('potassium');
    expect(fetched).toMatchObject({ saltEquivalent: 0.6, nutrientSources: {}, components: [] });
  });

  it('古い版のアプリの更新は、ひも付けも補った値も消さない', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    await call(`/api/food-masters/${POTATO_CHIPS}`, {
      method: 'PUT',
      body: { brandName: 'Home', productName: 'ポテトチップス うすしお', calories: 330, protein: 3.2, fat: 21.6, netCarbs: 31.4, dietaryFiber: 2.4, portionSize: 1, portionUnit: '袋' },
    });

    const fetched = await get(POTATO_CHIPS);
    expect(fetched).toMatchObject({ calories: 330, potassium: 720, nutrientSources: { potassium: 'composition_table' } });
    expect(fetched.components).toHaveLength(1);
  });
});

describe('送られたひも付けを確かめる', () => {
  it('成分表に無い食品番号や重さの無い行は 400 で、食品も作らない', async () => {
    const bad = await labelChips({ components: [{ foodNumber: '99999', grams: 60 }] });
    expect(bad.status).toBe(400);
    expect((await call(`/api/food-masters/${POTATO_CHIPS}`)).status).toBe(404);

    expect((await labelChips({ components: [{ foodNumber: CHIPS }] })).status).toBe(400);
  });

  it('食品を消すと、ひも付けも消える', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    await call(`/api/food-masters/${POTATO_CHIPS}`, { method: 'DELETE' });
    const { results } = await env.DB.prepare('SELECT * FROM food_master_components').all();
    expect(results).toHaveLength(0);
  });
});

describe('管理者の作業', () => {
  it('ひも付けの無い食品を、記録の多い順に返す', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    await call('/api/food-masters', { method: 'POST', body: food(OYAKODON, '親子丼', {}) });
    const third = '33333333-3333-3333-3333-333333333333';
    await call('/api/food-masters', { method: 'POST', body: food(third, 'うどん', {}) });
    for (const [i, id] of [[1, third], [2, third], [3, OYAKODON]] as const) {
      await env.DB.prepare(
        `INSERT INTO log_items (id, user_id, timestamp, log_date, meal_type, food_master_id) VALUES (?, 'user-b', '2026-11-01T12:00:00Z', '2026-11-01', 'Lunch', ?)`,
      ).bind(`log-${i}`, id).run();
    }

    const res = await call('/api/admin/food-masters/unlinked', { user: 'admin-user' });
    const { items } = await res.json<{ items: { id: string; logCount: number }[] }>();
    expect(items.map((i) => [i.id, i.logCount])).toEqual([[third, 2], [OYAKODON, 1]]);
  });

  it('管理者でなければ 403', async () => {
    expect((await call('/api/admin/food-masters/unlinked')).status).toBe(403);
    expect((await call('/api/admin/composition/recompute', { method: 'POST' })).status).toBe(403);
  });

  it('成分表の値が変われば、計算し直しで食品の値も変わる', async () => {
    await labelChips({ components: [{ foodNumber: CHIPS, grams: 60 }] });
    await env.DB.prepare(`UPDATE composition_foods SET potassium = 1000 WHERE food_number = ?`).bind(CHIPS).run();

    const res = await call('/api/admin/composition/recompute', { method: 'POST', user: 'admin-user' });
    expect(await res.json()).toEqual({ recomputed: 1 });
    expect(await get(POTATO_CHIPS)).toMatchObject({ potassium: 600 });
  });
});
