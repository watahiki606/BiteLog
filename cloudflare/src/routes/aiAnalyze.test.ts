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

let openaiHandler: FetchHandler = async () =>
  Response.json({ choices: [{ message: { content: JSON.stringify(VALID_ANALYSIS) } }] });

let lastOpenaiRequestBody: unknown;

beforeAll(() => {
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = input.toString();
    if (url === 'https://api.openai.com/v1/chat/completions') {
      lastOpenaiRequestBody = init?.body ? JSON.parse(init.body as string) : undefined;
      return await openaiHandler(input, init);
    }
    throw new Error(`Unexpected fetch in test: ${url}`);
  });
});

afterAll(() => {
  vi.unstubAllGlobals();
});

beforeEach(() => {
  openaiHandler = async () =>
    Response.json({ choices: [{ message: { content: JSON.stringify(VALID_ANALYSIS) } }] });
  lastOpenaiRequestBody = undefined;
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

    const reqBody = lastOpenaiRequestBody as {
      model: string;
      reasoning_effort: string;
      response_format: { type: string; json_schema: { strict: boolean } };
    };
    expect(reqBody.model).toBe('gpt-6-luna');
    expect(reqBody.reasoning_effort).toBe('none');
    expect(reqBody.response_format.type).toBe('json_schema');
    expect(reqBody.response_format.json_schema.strict).toBe(true);
  });

  it('指示は system に置き、user には画像だけを送る', async () => {
    await analyzeFood({ imageBase64: 'abc' }, await authHeader());

    const { messages } = lastOpenaiRequestBody as { messages: Array<{ role: string; content: unknown }> };
    expect(messages.map((m) => m.role)).toEqual(['system', 'user']);
    expect(typeof messages[0].content).toBe('string');
    expect(messages[1].content).toEqual([
      { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,abc', detail: 'high' } },
    ]);
  });

  it('noteを指定すると user に補足として画像の前に付ける', async () => {
    await analyzeFood({ imageBase64: 'dummy', note: ' マクドナルドのビッグマック ' }, await authHeader());

    const { messages } = lastOpenaiRequestBody as {
      messages: Array<{ role: string; content: Array<{ type: string; text?: string }> }>;
    };
    expect(messages[1].content[0]).toEqual({ type: 'text', text: 'User note: マクドナルドのビッグマック' });
    expect(messages[1].content[1].type).toBe('image_url');
  });

  it('noteが空白だけの場合は補足を付けない', async () => {
    await analyzeFood({ imageBase64: 'dummy', note: '   ' }, await authHeader());

    const { messages } = lastOpenaiRequestBody as {
      messages: Array<{ role: string; content: Array<{ type: string }> }>;
    };
    expect(messages[1].content.map((part) => part.type)).toEqual(['image_url']);
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
    openaiHandler = async () => Response.json({ choices: [{ message: { content: '' } }] });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(500);
    const body = await res.json<{ error: string }>();
    expect(body.error).toBe('No content from AI');
  });

  it('contentが不正なJSONの場合は500になる', async () => {
    openaiHandler = async () =>
      Response.json({ choices: [{ message: { content: 'not json' } }] });

    const res = await analyzeFood({ imageBase64: 'dummy' }, await authHeader());
    expect(res.status).toBe(500);
    const body = await res.json<{ error: string }>();
    expect(body.error).toBe('Failed to parse AI response');
  });
});
