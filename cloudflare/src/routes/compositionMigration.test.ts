/// <reference types="@cloudflare/vitest-pool-workers" />
import { env } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { applySchema, applySql } from '../test/schema';
import { compositionFoodUpsert } from '../lib/composition';
import createCompositionFoods from '../../migrations/0003_composition_foods.sql?raw';
import detailNutrients from '../../migrations/0005_detail_nutrients.sql?raw';
import traceMinerals from '../../migrations/0006_trace_minerals_biotin.sql?raw';
import moveIntoFoodMasters from '../../migrations/0008_composition_foods_into_food_masters.sql?raw';

// 本番の composition_foods を food_masters に移す 0008 が、取り込みのスクリプトと同じ行を作るか

const RICE = { calories: 156, protein: 2.5, fat: 0.3, net_carbs: 35.6, dietary_fiber: 1.5, potassium: 29, iodine: null };
const SAKE = { calories: 107, protein: 0.4, fat: 0, net_carbs: 4.9, dietary_fiber: null, saturated_fat: 0 };

async function foodMasterRows(): Promise<Record<string, unknown>[]> {
  const { results } = await env.DB.prepare('SELECT * FROM food_masters ORDER BY id').all();
  return results;
}

async function insertComposition(foodNumber: string, name: string, values: Record<string, number | null>) {
  const columns = Object.keys(values);
  await env.DB.prepare(
    `INSERT INTO composition_foods (food_number, food_group, name, search_text, edition, ${columns.join(', ')}, raw_json)
     VALUES (?, ?, ?, ?, 'test', ${columns.map(() => '?').join(', ')}, '{}')`,
  ).bind(foodNumber, foodNumber.slice(0, 2), name, name, ...Object.values(values)).run();
}

describe('0008 composition_foods を food_masters に移す', () => {
  let expected: Record<string, unknown>[];

  beforeAll(async () => {
    await applySchema(env.DB);
    for (const [num, name, values] of [['01088', 'こめ ［水稲めし］ 精白米 うるち米', RICE], ['16001', '＜アルコール飲料類＞ 清酒 普通酒', SAKE]] as const) {
      const { sql, binds } = compositionFoodUpsert(num, name, values);
      await env.DB.prepare(sql).bind(...binds).run();
    }
    expected = await foodMasterRows();
    await env.DB.prepare('DELETE FROM food_masters').run();

    // 本番の composition_foods と同じ形にする。food_masters の列は schema.sql で足してあるので、composition_foods の文だけを流す
    await applySql(env.DB, createCompositionFoods);
    for (const migration of [detailNutrients, traceMinerals]) {
      await applySql(env.DB, migration.split(';').filter((s) => s.includes('composition_foods')).join(';'));
    }
    await insertComposition('01088', 'こめ ［水稲めし］ 精白米 うるち米', RICE);
    await insertComposition('16001', '＜アルコール飲料類＞ 清酒 普通酒', SAKE);
    await applySql(env.DB, moveIntoFoodMasters);
  });

  it('取り込みのスクリプトで入れたときと同じ行になる', async () => {
    expect(expected).toHaveLength(2);
    expect(await foodMasterRows()).toEqual(expected);
  });

  it('composition_foods は消える', async () => {
    const table = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'composition_foods'").first();
    expect(table).toBeNull();
  });
});
