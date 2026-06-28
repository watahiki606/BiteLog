import { Hono } from 'hono';
import type { Bindings, Variables, BodyMeasurementRow } from '../types';
import { bodyMeasurementToResponse } from '../types';
import { authMiddleware } from '../middleware/auth';

const BATCH_SIZE = 100;
const DEFAULT_LIMIT = 1000;

// CSVの1行をパースする（log_items のCSVインポートと同じ簡易パーサ）
function parseCSVLine(line: string): string[] {
  const columns: string[] = [];
  let current = '';
  let inQuotes = false;
  for (const char of line) {
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      columns.push(current.trim());
      current = '';
    } else {
      current += char;
    }
  }
  columns.push(current.trim());
  return columns;
}

// CSVのcamelCaseヘッダ → DBカラム名（DBへのbind順序もこの定義順に従う）
const FIELD_DEFS: { csv: string; col: string; kind: 'text' | 'real' | 'int' }[] = [
  { csv: 'sourceDate',           col: 'source_date',           kind: 'text' },
  { csv: 'measuredAt',           col: 'measured_at',           kind: 'text' },
  { csv: 'measurementDateRaw',   col: 'measurement_date_raw',  kind: 'text' },
  { csv: 'measurementTimeRaw',   col: 'measurement_time_raw',  kind: 'text' },
  { csv: 'measurementIndex',     col: 'measurement_index',     kind: 'int' },
  { csv: 'itemCount',            col: 'item_count',            kind: 'int' },
  { csv: 'inputMethod',          col: 'input_method',          kind: 'text' },
  { csv: 'weightKg',             col: 'weight_kg',             kind: 'real' },
  { csv: 'bodyFatPercent',       col: 'body_fat_percent',      kind: 'real' },
  { csv: 'muscleMassKg',         col: 'muscle_mass_kg',        kind: 'real' },
  { csv: 'muscleScore',          col: 'muscle_score',          kind: 'real' },
  { csv: 'visceralFatLevel',     col: 'visceral_fat_level',    kind: 'real' },
  { csv: 'basalMetabolismKcal',  col: 'basal_metabolism_kcal', kind: 'real' },
  { csv: 'metabolicAge',         col: 'metabolic_age',         kind: 'int' },
  { csv: 'boneMassKg',           col: 'bone_mass_kg',          kind: 'real' },
  { csv: 'bodyWaterPercent',     col: 'body_water_percent',    kind: 'real' },
  { csv: 'pageUrl',              col: 'page_url',              kind: 'text' },
];

const COLUMNS = FIELD_DEFS.map((f) => f.col);

// 文字列値を kind に応じて DB へbindできる値（number/string/null）に変換する
function coerce(raw: string | undefined, kind: 'text' | 'real' | 'int'): number | string | null {
  const v = raw?.trim();
  if (v === undefined || v === '') return null;
  if (kind === 'text') return v;
  const n = kind === 'int' ? parseInt(v, 10) : parseFloat(v);
  return Number.isNaN(n) ? null : n;
}

// camelCaseフィールドを持つレコードを COLUMNS 順の bind 値配列へ変換する
function recordToValues(rec: Record<string, unknown>): (number | string | null)[] {
  return FIELD_DEFS.map((f) => coerce(rec[f.csv] != null ? String(rec[f.csv]) : undefined, f.kind));
}

function insertStmt(db: D1Database, id: string, userId: string, values: (number | string | null)[]) {
  const placeholders = COLUMNS.map(() => '?').join(', ');
  return db
    .prepare(
      `INSERT OR IGNORE INTO body_measurements (id, user_id, ${COLUMNS.join(', ')})
       VALUES (?, ?, ${placeholders})`
    )
    .bind(id, userId, ...values);
}

