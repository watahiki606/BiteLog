// テストの D1 に、本番と同じ schema.sql で表を作る。
// 各テストが表の作成文を手で写すと、列を足したときに写し漏れて本番と食い違う。
import schema from '../../schema.sql?raw';

/** 文を ; で分けて順に流す。行の頭の -- から行末までは注釈として外す */
export async function applySql(db: D1Database, sql: string): Promise<void> {
  const statements = sql
    .split(';')
    .map((s) => s.replace(/^\s*--.*$/gm, '').trim())
    .filter(Boolean);
  await db.batch(statements.map((s) => db.prepare(s)));
}

export async function applySchema(db: D1Database): Promise<void> {
  await applySql(db, schema);
}
