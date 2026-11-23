import { describe, it, expect } from 'vitest';
import { ADDED_NUTRIENT_IDS, CORE_NUTRIENT_IDS, LABEL_NUTRIENTS, NUTRIENTS, NUTRIENT_COLUMNS, nutrientBinds, nutrientsFromRow } from './nutrients';
import { NUTRITION_BASE_CTE, NUTRITION_SUM_COLUMNS } from './nutritionSql';

describe('栄養素の定義', () => {
  it('型で持つ最初の5項目は、定義ファイルの core と同じ', () => {
    expect(NUTRIENTS.filter((n) => n.core).map((n) => n.id)).toEqual([...CORE_NUTRIENT_IDS]);
  });

  it('型で持つ追加の栄養素は、定義ファイルの core でないものと同じ', () => {
    expect(NUTRIENTS.filter((n) => !n.core).map((n) => n.id)).toEqual([...ADDED_NUTRIENT_IDS]);
  });

  it('食品表示に載りうる栄養素は、最初の5項目でも詳しい栄養素でもないもの', () => {
    expect(LABEL_NUTRIENTS.map((n) => n.id)).toEqual(NUTRIENTS.filter((n) => !n.core && !n.detail).map((n) => n.id));
    expect(LABEL_NUTRIENTS.map((n) => n.id)).toContain('vitaminC');
    expect(LABEL_NUTRIENTS.map((n) => n.id)).not.toContain('zinc');
  });

  it('ヨウ素、セレン、クロム、モリブデン、ビオチンは成分表に値のある詳しい栄養素', () => {
    for (const id of ['iodine', 'selenium', 'chromium', 'molybdenum', 'biotin']) {
      expect(NUTRIENTS.find((n) => n.id === id)).toMatchObject({ detail: true, unit: 'µg', composition: { table: 'main' } });
    }
  });

  it('D1 の行の列から、API のキーで値を取り出す', () => {
    const row = { id: 'x', calories: 650, protein: 15, fat: 20, net_carbs: 90, dietary_fiber: 3 };

    expect(nutrientsFromRow(row)).toEqual({ calories: 650, protein: 15, fat: 20, netCarbs: 90, dietaryFiber: 3 });
  });

  it('値の無い栄養素はキーごと省く', () => {
    expect(nutrientsFromRow({ calories: 650, protein: null })).toEqual({ calories: 650 });
  });

  it('送られた本文から、列の並びで値を取り出し、無いものは null にする', () => {
    const binds = nutrientBinds({ calories: 650, netCarbs: 90 });

    expect(binds).toHaveLength(NUTRIENT_COLUMNS.length);
    expect(binds[NUTRIENT_COLUMNS.indexOf('calories')]).toBe(650);
    expect(binds[NUTRIENT_COLUMNS.indexOf('net_carbs')]).toBe(90);
    expect(binds[NUTRIENT_COLUMNS.indexOf('protein')]).toBeNull();
  });
});

describe('集計の SQL', () => {
  it('どの栄養素も、食品の列を先に、無ければスナップショットのキーを読む', () => {
    const cte = NUTRITION_BASE_CTE;
    for (const n of NUTRIENTS) {
      expect(cte).toContain(`COALESCE(fm.${n.column}, json_extract(li.nutrition_snapshot_json, '$.${n.id}'))`);
    }
  });

  it('どの栄養素も、API のキーの名前で合計を返す', () => {
    for (const n of NUTRIENTS) {
      expect(NUTRITION_SUM_COLUMNS).toContain(`AS ${n.id}`);
    }
  });
});
