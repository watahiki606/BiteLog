import { describe, it, expect } from 'bun:test';
import { defaultPickGrams, mergePicked, pickedTexts, searchTermOf } from '../src/lib/nutrients';

describe('成分表から選ぶ重さの初期値', () => {
  it('量が g か ml なら、その数', () => {
    expect(defaultPickGrams(60, 'g')).toBe(60);
    expect(defaultPickGrams(200, 'ml')).toBe(200);
  });

  it('個や人前なら 100', () => {
    expect(defaultPickGrams(1, '個')).toBe(100);
    expect(defaultPickGrams(1, '人前')).toBe(100);
  });
});

describe('候補を探す語', () => {
  it('食品名の最初の語で探す', () => {
    expect(searchTermOf('鶏むね肉（皮なし）')).toBe('鶏むね肉');
    expect(searchTermOf('ポテトチップス うすしお')).toBe('ポテトチップス');
    expect(searchTermOf('')).toBe('');
  });
});

describe('選んだ食品の値', () => {
  it('重さの分にして、栄養素の桁で丸める。未測定の栄養素は含めない', () => {
    // ゆで卵 50 g
    const texts = pickedTexts({ calories: 134, protein: 12.4, potassium: 130, vitaminB12: 1.13 }, 50);
    expect(texts).toEqual({ calories: '67', protein: '6.2', potassium: '65', vitaminB12: '0.6' });
  });
});

describe('欄に書く値', () => {
  it('空の欄にだけ書き、手で入れた値は残す', () => {
    expect(mergePicked({ calories: '336', potassium: '' }, { calories: '325', potassium: '720' }, {}))
      .toEqual({ potassium: '720' });
  });

  it('選び直すと前に選んだ値を入れ替え、新しい候補に無い値は空に戻す。手で直した値は残す', () => {
    const merged = mergePicked(
      { calories: '160', vitaminD: '0.4', potassium: '50' },
      { calories: '156' },
      { calories: '160', vitaminD: '0.4', potassium: '29' },
    );
    expect(merged).toEqual({ calories: '156', vitaminD: '' });
  });
});
