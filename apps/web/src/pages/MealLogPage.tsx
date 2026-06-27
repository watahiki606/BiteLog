import { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';

interface NutritionSource {
  productName: string;
  brandName: string;
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
  portionSize: number;
}

interface LogItem {
  id: string;
  timestamp: string;
  mealType: string;
  numberOfServings: number;
  isMasterDeleted: boolean;
  foodMaster: NutritionSource | null;
  nutritionSnapshot: NutritionSource | null;
}

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}

const MEAL_COLORS: Record<string, { border: string; bg: string; text: string }> = {
  Breakfast: { border: '#00ff41', bg: 'rgba(0,255,65,0.1)',   text: '#00ff41' },
  Lunch:     { border: '#00e5ff', bg: 'rgba(0,229,255,0.1)',  text: '#00e5ff' },
  Dinner:    { border: '#ff00ff', bg: 'rgba(255,0,255,0.1)',  text: '#ff00ff' },
  Snack:     { border: '#ffff00', bg: 'rgba(255,255,0,0.1)',  text: '#ffff00' },
  Other:     { border: '#6060a0', bg: 'rgba(96,96,160,0.1)', text: '#6060a0' },
};

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function getNutrition(item: LogItem) {
  const src = item.isMasterDeleted ? item.nutritionSnapshot : (item.foodMaster ?? item.nutritionSnapshot);
  if (!src) return { calories: 0, protein: 0, fat: 0, netCarbs: 0, name: '—', brand: '' };
  const ratio = src.portionSize > 0 ? item.numberOfServings / src.portionSize : 0;
  return {
    calories: Math.round(src.calories * ratio),
    protein: Math.round(src.protein * ratio * 10) / 10,
    fat: Math.round(src.fat * ratio * 10) / 10,
    netCarbs: Math.round(src.netCarbs * ratio * 10) / 10,
    name: src.productName,
    brand: src.brandName,
  };
}

