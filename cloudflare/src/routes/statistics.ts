import { Hono } from 'hono';
import type { Bindings, Variables } from '../types';
import { authMiddleware } from '../middleware/auth';
import { NUTRITION_BASE_CTE, NUTRITION_SUM_COLUMNS } from '../lib/nutritionSql';

// 体組成の集計対象カラム（DB snake_case → レスポンス camelCase）。
// 体重等は合計に意味が無いため、同日複数計測は日次 AVG で集約する。
const BODY_AVG_FIELDS: { col: string; key: string }[] = [
  { col: 'weight_kg',             key: 'weightKg' },
  { col: 'body_fat_percent',      key: 'bodyFatPercent' },
  { col: 'muscle_mass_kg',        key: 'muscleMassKg' },
  { col: 'muscle_score',          key: 'muscleScore' },
  { col: 'visceral_fat_level',    key: 'visceralFatLevel' },
  { col: 'basal_metabolism_kcal', key: 'basalMetabolismKcal' },
  { col: 'metabolic_age',         key: 'metabolicAge' },
  { col: 'bone_mass_kg',          key: 'boneMassKg' },
  { col: 'body_water_percent',    key: 'bodyWaterPercent' },
];

const NUTRIENT_KEYS = ['calories', 'protein', 'fat', 'netCarbs', 'dietaryFiber'] as const;

type NutriRow = { log_date: string } & Record<(typeof NUTRIENT_KEYS)[number], number | null>;
type BodyRow = { date: string } & Record<string, number | null>;

const statistics = new Hono<{ Bindings: Bindings; Variables: Variables }>()
  .use('*', authMiddleware)
  // GET /daily?from&to : 日次の栄養合計と体組成平均をサーバー側でマージして返す。
  // 統計ページの「栄養素×体組成」相関グラフ／体組成トレンド用。
  // 生ログを返さず日次集計済みにすることで Worker の CPU 制限を回避する（/log-items/summary と同方針）。
  .get('/daily', async (c) => {
    const userId = c.get('userId');
    const from = c.req.query('from');
    const to = c.req.query('to');
    if (!from || !to) {
      return c.json({ error: 'from and to are required' }, 400);
    }

    // 栄養（日次合計）。base CTE を meal_type で割らず log_date 単位で合算する。
    const nutritionQuery = c.env.DB.prepare(
      `WITH ${NUTRITION_BASE_CTE}
       SELECT log_date, ${NUTRITION_SUM_COLUMNS}
       FROM base
       GROUP BY log_date
       ORDER BY log_date ASC`
    ).bind(userId, from, to).all<NutriRow>();

    // 体組成（日次平均）。measured_at は ISO 日時なので substr で日付化して比較・集約する。
    const bodyAvg = BODY_AVG_FIELDS.map((f) => `AVG(${f.col}) AS ${f.key}`).join(',\n        ');
    const bodyQuery = c.env.DB.prepare(
      `SELECT substr(measured_at, 1, 10) AS date,
        ${bodyAvg}
       FROM body_measurements
       WHERE user_id = ? AND substr(measured_at, 1, 10) BETWEEN ? AND ?
       GROUP BY date
       ORDER BY date ASC`
    ).bind(userId, from, to).all<BodyRow>();

    const [{ results: nutriRows }, { results: bodyRows }] = await Promise.all([nutritionQuery, bodyQuery]);

    // 日付キーで両者をマージ（サーバー側）。栄養欠損は 0、体組成欠損は null。
    const byDate = new Map<string, Record<string, number | null>>();
    const ensure = (date: string) => {
      let row = byDate.get(date);
      if (!row) {
        row = { calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0 };
        for (const f of BODY_AVG_FIELDS) row[f.key] = null;
        byDate.set(date, row);
      }
      return row;
    };

    for (const r of nutriRows) {
      const row = ensure(r.log_date);
      for (const k of NUTRIENT_KEYS) row[k] = r[k] ?? 0;
    }
    for (const r of bodyRows) {
      const row = ensure(r.date);
      for (const f of BODY_AVG_FIELDS) row[f.key] = r[f.key] ?? null;
    }

    const items = [...byDate.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([date, v]) => ({ date, ...v }));

    return c.json({ items });
  });

export default statistics;
