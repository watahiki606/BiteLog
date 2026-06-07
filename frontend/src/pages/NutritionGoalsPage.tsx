import { useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { api, type NutritionGoals } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}

export default function NutritionGoalsPage({ onToast }: Props) {
  const [goals, setGoals] = useState<NutritionGoals>({ targetProtein: 0, targetFat: 0, targetNetCarbs: 0, targetFiber: 0 });
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    async function fetchGoals() {
      setLoading(true);
      try {
        const data = await api.nutritionGoals.get();
        setGoals(data);
      } catch {
        onToast({ message: '目標の取得に失敗しました', type: 'error' });
      } finally {
        setLoading(false);
      }
    }
    fetchGoals();
  }, [onToast]);

  async function handleSave() {
    setSaving(true);
    try {
      await api.nutritionGoals.update(goals);
      onToast({ message: '目標を保存しました', type: 'success' });
    } catch {
      onToast({ message: '保存に失敗しました', type: 'error' });
    } finally {
      setSaving(false);
    }
  }

  const targetCalories = Math.round(
    goals.targetProtein * 4 + goals.targetFat * 9 + goals.targetNetCarbs * 4 + goals.targetFiber * 2
  );

  const fields: { key: keyof NutritionGoals; label: string; color: string }[] = [
    { key: 'targetProtein',  label: 'PROTEIN',   color: '#00ff41' },
    { key: 'targetFat',      label: 'FAT',        color: '#ff00ff' },
    { key: 'targetNetCarbs', label: 'NET CARBS',  color: '#00e5ff' },
    { key: 'targetFiber',    label: 'FIBER',      color: '#6060a0' },
  ];

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full text-muted-foreground tracking-widest text-xs">LOADING...</div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      <div className="px-6 py-4 border-b border-border-dim">
        <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Nutrition Goals</h2>
        <p className="text-xs text-muted-foreground mt-0.5">daily targets</p>
      </div>

      <div className="flex-1 overflow-auto px-6 py-6">
        <div className="max-w-md space-y-4">
          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
            className="bg-bg-card border border-border-dim p-5 mb-6"
          >
            <div className="text-xs text-muted-foreground tracking-widest mb-2">TARGET CALORIES</div>
            <div className="text-4xl font-bold text-neon-yellow">
              {targetCalories}
              <span className="text-sm font-normal ml-2 text-muted-foreground">kcal / day</span>
            </div>
          </motion.div>

          {fields.map((f, i) => (
            <motion.div
              key={f.key}
              initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.05 }}
              className="bg-bg-card border border-border-dim p-4 relative overflow-hidden"
            >
              <div className="absolute left-0 top-0 bottom-0 w-0.5" style={{ background: f.color, boxShadow: `0 0 8px ${f.color}` }} />
              <div className="pl-3">
                <label className="block text-xs text-muted-foreground tracking-widest uppercase mb-2">{f.label}</label>
                <div className="flex items-center gap-3">
                  <input
                    type="number" step="1" min="0"
                    value={goals[f.key]}
                    onChange={(e) => setGoals((g) => ({ ...g, [f.key]: Number(e.target.value) }))}
                    className="bg-bg-surface border border-border-dim px-3 py-2 text-lg font-bold focus:outline-none focus:border-neon-cyan transition-colors w-32 text-right"
                    style={{ color: f.color, fontFamily: 'inherit' }}
                  />
                  <span className="text-sm text-muted-foreground">g</span>
                </div>
              </div>
            </motion.div>
          ))}

          <motion.button
            whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }}
            onClick={handleSave}
            disabled={saving}
            className="w-full py-3 text-sm font-bold tracking-widest uppercase mt-6 disabled:opacity-40 transition-all"
            style={{
              background: 'rgba(0,229,255,0.1)',
              border: '1px solid #00e5ff',
              color: '#00e5ff',
              boxShadow: '0 0 20px rgba(0,229,255,0.2)',
            }}
          >
            {saving ? 'SAVING...' : 'SAVE GOALS'}
          </motion.button>
        </div>
      </div>
    </div>
  );
}
