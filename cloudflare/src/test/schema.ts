// テストの D1 に、本番と同じ schema.sql で表を作る。
// 各テストが表の作成文を手で写すと、列を足したときに写し漏れて本番と食い違う。
import schema from '../../schema.sql?raw';

export async function applySchema(db: D1Database): Promise<void> {
  const statements = schema
    .split(';')
    .map((s) => s.replace(/^\s*--.*$/gm, '').trim())
    .filter(Boolean);
  await db.batch(statements.map((s) => db.prepare(s)));
}
