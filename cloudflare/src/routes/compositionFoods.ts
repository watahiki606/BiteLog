// 日本食品標準成分表の食品を探す。食品の入力で成分表から値を選ぶときに使う。
import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';
import { COMPOSITION_NUTRIENTS, compositionSearchWords } from '../lib/composition';

export type CompositionFoodRow = {
  food_number: string;
  food_group: string;
  name: string;
  edition: string;
  [nutrientColumn: string]: unknown;
};

const SELECT_COLUMNS = ['food_number', 'food_group', 'name', 'edition', ...COMPOSITION_NUTRIENTS.map((n) => n.column)].join(', ');

/** 100 g あたりの値。成分表で未測定の栄養素はキーごと省く */
export function compositionFoodToResponse(row: CompositionFoodRow) {
  const per100g: Record<string, number> = {};
  for (const n of COMPOSITION_NUTRIENTS) {
    const value = row[n.column];
    if (typeof value === 'number') per100g[n.id] = value;
  }
  return { foodNumber: row.food_number, foodGroup: row.food_group, name: row.name, edition: row.edition, per100g };
}

const compositionFoods = new Hono<{ Bindings: Bindings; Variables: Variables }>()
  .use('*', authMiddleware)
  .get('/', async (c) => {
    const words = compositionSearchWords(c.req.query('q') ?? '');
    const limit = Math.min(Math.max(parseInt(c.req.query('limit') ?? '20') || 20, 1), 100);
    if (words.length === 0) return c.json({ items: [] });

    // 語ごとに search_text に含まれることを求める。名前の短いものほど一般的な食品なので先に出す
    const where = words.map(() => 'instr(search_text, ?) > 0').join(' AND ');
    const { results } = await c.env.DB.prepare(
      `SELECT ${SELECT_COLUMNS} FROM composition_foods WHERE ${where} ORDER BY length(name), food_number LIMIT ?`,
    ).bind(...words, limit).all<CompositionFoodRow>();
    return c.json({ items: results.map(compositionFoodToResponse) });
  })
  .get('/:foodNumber', async (c) => {
    const row = await c.env.DB.prepare(`SELECT ${SELECT_COLUMNS} FROM composition_foods WHERE food_number = ?`)
      .bind(c.req.param('foodNumber')).first<CompositionFoodRow>();
    if (!row) return c.json({ error: 'Not found' }, 404);
    return c.json(compositionFoodToResponse(row));
  });

export default compositionFoods;
