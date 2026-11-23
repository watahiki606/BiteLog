import { useEffect, useState } from 'react';
import { useCompositionSearch, type FoodComponent } from '@/hooks/useComposition';
import { fieldClass } from '@/components/Modal';

/**
 * 食品を成分表の食品と重さにひも付ける欄。
 * 重さは食品の1回分に含まれる、その食材の可食部の重さ。料理なら食材ごとに行を足す
 */
export default function ComponentsEditor({ components, onChange, defaultGrams, initialQuery = '' }: {
  components: FoodComponent[];
  onChange: (components: FoodComponent[]) => void;
  defaultGrams: number;
  initialQuery?: string;
}) {
  const [query, setQuery] = useState(initialQuery);
  const [debounced, setDebounced] = useState(initialQuery);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query), 300);
    return () => clearTimeout(t);
  }, [query]);
  const { data: results = [], isLoading } = useCompositionSearch(debounced);

  function add(foodNumber: string, name: string) {
    onChange([...components, { foodNumber, name, grams: defaultGrams }]);
  }

  function setGrams(index: number, grams: number) {
    onChange(components.map((c, i) => (i === index ? { ...c, grams } : c)));
  }

  function remove(index: number) {
    onChange(components.filter((_, i) => i !== index));
  }

  return (
    <div className="space-y-2">
      {components.length === 0 ? (
        <p className="text-xs text-muted-foreground">NOT LINKED</p>
      ) : (
        components.map((c, i) => (
          <div key={`${c.foodNumber}-${i}`} className="flex items-center gap-2">
            <span className="flex-1 min-w-0 text-xs text-foreground truncate" title={c.name ?? c.foodNumber}>
              <span className="text-muted-foreground mr-1">{c.foodNumber}</span>{c.name ?? '—'}
            </span>
            <input type="number" min="0" step="1" value={c.grams} onChange={(e) => setGrams(i, Number(e.target.value))}
              className="w-20 shrink-0 bg-bg-card border border-border-dim px-2 py-1.5 text-xs text-foreground focus:outline-none focus:border-neon-cyan" style={{ fontFamily: 'inherit' }} aria-label={`${c.name ?? c.foodNumber} grams`} />
            <span className="text-xs text-muted-foreground">g</span>
            <button onClick={() => remove(i)} className="text-xs text-destructive px-1" aria-label="remove">×</button>
          </div>
        ))
      )}
      <input type="text" placeholder="SEARCH COMPOSITION TABLE..." value={query} onChange={(e) => setQuery(e.target.value)}
        className={fieldClass} style={{ fontFamily: 'inherit' }} />
      {debounced.trim() && (
        <ul className="max-h-40 overflow-auto border border-border-dim">
          {isLoading && results.length === 0 ? (
            <li className="px-3 py-2 text-xs text-muted-foreground">LOADING...</li>
          ) : results.length === 0 ? (
            <li className="px-3 py-2 text-xs text-muted-foreground">NO MATCH</li>
          ) : results.map((r) => (
            <li key={r.foodNumber}>
              <button onClick={() => add(r.foodNumber, r.name)}
                className="w-full text-left px-3 py-1.5 text-xs hover:bg-neon-cyan/10 flex justify-between gap-2">
                <span className="truncate"><span className="text-muted-foreground mr-1">{r.foodNumber}</span>{r.name}</span>
                <span className="text-muted-foreground shrink-0">{r.per100g.calories ?? '—'} kcal/100g</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
