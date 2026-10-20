/// <reference types="@cloudflare/vitest-pool-workers" />
import { describe, it, expect, beforeAll, afterAll, beforeEach, vi } from 'vitest';
import app from '../index';
import { issueSessionJwt } from '../middleware/auth';

const TEST_SECRET = 'ai-analyze-test-secret';
const TEST_ENV = {
  WORKER_JWT_SECRET: TEST_SECRET,
  OPENAI_API_KEY: 'test-openai-key',
};

const VALID_ANALYSIS = {
  productName: 'おにぎり',
  calories: 180,
  protein: 4,
  fat: 1,
  sugar: 38,
  dietaryFiber: 1,
  portion: 1,
  portionUnit: '個',
  confidence: 'medium',
};

type FetchHandler = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type SearchCall = { type: 'web_search_call'; action: { type: 'search'; sources: Array<{ type: 'url'; url: string }> } };

function openaiResponse(content: object | string, searches: SearchCall[] = []) {
  const text = typeof content === 'string' ? content : JSON.stringify(content);
  return Response.json({
    output: [...searches, { type: 'message', content: [{ type: 'output_text', text, annotations: [] }] }],
  });
}

function searchCall(...urls: string[]): SearchCall {
  return { type: 'web_search_call', action: { type: 'search', sources: urls.map((url) => ({ type: 'url', url })) } };
}

let openaiHandler: FetchHandler = async () => openaiResponse(VALID_ANALYSIS);

type OpenaiRequest = {
  model: string;
  reasoning: { effort: string };
  instructions: string;
  input: Array<{ role: string; content: Array<{ type: string; text?: string; image_url?: string; detail?: string }> }>;
  text: { format: { type: string; strict: boolean; schema: { properties: Record<string, unknown>; required: string[] } } };
  tools?: Array<{ type: string }>;
  include?: string[];
};

let lastOpenaiRequestBody: OpenaiRequest;

beforeAll(() => {
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = input.toString();
    if (url === 'https://api.openai.com/v1/responses') {
      lastOpenaiRequestBody = JSON.parse(init?.body as string);
      return await openaiHandler(input, init);
    }
    throw new Error(`Unexpected fetch in test: ${url}`);
  });
});

afterAll(() => {
  vi.unstubAllGlobals();
});

beforeEach(() => {
  openaiHandler = async () => openaiResponse(VALID_ANALYSIS);
});

async function authHeader(): Promise<Record<string, string>> {
  const token = await issueSessionJwt('test-user', TEST_SECRET);
  return { Authorization: `Bearer ${token}` };
}

function analyzeFood(body: object, headers: Record<string, string>) {
  return app.request(
    '/api/ai/analyze-food',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
    },
    TEST_ENV
  );
}

describe('POST /api/ai/analyze-food', () => {
  it('imageBase64がない場合は400', async () => {
    const res = await analyzeFood({}, await authHeader());
    expect(res.status).toBe(400);
  });

  it('未認証の場合は401', async () => {
    const res = await analyzeFood({ imageBase64: 'dummy' }, {});
    expect(res.status).toBe(401);
  });

  it('AIの解析結果をレスポンス形式にマッピングする', async () => {
    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());

    expect(res.status).toBe(200);
    const body = await res.json<Record<string, unknown>>();
    expect(body).toEqual({
      productName: 'おにぎり',
      calories: 180,
      protein: 4,
      fat: 1,
      netCarbs: 38,
      dietaryFiber: 1,
      portionAmount: 1,
      portionUnit: '個',
      confidence: 'medium',
    });
  });

  it('GPT-6 Luna に推論なしで、Structured Outputs を指定して送る', async () => {
    await analyzeFood({ imageBase64: 'dummy' }, await authHeader());

    const req = lastOpenaiRequestBody;
    expect(req.model).toBe('gpt-6-luna');
    expect(req.reasoning.effort).toBe('none');
    expect(req.text.format.type).toBe('json_schema');
    expect(req.text.format.strict).toBe(true);
  });

  it('指示は instructions に置き、user には画像だけを送る', async () => {
    await analyzeFood({ imageBase64: 'abc' }, await authHeader());

    const req = lastOpenaiRequestBody;
    expect(typeof req.instructions).toBe('string');
    expect(req.input).toEqual([
      { role: 'user', content: [{ type: 'input_image', image_url: 'data:image/jpeg;base64,abc', detail: 'high' }] },
    ]);
  });

  it('noteを指定すると user に補足として画像の前に付ける', async () => {
    await analyzeFood({ imageBase64: 'dummy', note: ' 半分残した ' }, await authHeader());

    const content = lastOpenaiRequestBody.input[0].content;
    expect(content[0]).toEqual({ type: 'input_text', text: 'User note: 半分残した' });
    expect(content[1].type).toBe('input_image');
  });

  it('noteが空白だけの場合は補足を付けない', async () => {
    await analyzeFood({ imageBase64: 'dummy', note: '   ' }, await authHeader());

    expect(lastOpenaiRequestBody.input[0].content.map((part) => part.type)).toEqual(['input_image']);
  });

  it('写真に見えた店名とメニュー名の見当を答えさせる', async () => {
    await analyzeFood({ imageBase64: 'dummy' }, await authHeader());

    expect(lastOpenaiRequestBody.text.format.schema.required).toContain('menuGuess');
    expect(lastOpenaiRequestBody.instructions).toContain('menuGuess');
  });

  it('見当があれば返す', async () => {
    openaiHandler = async () => openaiResponse({ ...VALID_ANALYSIS, menuGuess: 'くら寿司 サーモン' });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());

    expect((await res.json<Record<string, unknown>>()).menuGuess).toBe('くら寿司 サーモン');
  });

  it('見当が空なら返さない', async () => {
    openaiHandler = async () => openaiResponse({ ...VALID_ANALYSIS, menuGuess: '' });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());

    expect(await res.json<Record<string, unknown>>()).not.toHaveProperty('menuGuess');
  });

  it('menuNameが無ければWeb検索を使わない', async () => {
    await analyzeFood({ imageBase64: 'dummy', note: 'スシロー' }, await authHeader());

    expect(lastOpenaiRequestBody.tools).toBeUndefined();
  });

  it('menuNameが空白だけならWeb検索を使わない', async () => {
    await analyzeFood({ imageBase64: 'dummy', menuName: '  ' }, await authHeader());

    expect(lastOpenaiRequestBody.tools).toBeUndefined();
    expect(lastOpenaiRequestBody.reasoning.effort).toBe('none');
  });

  it('OpenAIが429を返した場合はレート制限エラーになる', async () => {
    openaiHandler = async () => new Response('rate limited', { status: 429 });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(429);
  });

  it('OpenAIが401を返した場合はAI設定エラーになる', async () => {
    openaiHandler = async () => new Response('unauthorized', { status: 401 });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(502);
  });

  it('OpenAIがその他のエラーを返した場合は500になる', async () => {
    openaiHandler = async () => new Response('error', { status: 500 });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(500);
  });

  it('OpenAI呼び出し自体が失敗した場合は500になる', async () => {
    openaiHandler = async () => {
      throw new Error('network error');
    };

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(500);
    const body = await res.json<{ error: string }>();
    expect(body.error).toBe('Failed to reach OpenAI API');
  });

  it('contentが空の場合は500になる', async () => {
    openaiHandler = async () => openaiResponse('');

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(500);
    const body = await res.json<{ error: string }>();
    expect(body.error).toBe('No content from AI');
  });

  it('contentが不正なJSONの場合は500になる', async () => {
    openaiHandler = async () => openaiResponse('not json');

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(500);
    const body = await res.json<{ error: string }>();
    expect(body.error).toBe('Failed to parse AI response');
  });
});

