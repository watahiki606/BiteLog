import { useState, useCallback, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';
import { useBodyMeasurements, type BodyMeasurement } from '@/hooks/useBodyMeasurements';

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}

// 手動追加フォーム。measuredAt は datetime-local、その他は任意の数値。
const emptyForm = {
  measuredAt: '',
  weightKg: '',
  bodyFatPercent: '',
  muscleMassKg: '',
  muscleScore: '',
  visceralFatLevel: '',
  basalMetabolismKcal: '',
  metabolicAge: '',
  boneMassKg: '',
  bodyWaterPercent: '',
};
type FormData = typeof emptyForm;

const numFields: { key: keyof FormData; label: string; step?: string }[] = [
  { key: 'weightKg',            label: '体重 (kg)',        step: '0.1' },
  { key: 'bodyFatPercent',      label: '体脂肪率 (%)',     step: '0.1' },
  { key: 'muscleMassKg',        label: '筋肉量 (kg)',      step: '0.1' },
  { key: 'muscleScore',         label: '筋肉スコア',       step: '1' },
  { key: 'visceralFatLevel',    label: '内臓脂肪レベル',   step: '0.5' },
  { key: 'basalMetabolismKcal', label: '基礎代謝 (kcal)',  step: '1' },
  { key: 'metabolicAge',        label: '体内年齢',         step: '1' },
  { key: 'boneMassKg',          label: '推定骨量 (kg)',    step: '0.1' },
  { key: 'bodyWaterPercent',    label: '体水分率 (%)',     step: '0.1' },
];

function fmtDateTime(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleString('ja-JP', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });
}

function num(v: number | null): string {
  return v == null ? '—' : String(v);
}

