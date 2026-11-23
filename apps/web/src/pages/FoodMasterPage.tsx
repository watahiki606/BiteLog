import { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';
import { useFoodMasters, FOOD_MASTER_LIMIT as LIMIT, type FoodMaster } from '@/hooks/useFoodMasters';
import { Modal } from '@/components/Modal';
import FoodEditModal from '@/components/FoodEditModal';

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
  isAdmin: boolean;
}

export default function FoodMasterPage({ onToast, isAdmin }: Props) {
  const [offset, setOffset] = useState(0);
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<FoodMaster | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<FoodMaster | null>(null);

  // 入力をデバウンスして検索語を確定。確定時に1ページ目へ戻す。
  useEffect(() => {
    const t = setTimeout(() => { setDebouncedQuery(query); setOffset(0); }, 300);
    return () => clearTimeout(t);
  }, [query]);

  const onError = useCallback(
    () => onToast({ message: 'データの取得に失敗しました', type: 'error' }),
    [onToast]
  );
  const { data, isLoading: loading, mutate } = useFoodMasters(debouncedQuery, offset, onError);
  const items = data?.items ?? [];
  const total = data?.total ?? 0;

  function openAdd() {
    setEditing(null);
    setModalOpen(true);
  }

  function openEdit(item: FoodMaster) {
    setEditing(item);
    setModalOpen(true);
  }

  async function handleDelete(item: FoodMaster) {
    try {
      const client = createClient();
      const res = await client.api['food-masters'][':id'].$delete({ param: { id: item.id } });
      if (res.status === 403) {
        onToast({ message: '他のユーザーが作成した食品は削除できません', type: 'error' });
        setDeleteTarget(null);
        return;
      }
      if (!res.ok) throw new Error();
      onToast({ message: '削除しました', type: 'success' });
      setDeleteTarget(null);
      mutate();
    } catch {
      onToast({ message: '削除に失敗しました', type: 'error' });
    }
  }

  const totalPages = Math.ceil(total / LIMIT);
  const currentPage = Math.floor(offset / LIMIT) + 1;

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between px-6 py-4 border-b border-border-dim">
        <div>
          <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Food Master</h2>
          <p className="text-xs text-muted-foreground mt-0.5">{total} items</p>
        </div>
        <div className="flex items-center gap-3">
          <input
            type="text" placeholder="SEARCH..." value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="bg-bg-card border border-border-dim px-3 py-1.5 text-xs text-foreground focus:outline-none focus:border-neon-cyan transition-colors w-48"
            style={{ fontFamily: 'inherit' }}
          />
          <motion.button whileHover={{ scale: 1.03 }} whileTap={{ scale: 0.97 }} onClick={openAdd}
            className="px-4 py-1.5 text-xs font-bold tracking-widest uppercase"
            style={{ background: 'rgba(0,255,65,0.1)', border: '1px solid #00ff41', color: '#00ff41', boxShadow: '0 0 10px rgba(0,255,65,0.2)' }}
          >+ ADD</motion.button>
        </div>
      </div>

      <div className="flex-1 overflow-auto">
        <table className="w-full text-xs border-collapse">
          <thead className="sticky top-0 bg-bg-surface">
            <tr>
              {['Product', 'Brand', 'kcal', 'P', 'F', 'C', 'Fiber', 'Portion', 'Used', ''].map((h) => (
                <th key={h} className="px-4 py-3 text-left text-muted-foreground tracking-widest font-normal border-b border-border-dim">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={10} className="px-4 py-8 text-center text-muted-foreground tracking-widest">LOADING...</td></tr>
            ) : items.length === 0 ? (
              <tr><td colSpan={10} className="px-4 py-8 text-center text-muted-foreground tracking-widest">NO DATA</td></tr>
            ) : items.map((item) => (
              <motion.tr key={item.id} initial={{ opacity: 0 }} animate={{ opacity: 1 }}
                className="border-b border-border-dim hover:bg-neon-cyan/5 transition-colors group"
              >
                <td className="px-4 py-3 text-foreground max-w-40 truncate">{item.productName}</td>
                <td className="px-4 py-3 text-muted-foreground max-w-32 truncate">{item.brandName || '—'}</td>
                <td className="px-4 py-3 text-neon-yellow">{item.calories}</td>
                <td className="px-4 py-3 text-neon-green">{item.protein}g</td>
                <td className="px-4 py-3 text-neon-magenta">{item.fat}g</td>
                <td className="px-4 py-3 text-neon-cyan">{item.netCarbs}g</td>
                <td className="px-4 py-3 text-muted-foreground">{item.dietaryFiber}g</td>
                <td className="px-4 py-3 text-muted-foreground">{item.portionSize}{item.portionUnit}</td>
                <td className="px-4 py-3">
                  <span className="px-1.5 py-0.5 text-xs" style={{ border: '1px solid #1a1a3e', color: '#6060a0' }}>{item.usageCount}</span>
                </td>
                <td className="px-4 py-3">
                  {(isAdmin || item.isMine) && (
                    <div className="flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button onClick={() => openEdit(item)} className="px-2 py-1 text-xs text-neon-cyan border border-neon-cyan/30 hover:border-neon-cyan hover:bg-neon-cyan/10 transition-all">EDIT</button>
                      <button onClick={() => setDeleteTarget(item)} className="px-2 py-1 text-xs text-destructive border border-destructive/30 hover:border-destructive hover:bg-destructive/10 transition-all">DEL</button>
                    </div>
                  )}
                </td>
              </motion.tr>
            ))}
          </tbody>
        </table>
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-between px-6 py-3 border-t border-border-dim">
          <span className="text-xs text-muted-foreground tracking-widest">PAGE {currentPage} / {totalPages}</span>
          <div className="flex gap-2">
            <button onClick={() => setOffset(Math.max(0, offset - LIMIT))} disabled={offset === 0} className="px-3 py-1 text-xs border border-border-dim text-muted-foreground hover:border-neon-cyan hover:text-neon-cyan transition-all disabled:opacity-30">‹ PREV</button>
            <button onClick={() => setOffset(offset + LIMIT)} disabled={offset + LIMIT >= total} className="px-3 py-1 text-xs border border-border-dim text-muted-foreground hover:border-neon-cyan hover:text-neon-cyan transition-all disabled:opacity-30">NEXT ›</button>
          </div>
        </div>
      )}

      <AnimatePresence>
        {modalOpen && (
          <FoodEditModal key={editing?.id ?? 'new'} editing={editing} onToast={onToast}
            onClose={() => setModalOpen(false)} onSaved={() => { setModalOpen(false); mutate(); }} />
        )}
      </AnimatePresence>

      <AnimatePresence>
        {deleteTarget && (
          <Modal title="DELETE CONFIRM" onClose={() => setDeleteTarget(null)} onSave={() => handleDelete(deleteTarget)} saveLabel="DELETE" danger>
            <p className="text-sm text-foreground"><span className="text-neon-cyan">{deleteTarget.productName}</span> を削除しますか？</p>
            <p className="text-xs text-muted-foreground mt-2">この操作は取り消せません。</p>
          </Modal>
        )}
      </AnimatePresence>
    </div>
  );
}


