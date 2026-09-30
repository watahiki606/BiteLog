/// <reference types="@cloudflare/vitest-pool-workers" />
import { SELF, env } from 'cloudflare:test';
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { issueSessionJwt } from '../middleware/auth';

const TEST_SECRET = 'dev-and-test-secret';

beforeAll(async () => {
  await env.DB.prepare(
    `CREATE TABLE IF NOT EXISTS body_measurements (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      source_date TEXT,
      measured_at TEXT NOT NULL,
      measurement_date_raw TEXT,
      measurement_time_raw TEXT,
      measurement_index INTEGER,
      item_count INTEGER,
      input_method TEXT,
      weight_kg REAL,
      body_fat_percent REAL,
      muscle_mass_kg REAL,
      muscle_score REAL,
      visceral_fat_level REAL,
      basal_metabolism_kcal REAL,
      metabolic_age INTEGER,
      bone_mass_kg REAL,
      body_water_percent REAL,
      page_url TEXT,
      UNIQUE(user_id, measured_at)
    )`
  ).run();
});

beforeEach(async () => {
  await env.DB.prepare('DELETE FROM body_measurements').run();
});

async function jwtFor(userId: string): Promise<string> {
  return issueSessionJwt(userId, TEST_SECRET);
}

async function authedFetch(userId: string, path: string, init: RequestInit = {}) {
  return SELF.fetch(`http://localhost${path}`, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      Authorization: `Bearer ${await jwtFor(userId)}`,
    },
  });
}

const CSV_HEADER =
  'sourceDate,measuredAt,measurementDateRaw,measurementTimeRaw,measurementIndex,itemCount,inputMethod,weightKg,bodyFatPercent,muscleMassKg,muscleScore,visceralFatLevel,basalMetabolismKcal,metabolicAge,boneMassKg,bodyWaterPercent,pageUrl';

function csvRow(measuredAt: string, weightKg: number) {
  return `2025-01-01,${measuredAt},2025年01月01日,09:04,1,9,対応機器データ,${weightKg},15.2,41,-2,1,1247,18,2.3,54.8,https://example.com`;
}

describe('認証', () => {
  it('未認証は 401', async () => {
    const res = await SELF.fetch('http://localhost/api/body-measurements');
    expect(res.status).toBe(401);
  });
});

describe('POST /api/body-measurements (手動追加)', () => {
  it('measuredAt が無ければ 400', async () => {
    const res = await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ weightKg: 50 }),
    });
    expect(res.status).toBe(400);
  });

  it('1件追加でき、201 と保存値を返す', async () => {
    const res = await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ measuredAt: '2025-01-01T00:04:00.000Z', weightKg: 51.2, metabolicAge: 18 }),
    });
    expect(res.status).toBe(201);
    const body = await res.json<{ id: string; weightKg: number; metabolicAge: number }>();
    expect(body.weightKg).toBe(51.2);
    expect(body.metabolicAge).toBe(18);
    expect(body.id).toBeTruthy();
  });

  it('同一 measuredAt の重複は 409', async () => {
    const payload = JSON.stringify({ measuredAt: '2025-01-01T00:04:00.000Z', weightKg: 50 });
    await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: payload,
    });
    const res = await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: payload,
    });
    expect(res.status).toBe(409);
  });
});

