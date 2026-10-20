import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';

const aiAnalyze = new Hono<{ Bindings: Bindings; Variables: Variables }>();
aiAnalyze.use('*', authMiddleware);

const SYSTEM_PROMPT = `You estimate nutrition from a food photo for a meal-logging app. The app saves your answer as what the user is eating right now, so every value must describe the amount one person eats in this sitting.

Deciding the amount
- Nutrition label given per 100 g or 100 ml: scale every value to the full content of the package (内容量). For example, 250 kcal per 100 g in a 120 g pack becomes 300 kcal for 120 g.
- Nutrition label given per unit (1個, 1本, 1袋, 1包装, 1缶, 1食): return that one unit as printed, even when the box holds several.
- Food without a label: estimate one person's serving. When the same dish is served for several people, or other plates appear in the background, count only the main plate in the foreground and the side dishes that go with it. Add up the different dishes that make up that one person's meal.
- portion and portionUnit state that amount, e.g. 120 g, 500 ml, 1 個, 1 人前.

Reading a nutrition label
- Copy the printed numbers as they are, then scale them only when the rules above require it.
- Energy is エネルギー or 熱量. Protein is たんぱく質 or 蛋白質. Fat is 脂質.
- sugar means 糖質, the net carbohydrates. If 糖質 and 食物繊維 are printed, use them. If only 炭水化物 and 食物繊維 are printed, sugar is 炭水化物 minus 食物繊維. If only 炭水化物 is printed, sugar is 炭水化物 and dietaryFiber is 0.

productName
- Write it in Japanese. Start with the general name of the food, such as 親子丼, 鮭おにぎり or 缶コーヒー, and put the product name or details after it in （）. The app looks up the user's past logs with the text before the first space or bracket.
- Use a name printed on the package as written. Do not add a brand, flavor or product line you cannot see. Do not add words such as 推定.

confidence
- high: the values come from a nutrition label.
- medium: the dish is clear and the amount is a typical serving.
- low: the dish or the amount is uncertain.

The user may add a note. The note overrides what the photo suggests: use it to identify the food and to adjust the amount actually eaten, such as 半分残した, 2個食べた or 全部.`;

// 店名が入ったときだけ足す。評価では、店名が無いのに検索させると皿の形から店を決めつけて調べ、
// 費用も約10倍になったので、検索は店名があるときに限る
const NAMED_RULES = `

The user named the restaurant or product
- The user's message gives the restaurant or product name. Search the web for the official nutrition values published by that restaurant or manufacturer for this item.
- If a nutrition label is visible in the photo, use the label and do not search.
- When several menu items match the name, pick the one that matches the photo.
- Official values are often given per plate, per set or per package. Scale them to the amount in the photo and in the note. For example, when the official value is for a plate of two pieces and the photo shows one piece, return one piece.
- If you cannot find official values for this item, estimate from the photo as described above.

basis
- label: the values come from a nutrition label in the photo.
- official: the values come from nutrition values published by the restaurant or manufacturer.
- estimate: you estimated the values from the photo.

sourceUrl
- When basis is official, the URL of the page you took the values from. Otherwise an empty string.`;

const RESPONSE_FORMAT = {
  type: 'json_schema',
  name: 'food_nutrition_analysis',
  strict: true,
  schema: {
    type: 'object',
    properties: {
      productName: {
        type: 'string',
        description: 'Japanese name: the general food name first, details in （）',
      },
      calories: {
        type: 'number',
        description: 'kcal for the portion',
      },
      protein: {
        type: 'number',
        description: 'Protein in grams for the portion',
      },
      fat: {
        type: 'number',
        description: 'Fat in grams for the portion',
      },
      sugar: {
        type: 'number',
        description: '糖質 (net carbohydrates) in grams for the portion',
      },
      dietaryFiber: {
        type: 'number',
        description: '食物繊維 in grams for the portion',
      },
      portion: {
        type: 'number',
        description: 'The amount the user is eating now',
      },
      portionUnit: {
        type: 'string',
        description: 'Unit of portion, e.g. g, ml, 個, 人前',
      },
      confidence: {
        type: 'string',
        enum: ['high', 'medium', 'low'],
      },
    },
    required: [
      'productName',
      'calories',
      'protein',
      'fat',
      'sugar',
      'dietaryFiber',
      'portion',
      'portionUnit',
      'confidence',
    ],
    additionalProperties: false,
  },
};

const NAMED_RESPONSE_FORMAT = {
  ...RESPONSE_FORMAT,
  schema: {
    ...RESPONSE_FORMAT.schema,
    properties: {
      ...RESPONSE_FORMAT.schema.properties,
      basis: { type: 'string', enum: ['label', 'official', 'estimate'] },
      sourceUrl: { type: 'string', description: 'URL of the page the official values came from, or empty' },
    },
    required: [...RESPONSE_FORMAT.schema.required, 'basis', 'sourceUrl'],
  },
};

