import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';

const aiAnalyze = new Hono<{ Bindings: Bindings; Variables: Variables }>();
aiAnalyze.use('*', authMiddleware);

const PROMPT = `Analyze this image and return nutrition information in JSON format.

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

Return ONLY this JSON format (no other text):
{
  "productName": "Product or dish name in Japanese",
  "calories": number in kcal,
  "protein": number in grams,
  "fat": number in grams,
  "sugar": number in grams,
  "dietaryFiber": number in grams,
  "portion": portion amount (number),
  "portionUnit": "unit (e.g., g, ml, 個, 人前)",
  "confidence": "high" or "medium" or "low"
}

Rules:
- If nutrition label exists, read and use those exact values
- For food photos without labels, estimate typical serving size
- For multiple items, sum the total values
- Return JSON only, no explanations`;

aiAnalyze.post('/analyze-food', async (c) => {
  const body = await c.req.json<{ imageBase64?: string }>();

  if (!body.imageBase64 || typeof body.imageBase64 !== 'string') {
    return c.json({ error: 'imageBase64 is required' }, 400);
  }

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
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: PROMPT },
              {
                type: 'image_url',
                image_url: { url: `data:image/jpeg;base64,${body.imageBase64}` },
              },
            ],
          },
        ],
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

  const parsed = extractAndParseJSON(content);
  if (!parsed) {
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

function extractAndParseJSON(text: string): Record<string, unknown> | null {
  const fenceMatch = text.match(/```json\s*([\s\S]*?)```/);
  const candidate = fenceMatch ? fenceMatch[1].trim() : text.trim();

  const start = candidate.indexOf('{');
  const end = candidate.lastIndexOf('}');
  if (start === -1 || end === -1) return null;

  try {
    return JSON.parse(candidate.slice(start, end + 1)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export default aiAnalyze;
