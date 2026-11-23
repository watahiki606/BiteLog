/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';
import { compositionSearchText } from '../lib/composition';

// 成分表の食品を、普段の言葉で探せるか。値は 100 g あたりで、未測定は省く

beforeAll(() => applySchema(env.DB));

async function insert(foodNumber: string, name: string, values: Record<string, number | null>, remarks = '') {
  const columns = Object.keys(values);
  await env.DB.prepare(
    `INSERT INTO composition_foods (food_number, food_group, name, search_text, edition, ${columns.join(', ')}, raw_json)
     VALUES (?, ?, ?, ?, 'test', ${columns.map(() => '?').join(', ')}, '{}')`,
  ).bind(foodNumber, foodNumber.slice(0, 2), name, compositionSearchText(name, remarks), ...Object.values(values)).run();
}

beforeEach(async () => {
  await env.DB.prepare('DELETE FROM composition_foods').run();
  await insert('01088', 'こめ ［水稲めし］ 精白米 うるち米', { calories: 156, net_carbs: 35.6, vitamin_d: 0 });
  await insert('11220', '＜鳥肉類＞ にわとり ［若どり・主品目］ むね 皮なし 生', { calories: 105, potassium: 370, vitamin_d: null });
  await insert('11221', '＜鳥肉類＞ にわとり ［若どり・主品目］ むね 皮なし 焼き', { calories: 177 });
  await insert('01004', 'えんばく オートミール', { calories: 350 }, '別名： オート、オーツ');
});

async function call(path: string) {
  return SELF.fetch(`http://localhost${path}`, {
    headers: { Authorization: `Bearer ${await issueSessionJwt('user-a', 'dev-and-test-secret')}` },
  });
}

async function search(q: string) {
  const res = await call(`/api/composition-foods?q=${encodeURIComponent(q)}`);
  return (await res.json<{ items: { foodNumber: string }[] }>()).items.map((i) => i.foodNumber);
}

describe('成分表の検索', () => {
  it('「ご飯」でめしが見つかる', async () => {
    expect(await search('ご飯')).toEqual(['01088']);
  });

  it('「鶏むね肉 焼き」で、にわとりのむねの焼きが見つかる', async () => {
    expect(await search('鶏むね肉 焼き')).toEqual(['11221']);
  });

  it('語を足すほど絞られ、名前の短いものが先に出る', async () => {
    expect(await search('鶏むね')).toEqual(['11220', '11221']);
  });

  it('別名でも見つかる', async () => {
    expect(await search('オーツ')).toEqual(['01004']);
  });

  it('空の検索語には何も返さない', async () => {
    expect(await search('  ')).toEqual([]);
  });

  it('1食品を、100 g あたりの値で返す。未測定は省き、0 は残す', async () => {
    const res = await call('/api/composition-foods/11220');
    const body = await res.json<{ per100g: Record<string, number> }>();
    expect(body).toMatchObject({ foodNumber: '11220', per100g: { calories: 105, potassium: 370 } });
    expect(body.per100g).not.toHaveProperty('vitaminD');

    const rice = await (await call('/api/composition-foods/01088')).json<{ per100g: Record<string, number> }>();
    expect(rice.per100g.vitaminD).toBe(0);
  });

  it('無い食品番号は 404', async () => {
    expect((await call('/api/composition-foods/99999')).status).toBe(404);
  });
});
