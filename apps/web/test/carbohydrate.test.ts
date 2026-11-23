import { describe, it, expect } from 'bun:test';
import { carbohydrateOf, withCarbohydrate, withFiber } from '../src/lib/nutrients';

// 入力欄は炭水化物とうち食物繊維。保存は糖質と食物繊維のまま

describe('炭水化物の入力欄', () => {
  it('糖質と食物繊維の和を炭水化物として出す', () => {
    expect(carbohydrateOf({ netCarbs: 38.6, dietaryFiber: 1.6 })).toBe(40.2);
  });

  it('炭水化物を入れると、食物繊維を引いた値を糖質にする', () => {
    expect(withCarbohydrate({ netCarbs: 0, dietaryFiber: 1.6 }, 40.2)).toEqual({ netCarbs: 38.6, dietaryFiber: 1.6 });
  });

  it('食物繊維を入れても炭水化物は変わらず、糖質が減る', () => {
    expect(withFiber({ netCarbs: 31, dietaryFiber: 0 }, 2.5)).toEqual({ netCarbs: 28.5, dietaryFiber: 2.5 });
  });

  it('引き算の誤差を丸める', () => {
    expect(withCarbohydrate({ netCarbs: 0, dietaryFiber: 0.1 }, 0.3).netCarbs).toBe(0.2);
  });

  it('食物繊維が炭水化物より多ければ糖質は負になり、呼ぶ側が保存を止める', () => {
    expect(withFiber({ netCarbs: 2, dietaryFiber: 0 }, 3).netCarbs).toBe(-1);
  });
});
