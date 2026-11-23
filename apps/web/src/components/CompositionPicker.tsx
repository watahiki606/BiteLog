import { useEffect, useState } from 'react';
import { useCompositionSearch, type CompositionFood } from '@/hooks/useComposition';
import { fieldClass } from '@/components/Modal';
import { searchTermOf } from '@/lib/nutrients';

/**
 * 成分表から食品を選び、重さの分の値を栄養素の欄に入れる。
 * 入れた値は手で打った値と同じで直せる。食品と成分表は結ばない
 */
export default function CompositionPicker({ productName, defaultGrams, picked, onPick }: {
  /** 検索欄が空のあいだは、食品名の最初の語で候補を出す */
  productName: string;
  defaultGrams: number;
  /** 最後に選んだ食品と重さ */
  picked: { name: string; grams: number } | null;
  onPick: (food: CompositionFood, grams: number) => void;
}) {
  const [query, setQuery] = useState('');
  const [gramsText, setGramsText] = useState('');
  const effective = query.trim() || searchTermOf(productName);
  const [debounced, setDebounced] = useState(effective);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(effective), 300);
    return () => clearTimeout(t);
  }, [effective]);
  const { data: results = [], isLoading } = useCompositionSearch(debounced);

  const typedGrams = Number(gramsText);
  const grams = gramsText.trim() !== '' && typedGrams > 0 ? typedGrams : defaultGrams;

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        <input type="text" placeholder={effective || 'SEARCH COMPOSITION TABLE...'} value={query} onChange={(e) => setQuery(e.target.value)}
          className={fieldClass} style={{ fontFamily: 'inherit' }} />
        <input type="number" min="0" step="1" placeholder={String(defaultGrams)} value={gramsText} onChange={(e) => setGramsText(e.target.value)}
          className="w-20 shrink-0 bg-bg-card border border-border-dim px-2 py-1.5 text-xs text-foreground focus:outline-none focus:border-neon-cyan"
          style={{ fontFamily: 'inherit' }} aria-label="edible grams" />
        <span className="self-center text-xs text-muted-foreground">g</span>
      </div>
      {debounced.trim() && (
        <ul className="max-h-40 overflow-auto border border-border-dim">
          {isLoading && results.length === 0 ? (
            <li className="px-3 py-2 text-xs text-muted-foreground">LOADING...</li>
          ) : results.length === 0 ? (
            <li className="px-3 py-2 text-xs text-muted-foreground">NO MATCH</li>
          ) : results.map((r) => (
            <li key={r.foodNumber}>
              <button onClick={() => onPick(r, grams)}
                className="w-full text-left px-3 py-1.5 text-xs hover:bg-neon-cyan/10 flex justify-between gap-2">
                <span className="truncate"><span className="text-muted-foreground mr-1">{r.foodNumber}</span>{r.name}</span>
                <span className="text-muted-foreground shrink-0">{r.per100g.calories ?? '—'} kcal/100g</span>
              </button>
            </li>
          ))}
        </ul>
      )}
      <p className="text-xs text-muted-foreground">
        {picked
          ? `FILLED WITH ${picked.name} ${picked.grams} g. EDIT THE VALUES AS NEEDED`
          : 'PICK A FOOD TO FILL EMPTY FIELDS WITH THE VALUES FOR THIS WEIGHT'}
      </p>
    </div>
  );
}
