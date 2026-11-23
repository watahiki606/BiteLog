import { useState } from 'react';
import { AnimatePresence } from 'motion/react';
import useSWR from 'swr';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';
import type { FoodMaster } from '@/hooks/useFoodMasters';
import FoodEditModal from '@/components/FoodEditModal';

type UnlinkedFood = {
  id: string; brandName: string; productName: string; portionSize: number; portionUnit: string; logCount: number;
};

const PAGE = 50;

async function fetchUnlinked([, offset]: [string, number]): Promise<UnlinkedFood[]> {
  const res = await createClient().api.admin['food-masters'].unlinked.$get({ query: { limit: String(PAGE), offset: String(offset) } });
  if (!res.ok) throw new Error('unlinked');
  return (await res.json()).items;
}

/**
 * 成分表とのひも付けの作業画面。管理者だけ。
 * ひも付けの無い食品を全員の記録の多い順に並べる。上の食品ほど、ひも付けたときに値の入る記録が多い
 */
export default function LinkPage({ onToast }: { onToast: (msg: Omit<ToastMessage, 'id'>) => void }) {
  const [offset, setOffset] = useState(0);
  const { data: items = [], isLoading, mutate } = useSWR(['unlinked', offset], fetchUnlinked, { revalidateOnFocus: false });
  const [editing, setEditing] = useState<FoodMaster | null>(null);

  async function open(id: string) {
    const res = await createClient().api['food-masters'][':id'].$get({ param: { id } });
    if (!res.ok) {
      onToast({ message: '食品を読めませんでした', type: 'error' });
      return;
    }
    setEditing((await res.json()) as unknown as FoodMaster);
  }

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-4 border-b border-border-dim">
        <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Composition Link</h2>
        <p className="text-xs text-muted-foreground mt-0.5">Foods without a link to the composition table, most logged first</p>
      </div>
      <div className="flex-1 overflow-auto">
        <table className="w-full text-xs border-collapse">
          <thead className="sticky top-0 bg-bg-surface">
            <tr>
              {['Logs', 'Product', 'Brand', 'Portion'].map((h) => (
                <th key={h} className="px-4 py-3 text-left text-muted-foreground tracking-widest font-normal border-b border-border-dim">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {isLoading && items.length === 0 ? (
              <tr><td colSpan={4} className="px-4 py-8 text-center text-muted-foreground tracking-widest">LOADING...</td></tr>
            ) : items.map((item) => (
              <tr key={item.id} onClick={() => open(item.id)} className="border-b border-border-dim hover:bg-neon-cyan/5 cursor-pointer">
                <td className="px-4 py-3 text-neon-yellow">{item.logCount}</td>
                <td className="px-4 py-3 text-foreground">{item.productName}</td>
                <td className="px-4 py-3 text-muted-foreground">{item.brandName || '—'}</td>
                <td className="px-4 py-3 text-muted-foreground">{item.portionSize} {item.portionUnit}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="flex items-center justify-end gap-2 px-6 py-3 border-t border-border-dim">
        <button onClick={() => setOffset(Math.max(0, offset - PAGE))} disabled={offset === 0} className="px-3 py-1 text-xs border border-border-dim text-muted-foreground disabled:opacity-30">‹ PREV</button>
        <button onClick={() => setOffset(offset + PAGE)} disabled={items.length < PAGE} className="px-3 py-1 text-xs border border-border-dim text-muted-foreground disabled:opacity-30">NEXT ›</button>
      </div>
      <AnimatePresence>
        {editing && (
          <FoodEditModal key={editing.id} editing={editing} onToast={onToast}
            onClose={() => setEditing(null)} onSaved={() => { setEditing(null); mutate(); }} />
        )}
      </AnimatePresence>
    </div>
  );
}
