import { motion } from 'motion/react';

export const fieldClass = "w-full bg-bg-card border border-border-dim px-3 py-1.5 text-xs text-foreground focus:outline-none focus:border-neon-cyan transition-colors";

export function Field({ label, children, colSpan }: { label: React.ReactNode; children: React.ReactNode; colSpan?: number }) {
  return (
    <div className={colSpan === 2 ? 'col-span-2' : ''}>
      <label className="block text-xs text-muted-foreground mb-1 tracking-wider uppercase">{label}</label>
      {children}
    </div>
  );
}

export function Modal({ title, onClose, onSave, saveLabel = 'SAVE', danger = false, wide = false, children }: {
  title: string; onClose: () => void; onSave: () => void; saveLabel?: string; danger?: boolean; wide?: boolean; children: React.ReactNode;
}) {
  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 bg-black/70 flex items-center justify-center z-40 p-4" onClick={onClose}
    >
      <motion.div initial={{ scale: 0.9, y: 10 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.9, y: 10 }}
        className={`w-full ${wide ? 'max-w-2xl' : 'max-w-md'} max-h-full overflow-auto bg-bg-surface border border-border-dim p-6`}
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