describe('GET /api/body-measurements (一覧)', () => {
  it('自分のデータのみ measured_at 降順で返す', async () => {
    for (const [u, at, w] of [
      ['user-a', '2025-01-01T00:00:00.000Z', 50],
      ['user-a', '2025-01-02T00:00:00.000Z', 51],
      ['user-b', '2025-01-03T00:00:00.000Z', 60],
    ] as const) {
      await authedFetch(u, '/api/body-measurements', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ measuredAt: at, weightKg: w }),
      });
    }
    const res = await authedFetch('user-a', '/api/body-measurements');
    const { items } = await res.json<{ items: { measuredAt: string; weightKg: number }[] }>();
    expect(items).toHaveLength(2);
    expect(items[0].measuredAt).toBe('2025-01-02T00:00:00.000Z');
    expect(items[1].measuredAt).toBe('2025-01-01T00:00:00.000Z');
  });

  it('from/to は計測した地域の暦日で絞る', async () => {
    // 09:00 JST の計測は UTC では前日になる。measured_at から切り出すと1日ずれる
    for (const [at, day, w] of [
      ['2025-01-01T23:00:00.000Z', '2025-01-02', 50],
      ['2025-01-02T23:00:00.000Z', '2025-01-03', 51],
    ] as const) {
      await authedFetch('user-a', '/api/body-measurements', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ measuredAt: at, sourceDate: day, weightKg: w }),
      });
    }

    const res = await authedFetch('user-a', '/api/body-measurements?from=2025-01-02&to=2025-01-02');
    const { items } = await res.json<{ items: { weightKg: number }[] }>();
    expect(items).toHaveLength(1);
    expect(items[0].weightKg).toBe(50);
  });

  it('sourceDate が無い行は measuredAt の日付で絞る', async () => {
    await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ measuredAt: '2025-03-10T05:00:00.000Z', weightKg: 55 }),
    });

    const hit = await authedFetch('user-a', '/api/body-measurements?from=2025-03-10&to=2025-03-10');
    expect((await hit.json<{ items: unknown[] }>()).items).toHaveLength(1);

    const miss = await authedFetch('user-a', '/api/body-measurements?from=2025-03-11&to=2025-03-11');
    expect((await miss.json<{ items: unknown[] }>()).items).toHaveLength(0);
  });

  it('同じ日に何度乗っても全部返す', async () => {
    for (const [at, w] of [
      ['2025-02-01T22:00:00.000Z', 60.8],
      ['2025-02-02T03:00:00.000Z', 61.4],
      ['2025-02-02T12:00:00.000Z', 61.9],
    ] as const) {
      await authedFetch('user-a', '/api/body-measurements', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ measuredAt: at, sourceDate: '2025-02-02', weightKg: w }),
      });
    }

    const res = await authedFetch('user-a', '/api/body-measurements?from=2025-02-02&to=2025-02-02');
    const { items } = await res.json<{ items: { weightKg: number }[] }>();
    expect(items.map((item: { weightKg: number }) => item.weightKg)).toEqual([61.9, 61.4, 60.8]);
  });
});

describe('DELETE /api/body-measurements/:id', () => {
  it('自分のデータを削除できる', async () => {
    const created = await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ measuredAt: '2025-01-01T00:00:00.000Z', weightKg: 50 }),
    });
    const { id } = await created.json<{ id: string }>();
    const res = await authedFetch('user-a', `/api/body-measurements/${id}`, { method: 'DELETE' });
    expect(res.status).toBe(200);

    const list = await authedFetch('user-a', '/api/body-measurements');
    const { items } = await list.json<{ items: unknown[] }>();
    expect(items).toHaveLength(0);
  });

  it('他ユーザーのデータは削除できず 404', async () => {
    const created = await authedFetch('user-a', '/api/body-measurements', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ measuredAt: '2025-01-01T00:00:00.000Z', weightKg: 50 }),
    });
    const { id } = await created.json<{ id: string }>();
    const res = await authedFetch('user-b', `/api/body-measurements/${id}`, { method: 'DELETE' });
    expect(res.status).toBe(404);
  });
});

describe('POST /api/body-measurements/import (CSV一括)', () => {
  it('全17列をパースして登録する', async () => {
    const csv = [CSV_HEADER, csvRow('2025-01-01T00:04:00.000Z', 51), csvRow('2025-01-01T11:34:00.000Z', 51.6)].join('\n');
    const res = await authedFetch('user-a', '/api/body-measurements/import', {
      method: 'POST', headers: { 'Content-Type': 'text/csv' }, body: csv,
    });
    expect(res.status).toBe(200);
    const { created } = await res.json<{ created: number; skipped: number }>();
    expect(created).toBe(2);

    const list = await authedFetch('user-a', '/api/body-measurements');
    const { items } = await list.json<{ items: { weightKg: number; muscleScore: number; metabolicAge: number; inputMethod: string }[] }>();
    expect(items).toHaveLength(2);
    expect(items[0].muscleScore).toBe(-2);
    expect(items[0].metabolicAge).toBe(18);
    expect(items[0].inputMethod).toBe('対応機器データ');
  });

  it('再インポート時に既存の measured_at はスキップする', async () => {
    const csv = [CSV_HEADER, csvRow('2025-01-01T00:04:00.000Z', 51)].join('\n');
    await authedFetch('user-a', '/api/body-measurements/import', {
      method: 'POST', headers: { 'Content-Type': 'text/csv' }, body: csv,
    });
    const res = await authedFetch('user-a', '/api/body-measurements/import', {
      method: 'POST', headers: { 'Content-Type': 'text/csv' }, body: csv,
    });
    const { created, skipped } = await res.json<{ created: number; skipped: number }>();
    expect(created).toBe(0);
    expect(skipped).toBe(1);
  });

  it('データ行が無ければ 400', async () => {
    const res = await authedFetch('user-a', '/api/body-measurements/import', {
      method: 'POST', headers: { 'Content-Type': 'text/csv' }, body: CSV_HEADER,
    });
    expect(res.status).toBe(400);
  });
});
