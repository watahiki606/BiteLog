/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';

// 公開中の古い版のアプリは、食品を作るときと直すときに成分表の食材 components を送ってくる。
// 食品は送られた栄養素の値だけを持つので、components は読まずに捨てる。

beforeAll(() => applySchema(env.DB));

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM log_items'),
    env.DB.prepare('DELETE FROM user_food_stats'),
    env.DB.prepare('DELETE FROM food_masters'),
  ]);
});

async function call(path: string, init: { method?: string; body?: unknown } = {}) {
  return SELF.fetch(`http://localhost${path}`, {
    method: init.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${await issueSessionJwt('user-a', 'dev-and-test-secret')}`,
      'Content-Type': 'application/json',
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
}

const CHIPS_ID = '22222222-2222-2222-2222-222222222222';

/** ラベルに5項目と食塩だけが書かれたポテトチップス 1袋 */
const chips = {
  id: CHIPS_ID, brandName: 'Home', productName: 'ポテトチップス うすしお',
  calories: 336, protein: 3.2, fat: 21.6, netCarbs: 31.4, dietaryFiber: 2.4, saltEquivalent: 0.6,
  portionSize: 1, portionUnit: '袋', uniqueKey: 'Home|ポテトチップス うすしお|袋', nutrientSource: 'label',
};

async function get(id: string) {
  return (await call(`/api/food-masters/${id}`)).json<Record<string, unknown>>();
}

describe('古い版のアプリが送る成分表の食材', () => {
  it('作るときに送られても、送られた値だけで作る', async () => {
    const res = await call('/api/food-masters', {
      method: 'POST', body: { ...chips, components: [{ foodNumber: '15103', grams: 60 }] },
    });
    expect(res.status).toBe(201);

    const fetched = await get(CHIPS_ID);
    expect(fetched).toMatchObject({ calories: 336, saltEquivalent: 0.6 });
    // 成分表から値を補わない。分からない栄養素は応答に載らない
    expect(fetched).not.toHaveProperty('potassium');
    expect(fetched).not.toHaveProperty('components');
    expect(fetched).not.toHaveProperty('nutrientSources');
  });

  it('形のおかしい食材が送られても、作れる', async () => {
    const res = await call('/api/food-masters', {
      method: 'POST', body: { ...chips, components: [{ foodNumber: '99999' }] },
    });
    expect(res.status).toBe(201);
  });

  it('直すときに送られても、送られた値だけを書き換える', async () => {
    await call('/api/food-masters', { method: 'POST', body: chips });
    const res = await call(`/api/food-masters/${CHIPS_ID}`, {
      method: 'PUT', body: { calories: 330, potassium: 720, components: [{ foodNumber: '15103', grams: 60 }] },
    });
    expect(res.status).toBe(200);
    expect(await get(CHIPS_ID)).toMatchObject({ calories: 330, protein: 3.2, potassium: 720, saltEquivalent: 0.6 });
  });
});
