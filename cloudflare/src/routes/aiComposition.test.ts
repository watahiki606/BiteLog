/// <reference types="@cloudflare/vitest-pool-workers" />
import { env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from 'vitest';
import app from '../index';
import { issueSessionJwt } from '../middleware/auth';
import { applySchema } from '../test/schema';
import { resetCatalogCache } from '../lib/aiComposition';
import { compositionFoodUpsert } from '../lib/composition';

// 写真の解析で、料理を成分表の食材と重さに分けさせ、値は食品に入れた国の一覧の食品から引く

const SECRET = 'ai-composition-test-secret';

type Request = { instructions: string; text: { format: { schema: { properties: Record<string, unknown>; required: string[] } } } };
let lastRequest: Request;
let answer: object = {};

beforeAll(async () => {
  await applySchema(env.DB);
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    if (input.toString() !== 'https://api.openai.com/v1/responses') throw new Error(`Unexpected fetch: ${input}`);
    lastRequest = JSON.parse(init?.body as string);
    return Response.json({ output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(answer) }] }] });
  });
});

afterAll(() => vi.unstubAllGlobals());

beforeEach(async () => {
  resetCatalogCache();
  await env.DB.prepare('DELETE FROM food_masters').run();
  for (const [num, name, values] of [
    ['01088', 'こめ ［水稲めし］ 精白米 うるち米', { calories: 156, protein: 2.5, fat: 0.3, net_carbs: 35.6, dietary_fiber: 1.5, salt_equivalent: 0, potassium: 29, vitamin_d: 0 }],
    ['18030', '和風料理 煮物類 親子丼の具', { calories: 101, protein: 8.4, fat: 5.2, net_carbs: 5.2, dietary_fiber: 0.4, salt_equivalent: 1.0, potassium: 120, vitamin_d: 0.7 }],
  ] as const) {
    const { sql, binds } = compositionFoodUpsert(num, name, values);
    await env.DB.prepare(sql).bind(...binds).run();
  }
  // 国の一覧ではない食品は、成分表の出典で食品番号を持っていても一覧に入れない
  await env.DB.prepare(
    `INSERT INTO food_masters (id, product_name, unique_key, created_by, nutrient_source, nutrient_source_ref)
     VALUES ('mine', '自分のご飯', '|自分のご飯|g', 'test-user', 'composition_table', '01088')`,
  ).run();
});

async function analyze() {
  const token = await issueSessionJwt('test-user', SECRET);
  const res = await app.request('/api/ai/analyze-food', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ imageBase64: 'x' }),
  }, { WORKER_JWT_SECRET: SECRET, OPENAI_API_KEY: 'k', DB: env.DB });
  return res.json<Record<string, unknown>>();
}

const OYAKODON = {
  productName: '親子丼', calories: 700, protein: 25, fat: 20, sugar: 95, dietaryFiber: 2,
  saltEquivalent: null, saturatedFat: null, portion: 1, portionUnit: '人前', confidence: 'medium', menuGuess: '',
  components: [{ foodNumber: '01088', grams: 250 }, { foodNumber: '18030', grams: 200 }],
};

describe('写真の解析と成分表', () => {
  it('指示の末尾に成分表の一覧を置き、食材と重さを答えさせる', async () => {
    answer = OYAKODON;
    await analyze();
    expect(lastRequest.instructions).toContain('01088 こめ ［水稲めし］ 精白米 うるち米');
    expect(lastRequest.instructions).not.toContain('自分のご飯');
    expect(lastRequest.text.format.schema.required).toContain('components');
  });

  it('写真から推定したときは、食材と重さから成分表で引いた値を返す', async () => {
    answer = OYAKODON;
    const body = await analyze();
    expect(body).toMatchObject({
      calories: 592, protein: 23.05, saltEquivalent: 2, potassium: 312.5, vitaminD: 1.4,
      components: [
        { foodNumber: '01088', grams: 250, name: 'こめ ［水稲めし］ 精白米 うるち米' },
        { foodNumber: '18030', grams: 200, name: '和風料理 煮物類 親子丼の具' },
      ],
    });
  });

  it('栄養成分表示から読んだときは、読んだ値を残し、分からない栄養素だけを補う', async () => {
    answer = { ...OYAKODON, confidence: 'high', calories: 650, saltEquivalent: 3.1 };
    const body = await analyze();
    expect(body).toMatchObject({ calories: 650, protein: 25, saltEquivalent: 3.1, potassium: 312.5 });
  });

  it('表に無い食品番号は捨て、食材が残らなければ AI の答えた値のまま', async () => {
    answer = { ...OYAKODON, components: [{ foodNumber: '99999', grams: 100 }] };
    const body = await analyze();
    expect(body).toMatchObject({ calories: 700, netCarbs: 95 });
    expect(body).not.toHaveProperty('components');
    expect(body).not.toHaveProperty('potassium');
  });
});

describe('読み違いの安全策', () => {
  it('1食で食塩が 20 g を超える食材の組は使わず、AI の答えた値に戻す', async () => {
    // 親子丼の具 2.5 kg は食塩 25 g になる
    answer = { ...OYAKODON, components: [{ foodNumber: '18030', grams: 2500 }] };
    const body = await analyze();
    expect(body).toMatchObject({ calories: 700 });
    expect(body).not.toHaveProperty('components');
  });
});