export default function MealLogPage({ onToast }: Props) {
  const [date, setDate] = useState(today());
  const [items, setItems] = useState<LogItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<LogItem | null>(null);

  const fetchItems = useCallback(async (d: string) => {
    setLoading(true);
    try {
      const client = createClient();
      const res = await client.api['log-items'].$get({ query: { logDate: d } });
      if (!res.ok) throw new Error();
      const data = await res.json();
      setItems(data.items as LogItem[]);
    } catch {
      onToast({ message: 'データの取得に失敗しました', type: 'error' });
    } finally {
      setLoading(false);
    }
  }, [onToast]);

  useEffect(() => { fetchItems(date); }, [date, fetchItems]);

  async function handleDelete(item: LogItem) {
    try {
      const client = createClient();
      const res = await client.api['log-items'][':id'].$delete({ param: { id: item.id } });
      if (!res.ok) throw new Error();
      onToast({ message: '削除しました', type: 'success' });
      setDeleteTarget(null);
      fetchItems(date);
    } catch {
      onToast({ message: '削除に失敗しました', type: 'error' });
    }
  }

  const totals = items.reduce((acc, item) => {
    const n = getNutrition(item);
    return { calories: acc.calories + n.calories, protein: acc.protein + n.protein, fat: acc.fat + n.fat, netCarbs: acc.netCarbs + n.netCarbs };
  }, { calories: 0, protein: 0, fat: 0, netCarbs: 0 });

  const stats = [
    { label: 'CALORIES', value: totals.calories, unit: 'kcal', color: '#ffff00' },
    { label: 'PROTEIN',  value: totals.protein,  unit: 'g',    color: '#00ff41' },
    { label: 'FAT',      value: totals.fat,       unit: 'g',    color: '#ff00ff' },
    { label: 'NET CARBS',value: totals.netCarbs,  unit: 'g',    color: '#00e5ff' },
  ];

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between px-6 py-4 border-b border-border-dim">
        <div>
          <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Meal Log</h2>
          <p className="text-xs text-muted-foreground mt-0.5">{items.length} entries</p>
        </div>
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)}
          className="bg-bg-card border border-border-dim px-3 py-1.5 text-xs text-neon-cyan focus:outline-none focus:border-neon-cyan transition-colors"
          style={{ fontFamily: 'inherit', colorScheme: 'dark' }}
        />
      </div>

      <div className="grid grid-cols-4 gap-3 px-6 py-4 border-b border-border-dim">
        {stats.map((s, i) => (
          <motion.div key={s.label} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.05 }}
            className="bg-bg-card border border-border-dim p-3 relative overflow-hidden"
          >
            <div className="text-xs text-muted-foreground tracking-widest mb-1">{s.label}</div>
            <div className="text-lg font-bold" style={{ color: s.color }}>
              {s.value}<span className="text-xs font-normal ml-1 text-muted-foreground">{s.unit}</span>
            </div>
            <div className="absolute bottom-0 left-0 right-0 h-0.5 opacity-40" style={{ background: s.color }} />
          </motion.div>
        ))}
      </div>

      <div className="flex-1 overflow-auto">
        <table className="w-full text-xs border-collapse">
          <thead className="sticky top-0 bg-bg-surface">
            <tr>
              {['Time', 'Type', 'Food', 'Servings', 'kcal', 'P', 'F', 'C', ''].map((h) => (
                <th key={h} className="px-4 py-3 text-left text-muted-foreground tracking-widest font-normal border-b border-border-dim">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={9} className="px-4 py-8 text-center text-muted-foreground tracking-widest">LOADING...</td></tr>
            ) : items.length === 0 ? (
              <tr><td colSpan={9} className="px-4 py-8 text-center text-muted-foreground tracking-widest">NO DATA</td></tr>
            ) : items.map((item) => {
              const n = getNutrition(item);
              const c = MEAL_COLORS[item.mealType] ?? MEAL_COLORS.Other;
              return (
                <motion.tr key={item.id} initial={{ opacity: 0 }} animate={{ opacity: 1 }}
                  className="border-b border-border-dim hover:bg-neon-cyan/5 transition-colors group"
                  style={{ opacity: item.isMasterDeleted ? 0.6 : 1 }}
                >
                  <td className="px-4 py-3 text-muted-foreground">
                    {new Date(item.timestamp).toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })}
                  </td>
                  <td className="px-4 py-3">
                    <span className="px-2 py-0.5 text-xs" style={{ border: `1px solid ${c.border}`, background: c.bg, color: c.text }}>{item.mealType}</span>
                  </td>
                  <td className="px-4 py-3">
                    <div className="text-foreground max-w-48 truncate">{n.name}</div>
                    {n.brand && <div className="text-muted-foreground text-xs truncate">{n.brand}</div>}
                    {item.isMasterDeleted && <span className="text-xs text-destructive/60">削除済み</span>}
                  </td>
                  <td className="px-4 py-3 text-muted-foreground">{item.numberOfServings}</td>
                  <td className="px-4 py-3 text-neon-yellow">{n.calories}</td>
                  <td className="px-4 py-3 text-neon-green">{n.protein}g</td>
                  <td className="px-4 py-3 text-neon-magenta">{n.fat}g</td>
                  <td className="px-4 py-3 text-neon-cyan">{n.netCarbs}g</td>
                  <td className="px-4 py-3">
                    <button onClick={() => setDeleteTarget(item)} className="px-2 py-1 text-xs text-destructive border border-destructive/30 hover:border-destructive hover:bg-destructive/10 transition-all opacity-0 group-hover:opacity-100">DEL</button>
                  </td>
                </motion.tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <AnimatePresence>
        {deleteTarget && (
          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/70 flex items-center justify-center z-40" onClick={() => setDeleteTarget(null)}
          >
            <motion.div initial={{ scale: 0.9 }} animate={{ scale: 1 }} exit={{ scale: 0.9 }}
              className="bg-bg-surface border border-border-dim p-6 max-w-sm w-full"
              style={{ boxShadow: '0 0 30px rgba(255,51,102,0.15)' }} onClick={(e) => e.stopPropagation()}
            >
              <h3 className="text-sm font-bold tracking-widest text-destructive mb-4">DELETE CONFIRM</h3>
              <p className="text-sm text-foreground mb-1"><span className="text-neon-cyan">{getNutrition(deleteTarget).name}</span> を削除しますか？</p>
              <p className="text-xs text-muted-foreground mb-6">この操作は取り消せません。</p>
              <div className="flex justify-end gap-3">
                <button onClick={() => setDeleteTarget(null)} className="px-4 py-2 text-xs tracking-widest border border-border-dim text-muted-foreground hover:border-foreground transition-all uppercase">CANCEL</button>
                <button onClick={() => handleDelete(deleteTarget)} className="px-4 py-2 text-xs font-bold tracking-widest uppercase" style={{ background: 'rgba(255,51,102,0.1)', border: '1px solid #ff3366', color: '#ff3366' }}>DELETE</button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
