import { describe, it, expect } from 'bun:test';
import { changedAddedBody, defaultComponentGrams, emptyAddedInputs } from '../src/lib/nutrients';

describe('直すときに送る値', () => {
  it('変えた欄だけを送る。空にした欄は null', () => {
    const initial = { ...emptyAddedInputs(), potassium: '720', saltEquivalent: '0.6' };
    const current = { ...initial, saltEquivalent: '0.7', potassium: '' };
    expect(changedAddedBody(initial, current)).toEqual({ saltEquivalent: 0.7, potassium: null });
  });

  it('何も変えなければ何も送らない。成分表で補った値の印を外さないため', () => {
    const initial = { ...emptyAddedInputs(), potassium: '720' };
    expect(changedAddedBody(initial, { ...initial })).toEqual({});
  });
});

describe('食材の重さの初期値', () => {
  it('量が g か ml なら、その数', () => {
    expect(defaultComponentGrams(60, 'g')).toBe(60);
    expect(defaultComponentGrams(200, 'ml')).toBe(200);
  });

  it('個や人前なら 100', () => {
    expect(defaultComponentGrams(1, '個')).toBe(100);
    expect(defaultComponentGrams(1, '人前')).toBe(100);
  });
});