const bodyMeasurements = new Hono<{ Bindings: Bindings; Variables: Variables }>()
  .use('*', authMiddleware)
  // GET / : ユーザーの計測データを measured_at 降順で返す
  .get('/', async (c) => {
    const userId = c.get('userId');
    const limitParam = parseInt(c.req.query('limit') ?? '', 10);
    const limit = Number.isNaN(limitParam) ? DEFAULT_LIMIT : Math.min(Math.max(limitParam, 1), 5000);

    const { results } = await c.env.DB.prepare(
      `SELECT * FROM body_measurements WHERE user_id = ? ORDER BY measured_at DESC LIMIT ?`
    )
      .bind(userId, limit)
      .all<BodyMeasurementRow>();

    return c.json({ items: results.map(bodyMeasurementToResponse) });
  })
  // POST / : 手動で1件追加。measuredAt 必須。重複（同一measured_at）は 409
  .post('/', async (c) => {
    const userId = c.get('userId');
    const body = await c.req.json<Record<string, unknown>>();

    const measuredAt = typeof body.measuredAt === 'string' ? body.measuredAt.trim() : '';
    if (!measuredAt) return c.json({ error: 'measuredAt is required' }, 400);

    const id = crypto.randomUUID();
    const values = recordToValues(body);
    const res = await insertStmt(c.env.DB, id, userId, values).run();
    if (res.meta.changes === 0) {
      return c.json({ error: 'A measurement at this time already exists' }, 409);
    }

    const row = await c.env.DB.prepare(
      `SELECT * FROM body_measurements WHERE id = ?`
    )
      .bind(id)
      .first<BodyMeasurementRow>();
    return c.json(bodyMeasurementToResponse(row!), 201);
  })
  // DELETE /:id : 自分の計測データを1件削除
  .delete('/:id', async (c) => {
    const userId = c.get('userId');
    const id = c.req.param('id');
    const res = await c.env.DB.prepare(
      `DELETE FROM body_measurements WHERE id = ? AND user_id = ?`
    )
      .bind(id, userId)
      .run();
    if (res.meta.changes === 0) return c.json({ error: 'Not found' }, 404);
    return c.json({ deleted: true });
  })
  // POST /import : CSV（全17列）を一括登録。重複は INSERT OR IGNORE でスキップ
  .post('/import', async (c) => {
    const userId = c.get('userId');
    const csvText = await c.req.text();

    const lines = csvText.split(/\r?\n/).filter((l) => l.trim());
    if (lines.length < 2) return c.json({ error: 'CSV has no data rows' }, 400);

    const headers = parseCSVLine(lines[0]);
    const measuredAtIdx = headers.indexOf('measuredAt');
    if (measuredAtIdx < 0) {
      return c.json({ error: 'CSV must contain a measuredAt column' }, 400);
    }
    // CSVヘッダ名 → 列インデックス
    const idxByCsv = new Map(headers.map((h, i) => [h, i]));

    type Pending = { id: string; values: (number | string | null)[] };
    const pending: Pending[] = [];
    let skipped = 0;
    // 同一CSV内での measured_at 重複も排除する
    const seen = new Set<string>();

    for (const line of lines.slice(1)) {
      const cols = parseCSVLine(line);
      const measuredAt = cols[measuredAtIdx]?.trim();
      if (!measuredAt || seen.has(measuredAt)) {
        skipped++;
        continue;
      }
      seen.add(measuredAt);

      const values = FIELD_DEFS.map((f) => {
        const i = idxByCsv.get(f.csv);
        return coerce(i === undefined ? undefined : cols[i], f.kind);
      });
      pending.push({ id: crypto.randomUUID(), values });
    }

    let created = 0;
    for (let i = 0; i < pending.length; i += BATCH_SIZE) {
      const chunk = pending.slice(i, i + BATCH_SIZE);
      const results = await c.env.DB.batch(
        chunk.map((p) => insertStmt(c.env.DB, p.id, userId, p.values))
      );
      created += results.filter((r) => r.meta.changes > 0).length;
    }

    return c.json({ created, skipped: skipped + (pending.length - created) });
  });

export default bodyMeasurements;
