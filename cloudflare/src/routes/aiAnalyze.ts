import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';

const aiAnalyze = new Hono<{ Bindings: Bindings; Variables: Variables }>();
aiAnalyze.use('*', authMiddleware);

const PROMPT = `Analyze this image and return nutrition information for the food shown.

IMPORTANT - Nutrition Label Reading:
If the image contains a nutrition facts label (package/product label), prioritize reading the text:
- Calories/Energy/カロリー/熱量
- Protein/たんぱく質/タンパク質
- Fat/脂質
- Sugar/Carbohydrate/糖質
- Dietary Fiber/食物繊維
- Total Carbohydrates/炭水化物
If "糖質" and "食物繊維" are both listed, use those values directly. If only "炭水化物" is listed, set sugar = 炭水化物 and dietaryFiber = 0.
If a nutrition label is present, set confidence to "high".

IMPORTANT - Portion:
"portion"/"portionUnit" describe BOTH the basis for all returned nutrition values AND the amount the user is about to log as eaten right now - they refer to the same quantity.
- If a nutrition label shows "per 100g" values but the visible package/container holds a different total amount, scale ALL nutrition values up from the label to the whole package, and set portion to the package's total size (not 100) with its unit.
- If the photo shows a dish or serving without a label, set portion/portionUnit to a sensible amount for what is shown (e.g., 1 "人前", or an estimated weight in g) and provide nutrition values for that whole amount.
- For multiple items in one photo, sum the totals into a single result and set portion/portionUnit to describe the combined amount.

If a user note is provided, use it to identify the product/dish, resolve visual ambiguity (e.g., regular vs. sugar-free version), and account for any amount actually consumed (e.g., "half eaten").`;

const RESPONSE_SCHEMA = {
  type: 'json_schema',
  json_schema: {
    name: 'food_nutrition_analysis',
    strict: true,
    schema: {
      type: 'object',
      properties: {
        productName: {
          type: 'string',
          description: 'Product or dish name in Japanese',
        },
        calories: {
          type: 'number',
          description: 'Total calories in kcal for the "portion" amount',
        },
        protein: {
          type: 'number',
          description: 'Protein in grams for the "portion" amount',
        },
        fat: {
          type: 'number',
          description: 'Fat in grams for the "portion" amount',
        },
        sugar: {
          type: 'number',
          description: '糖質 (sugar/net carbs) in grams for the "portion" amount',
        },
        dietaryFiber: {
          type: 'number',
          description: '食物繊維 in grams for the "portion" amount',
        },
        portion: {
          type: 'number',
          description: 'The amount that the nutrition values represent and that the user is logging now',
        },
        portionUnit: {
          type: 'string',
          description: 'Unit for portion, e.g. g, ml, 個, 人前',
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
  },
};

aiAnalyze.post('/analyze-food', async (c) => {
  const body = await c.req.json<{ imageBase64?: string; note?: string }>();

  if (!body.imageBase64 || typeof body.imageBase64 !== 'string') {
    return c.json({ error: 'imageBase64 is required' }, 400);
  }

  const messageContent: Array<
    { type: 'text'; text: string } | { type: 'image_url'; image_url: { url: string } }
  > = [{ type: 'text', text: PROMPT }];

  if (typeof body.note === 'string' && body.note.trim()) {
    messageContent.push({ type: 'text', text: `User note: ${body.note.trim()}` });
  }

  messageContent.push({
    type: 'image_url',
    image_url: { url: `data:image/jpeg;base64,${body.imageBase64}` },
  });

  let openaiRes: Response;
  try {
    openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${c.env.OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-5-mini',
        reasoning_effort: 'minimal',
        messages: [{ role: 'user', content: messageContent }],
        response_format: RESPONSE_SCHEMA,
        max_completion_tokens: 4096,
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

  const openaiData = await openaiRes.json<{
    choices: Array<{ message: { content: string } }>;
  }>();

  const content = openaiData.choices?.[0]?.message?.content;
  if (!content) {
    return c.json({ error: 'No content from AI' }, 500);
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(content) as Record<string, unknown>;
  } catch {
    return c.json({ error: 'Failed to parse AI response' }, 500);
  }

  return c.json({
    calories: (parsed['calories'] as number) ?? 0,
    protein: (parsed['protein'] as number) ?? 0,
    fat: (parsed['fat'] as number) ?? 0,
    netCarbs: (parsed['sugar'] as number) ?? 0,
    dietaryFiber: (parsed['dietaryFiber'] as number) ?? 0,
    portionAmount: (parsed['portion'] as number) ?? 1,
    portionUnit: (parsed['portionUnit'] as string) ?? '人前',
    confidence: (parsed['confidence'] as string) ?? 'medium',
    productName: (parsed['productName'] as string) ?? '不明な料理',
  });
});

export default aiAnalyze;