// 使う項目だけを書く。type が web_search_call なら action、message なら content を持つ
type OpenAIOutputItem = {
  type: string;
  action?: { sources?: Array<{ url?: string }> };
  content?: Array<{ type: string; text?: string }>;
};

aiAnalyze.post('/analyze-food', async (c) => {
  const body = await c.req.json<{ imageBase64?: string; note?: string; menuName?: string }>();

  if (!body.imageBase64 || typeof body.imageBase64 !== 'string') {
    return c.json({ error: 'imageBase64 is required' }, 400);
  }

  const menuName = typeof body.menuName === 'string' ? body.menuName.trim() : '';
  const note = typeof body.note === 'string' ? body.note.trim() : '';

  const userContent: Array<
    | { type: 'input_text'; text: string }
    | { type: 'input_image'; image_url: string; detail: 'high' }
  > = [];

  if (menuName) userContent.push({ type: 'input_text', text: `Restaurant or product: ${menuName}` });
  if (note) userContent.push({ type: 'input_text', text: `User note: ${note}` });

  // detail を指定しないと GPT-6 Luna は画像をほぼ原寸で数える。古いアプリは長辺約3072pxで送ってくるので、
  // high で上限をかける。今のアプリが送る1536pxはこの上限に収まり、縮められない
  userContent.push({
    type: 'input_image',
    image_url: `data:image/jpeg;base64,${body.imageBase64}`,
    detail: 'high',
  });

  const request = menuName
    ? {
        // none のまま検索させると、成分表示が写っていても調べ直して個数を変えることがあった
        reasoning: { effort: 'low' },
        instructions: SYSTEM_PROMPT + NAMED_RULES,
        text: { format: NAMED_RESPONSE_FORMAT },
        tools: [{ type: 'web_search' }],
        include: ['web_search_call.action.sources'],
      }
    : {
        // 公式の移行ガイドは minimal なら low から比べるよう勧めている。実写真で比べると
        // none のほうが速く安く、成分表示の読み違いも少なかった
        reasoning: { effort: 'none' },
        instructions: SYSTEM_PROMPT,
        text: { format: RESPONSE_FORMAT },
      };

  let openaiRes: Response;
  try {
    openaiRes = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${c.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-6-luna',
        ...request,
        input: [{ role: 'user', content: userContent }],
        max_output_tokens: 4096,
        store: false,
      }),
    });
  } catch {
    return c.json({ error: 'Failed to reach OpenAI API' }, 500);
  }

  if (!openaiRes.ok) {
    if (openaiRes.status === 429) return c.json({ error: 'Rate limit exceeded' }, 429);
    if (openaiRes.status === 401) return c.json({ error: 'AI service configuration error' }, 502);
    return c.json({ error: 'AI service error' }, 500);
  }

  const openaiData = await openaiRes.json<{ output?: OpenAIOutputItem[] }>();
  const output = openaiData.output ?? [];

  const message = output.find((item) => item.type === 'message');
  const content = message?.content?.find((part) => part.type === 'output_text')?.text;
  if (!content) {
    return c.json({ error: 'No content from AI' }, 500);
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(content) as Record<string, unknown>;
  } catch {
    return c.json({ error: 'Failed to parse AI response' }, 500);
  }

  const result = {
    calories: (parsed['calories'] as number) ?? 0,
    protein: (parsed['protein'] as number) ?? 0,
    fat: (parsed['fat'] as number) ?? 0,
    netCarbs: (parsed['sugar'] as number) ?? 0,
    dietaryFiber: (parsed['dietaryFiber'] as number) ?? 0,
    portionAmount: (parsed['portion'] as number) ?? 1,
    portionUnit: (parsed['portionUnit'] as string) ?? '人前',
    confidence: (parsed['confidence'] as string) ?? 'medium',
    productName: (parsed['productName'] as string) ?? '不明な料理',
  };
  if (!menuName) return c.json(result);

  // モデルは開いていないページの URL を書くことがある。検索で実際に見たページだけを出典にする
  const searchedUrls = new Set(
    output
      .filter((item) => item.type === 'web_search_call')
      .flatMap((item) => (item.action?.sources ?? []).map((source) => source.url))
  );
  const sourceUrl = parsed['sourceUrl'];
  return c.json({
    ...result,
    basis: (parsed['basis'] as string) ?? 'estimate',
    ...(typeof sourceUrl === 'string' && searchedUrls.has(sourceUrl) ? { sourceUrl } : {}),
  });
});

export default aiAnalyze;