export default function BodyMeasurementPage({ onToast }: Props) {
  const onError = useCallback(
    () => onToast({ message: 'データの取得に失敗しました', type: 'error' }),
    [onToast]
  );
  const { data, isLoading, mutate } = useBodyMeasurements(onError);
  const items = data ?? [];

  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState<FormData>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [importing, setImporting] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<BodyMeasurement | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  function openAdd() {
    setForm(emptyForm);
    setModalOpen(true);
  }

  function setField<K extends keyof FormData>(key: K, val: FormData[K]) {
    setForm((f) => ({ ...f, [key]: val }));
  }

  async function handleSave() {
    if (!form.measuredAt) {
      onToast({ message: '計測日時を入力してください', type: 'error' });
      return;
    }
    const measuredAt = new Date(form.measuredAt).toISOString();
    const sourceDate = measuredAt.slice(0, 10);
    const payload: Record<string, unknown> = {
      measuredAt, sourceDate, inputMethod: '手動入力',
    };
    for (const f of numFields) {
      const raw = form[f.key];
      if (raw !== '') payload[f.key] = Number(raw);
    }

    setSaving(true);
    try {
      const res = await createClient().api['body-measurements'].$post({ json: payload });
      if (res.status === 409) {
        onToast({ message: 'その日時の計測データは既に存在します', type: 'error' });
        return;
      }
      if (!res.ok) throw new Error();
      onToast({ message: '追加しました', type: 'success' });
      setModalOpen(false);
      mutate();
    } catch {
      onToast({ message: '保存に失敗しました', type: 'error' });
    } finally {
      setSaving(false);
    }
  }

  async function handleImport(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = ''; // 同じファイルを再選択できるようにリセット
    if (!file) return;

    setImporting(true);
    try {
      const csvText = await file.text();
      const res = await createClient().api['body-measurements'].import.$post(
        {},
        { init: { body: csvText, headers: { 'Content-Type': 'text/csv' } } }
      );
      if (!res.ok) throw new Error();
      const { created, skipped } = await res.json();
      onToast({ message: `${created}件登録（${skipped}件スキップ）`, type: 'success' });
      mutate();
    } catch {
      onToast({ message: 'インポートに失敗しました', type: 'error' });
    } finally {
      setImporting(false);
    }
  }

  async function handleDelete(item: BodyMeasurement) {
    try {
      const res = await createClient().api['body-measurements'][':id'].$delete({ param: { id: item.id } });
      if (!res.ok) throw new Error();
      onToast({ message: '削除しました', type: 'success' });
      setDeleteTarget(null);
      mutate();
    } catch {
      onToast({ message: '削除に失敗しました', type: 'error' });
    }
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between px-6 py-4 border-b border-border-dim">
        <div>
          <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Body Measurements</h2>
          <p className="text-xs text-muted-foreground mt-0.5">{items.length} records</p>
        </div>
        <div className="flex items-center gap-3">
          <input ref={fileRef} type="file" accept=".csv,text/csv" onChange={handleImport} className="hidden" />
          <motion.button whileHover={{ scale: 1.03 }} whileTap={{ scale: 0.97 }}
            onClick={() => fileRef.current?.click()} disabled={importing}
            className="px-4 py-1.5 text-xs font-bold tracking-widest uppercase disabled:opacity-40"
            style={{ background: 'rgba(0,229,255,0.1)', border: '1px solid #00e5ff', color: '#00e5ff', boxShadow: '0 0 10px rgba(0,229,255,0.2)' }}
          >{importing ? 'IMPORTING...' : '⇪ IMPORT CSV'}</motion.button>
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
              {['計測日時', '体重kg', '体脂肪%', '筋肉kg', '内臓脂肪', '基礎代謝', '体内年齢', '体水分%', ''].map((h) => (
                <th key={h} className="px-4 py-3 text-left text-muted-foreground tracking-widest font-normal border-b border-border-dim">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={9} className="px-4 py-8 text-center text-muted-foreground tracking-widest">LOADING...</td></tr>
            ) : items.length === 0 ? (
              <tr><td colSpan={9} className="px-4 py-8 text-center text-muted-foreground tracking-widest">NO DATA</td></tr>
            ) : items.map((item) => (
              <motion.tr key={item.id} initial={{ opacity: 0 }} animate={{ opacity: 1 }}
                className="border-b border-border-dim hover:bg-neon-cyan/5 transition-colors group"
              >
                <td className="px-4 py-3 text-foreground whitespace-nowrap">{fmtDateTime(item.measuredAt)}</td>
                <td className="px-4 py-3 text-neon-yellow">{num(item.weightKg)}</td>
                <td className="px-4 py-3 text-neon-magenta">{num(item.bodyFatPercent)}</td>
                <td className="px-4 py-3 text-neon-green">{num(item.muscleMassKg)}</td>
                <td className="px-4 py-3 text-neon-cyan">{num(item.visceralFatLevel)}</td>
                <td className="px-4 py-3 text-muted-foreground">{num(item.basalMetabolismKcal)}</td>
                <td className="px-4 py-3 text-muted-foreground">{num(item.metabolicAge)}</td>
                <td className="px-4 py-3 text-muted-foreground">{num(item.bodyWaterPercent)}</td>
                <td className="px-4 py-3">
                  <div className="flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button onClick={() => setDeleteTarget(item)} className="px-2 py-1 text-xs text-destructive border border-destructive/30 hover:border-destructive hover:bg-destructive/10 transition-all">DEL</button>
                  </div>
                </td>
              </motion.tr>
            ))}
          </tbody>
        </table>
      </div>

      <AnimatePresence>
        {modalOpen && (
          <Modal title="ADD MEASUREMENT" onClose={() => setModalOpen(false)} onSave={handleSave} saveLabel={saving ? 'SAVING...' : 'SAVE'}>
            <div className="grid grid-cols-2 gap-3">
              <Field label="計測日時" colSpan={2}>
                <input type="datetime-local" value={form.measuredAt} onChange={(e) => setField('measuredAt', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} />
              </Field>
              {numFields.map((f) => (
                <Field key={f.key} label={f.label}>
                  <input type="number" step={f.step} value={form[f.key]} onChange={(e) => setField(f.key, e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} />
                </Field>
              ))}
            </div>
          </Modal>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {deleteTarget && (
          <Modal title="DELETE CONFIRM" onClose={() => setDeleteTarget(null)} onSave={() => handleDelete(deleteTarget)} saveLabel="DELETE" danger>
            <p className="text-sm text-foreground"><span className="text-neon-cyan">{fmtDateTime(deleteTarget.measuredAt)}</span> の計測データを削除しますか？</p>
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