describe('POST /api/ai/analyze-food に menuName を付けたとき', () => {
  const OFFICIAL = { ...VALID_ANALYSIS, productName: 'サーモン（くら寿司）', calories: 93, basis: 'official' };
  const PDF = 'https://www.kurasushi.co.jp/common/pdf/kura_allergen.pdf';

  it('Web検索を有効にし、推論を low にして、検索で見たページも受け取る', async () => {
    await analyzeFood({ imageBase64: 'dummy', menuName: 'くら寿司 サーモン' }, await authHeader());

    const req = lastOpenaiRequestBody;
    expect(req.tools).toEqual([{ type: 'web_search' }]);
    expect(req.reasoning.effort).toBe('low');
    expect(req.include).toEqual(['web_search_call.action.sources']);
  });

  it('店名を user の先頭に、メモより前に付ける', async () => {
    await analyzeFood({ imageBase64: 'dummy', menuName: ' くら寿司 サーモン ', note: '1貫だけ' }, await authHeader());

    const content = lastOpenaiRequestBody.input[0].content;
    expect(content.map((part) => part.text ?? part.type)).toEqual([
      'Restaurant or product: くら寿司 サーモン',
      'User note: 1貫だけ',
      'input_image',
    ]);
  });

  it('値の根拠と出典を答えさせる', async () => {
    await analyzeFood({ imageBase64: 'dummy', menuName: 'くら寿司 サーモン' }, await authHeader());

    expect(lastOpenaiRequestBody.text.format.schema.required).toEqual(expect.arrayContaining(['basis', 'sourceUrl']));
  });

  it('検索で見たページの出典なら、根拠と一緒に返す', async () => {
    openaiHandler = async () => openaiResponse({ ...OFFICIAL, sourceUrl: PDF }, [searchCall('https://example.com/a', PDF)]);

    const res = await analyzeFood({ imageBase64: 'dummy', menuName: 'くら寿司 サーモン' }, await authHeader());

    const body = await res.json<Record<string, unknown>>();
    expect(body.calories).toBe(93);
    expect(body.basis).toBe('official');
    expect(body.sourceUrl).toBe(PDF);
  });

  it('検索で見ていないページの出典は返さない', async () => {
    openaiHandler = async () =>
      openaiResponse({ ...OFFICIAL, sourceUrl: 'https://www.kurasushi.co.jp/menu/' }, [searchCall(PDF)]);

    const res = await analyzeFood({ imageBase64: 'dummy', menuName: 'くら寿司 サーモン' }, await authHeader());

    const body = await res.json<Record<string, unknown>>();
    expect(body.basis).toBe('official');
    expect(body).not.toHaveProperty('sourceUrl');
  });

  it('写真からの推定なら、出典は返さない', async () => {
    openaiHandler = async () =>
      openaiResponse({ ...VALID_ANALYSIS, basis: 'estimate', sourceUrl: '' }, [searchCall(PDF)]);

    const res = await analyzeFood({ imageBase64: 'dummy', menuName: 'とんから亭 棒ひれかつ定食' }, await authHeader());

    const body = await res.json<Record<string, unknown>>();
    expect(body.basis).toBe('estimate');
    expect(body).not.toHaveProperty('sourceUrl');
  });
});
