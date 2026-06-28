import { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';
import { useFoodMasters, FOOD_MASTER_LIMIT as LIMIT, type FoodMaster } from '@/hooks/useFoodMasters';

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
  isAdmin: boolean;
}

const emptyForm = {
  brandName: '',
  productName: '',
  calories: 0,
  protein: 0,
  fat: 0,
  netCarbs: 0,
  dietaryFiber: 0,
  portionSize: 100,
  portionUnit: 'g',
};

type FormData = typeof emptyForm;

export default function FoodMasterPage({ onToast, isAdmin }: Props) {
  const [offset, setOffset] = useState(0);
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<FoodMaster | null>(null);
  const [form, setForm] = useState<FormData>(emptyForm);
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
    setForm(emptyForm);
    setModalOpen(true);
  }

  function openEdit(item: FoodMaster) {
    setEditing(item);
    setForm({
      brandName: item.brandName,
      productName: item.productName,
      calories: item.calories,
      protein: item.protein,
      fat: item.fat,
      netCarbs: item.netCarbs,
      dietaryFiber: item.dietaryFiber,
      portionSize: item.portionSize,
      portionUnit: item.portionUnit,
    });
    setModalOpen(true);
  }

  async function handleSave() {
    try {
      const client = createClient();
      if (editing) {
        // PUT は Hono RPC がバリデータなしで json ボディを型推論できないため、
        // param だけ渡し、ボディは init で送る。
        const res = await client.api['food-masters'][':id'].$put(
          { param: { id: editing.id } },
          { init: { body: JSON.stringify(form), headers: { 'Content-Type': 'application/json' } } }
        );
        if (res.status === 403) {
          onToast({ message: '他のユーザーが作成した食品は編集できません', type: 'error' });
          return;
        }
        if (!res.ok) throw new Error();
      } else {
        const id = crypto.randomUUID();
        const uniqueKey = `${form.brandName}|${form.productName}|${form.portionUnit}`;
        const res = await client.api['food-masters'].$post({
          json: { ...form, id, uniqueKey },
        });
        if (!res.ok) throw new Error();
      }
      onToast({ message: editing ? '更新しました' : '追加しました', type: 'success' });
      setModalOpen(false);
      mutate();
    } catch {
      onToast({ message: '保存に失敗しました', type: 'error' });
    }
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

  function setField<K extends keyof FormData>(key: K, val: FormData[K]) {
    setForm((f) => ({ ...f, [key]: val }));
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
          <Modal title={editing ? 'EDIT FOOD' : 'ADD FOOD'} onClose={() => setModalOpen(false)} onSave={handleSave}>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Product Name" colSpan={2}><input type="text" value={form.productName} onChange={(e) => setField('productName', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Brand Name" colSpan={2}><input type="text" value={form.brandName} onChange={(e) => setField('brandName', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Calories (kcal)"><input type="number" value={form.calories} onChange={(e) => setField('calories', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Protein (g)"><input type="number" step="0.1" value={form.protein} onChange={(e) => setField('protein', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Fat (g)"><input type="number" step="0.1" value={form.fat} onChange={(e) => setField('fat', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Net Carbs (g)"><input type="number" step="0.1" value={form.netCarbs} onChange={(e) => setField('netCarbs', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Fiber (g)"><input type="number" step="0.1" value={form.dietaryFiber} onChange={(e) => setField('dietaryFiber', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Portion Size"><input type="number" step="0.1" value={form.portionSize} onChange={(e) => setField('portionSize', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
              <Field label="Portion Unit"><input type="text" value={form.portionUnit} onChange={(e) => setField('portionUnit', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
            </div>
          </Modal>
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

const fc = "w-full bg-bg-card border border-border-dim px-3 py-1.5 text-xs text-foreground focus:outline-none focus:border-neon-cyan transition-colors";

function Field({ label, children, colSpan }: { label: string; children: React.ReactNode; colSpan?: number }) {
  return (
    <div className={colSpan === 2 ? 'col-span-2' : ''}>
      <label className="block text-xs text-muted-foreground mb-1 tracking-wider uppercase">{label}</label>
      {children}
    </div>
  );
}

function Modal({ title, onClose, onSave, saveLabel = 'SAVE', danger = false, children }: {
  title: string; onClose: () => void; onSave: () => void; saveLabel?: string; danger?: boolean; children: React.ReactNode;
}) {
  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 bg-black/70 flex items-center justify-center z-40 p-4" onClick={onClose}
    >
      <motion.div initial={{ scale: 0.9, y: 10 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.9, y: 10 }}
        className="w-full max-w-md bg-bg-surface border border-border-dim p-6"
        style={{ boxShadow: '0 0 40px rgba(0,229,255,0.1)' }} onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-5">
          <h3 className="text-sm font-bold tracking-widest text-neon-cyan">{title}</h3>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground text-lg leading-none">×</button>
        </div>
        <div className="mb-6">{children}</div>
        <div className="flex justify-end gap-3">
          <button onClick={onClose} className="px-4 py-2 text-xs tracking-widest border border-border-dim text-muted-foreground hover:border-foreground hover:text-foreground transition-all uppercase">CANCEL</button>
          <motion.button whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }} onClick={onSave}
            className="px-4 py-2 text-xs font-bold tracking-widest uppercase"
            style={{ background: danger ? 'rgba(255,51,102,0.1)' : 'rgba(0,229,255,0.1)', border: `1px solid ${danger ? '#ff3366' : '#00e5ff'}`, color: danger ? '#ff3366' : '#00e5ff', boxShadow: `0 0 10px ${danger ? 'rgba(255,51,102,0.2)' : 'rgba(0,229,255,0.2)'}` }}
          >{saveLabel}</motion.button>
        </div>
      </motion.div>
    </motion.div>
  );
}
