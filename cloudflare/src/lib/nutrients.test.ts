import { describe, it, expect } from 'vitest';
import { CORE_NUTRIENT_IDS, NUTRIENTS, NUTRIENT_COLUMNS, nutrientBinds, nutrientsFromRow } from './nutrients';
import { NUTRITION_BASE_CTE, NUTRITION_SUM_COLUMNS } from './nutritionSql';

describe('栄養素の定義', () => {
  it('型で持つ最初の5項目は、定義ファイルの core と同じ', () => {
    expect(NUTRIENTS.filter((n) => n.core).map((n) => n.id)).toEqual([...CORE_NUTRIENT_IDS]);
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
