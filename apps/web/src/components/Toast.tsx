import { useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';

export interface ToastMessage {
  id: string;
  message: string;
  type: 'success' | 'error' | 'info';
}

interface Props {
  toasts: ToastMessage[];
  onRemove: (id: string) => void;
}

export default function Toast({ toasts, onRemove }: Props) {
  return (
    <div className="fixed bottom-6 right-6 space-y-2 z-50">
      <AnimatePresence>
        {toasts.map((toast) => (
          <ToastItem key={toast.id} toast={toast} onRemove={onRemove} />
        ))}
      </AnimatePresence>
    </div>
  );
}

function ToastItem({ toast, onRemove }: { toast: ToastMessage; onRemove: (id: string) => void }) {
  useEffect(() => {
    const timer = setTimeout(() => onRemove(toast.id), 3000);
    return () => clearTimeout(timer);
  }, [toast.id, onRemove]);

  const colors = {
    success: { border: '#00ff41', text: '#00ff41', glow: 'rgba(0,255,65,0.3)' },
    error: { border: '#ff3366', text: '#ff3366', glow: 'rgba(255,51,102,0.3)' },
    info: { border: '#00e5ff', text: '#00e5ff', glow: 'rgba(0,229,255,0.3)' },
  }[toast.type];

  return (
    <motion.div
      initial={{ opacity: 0, x: 40, scale: 0.9 }}
      animate={{ opacity: 1, x: 0, scale: 1 }}
      exit={{ opacity: 0, x: 40, scale: 0.9 }}
      transition={{ duration: 0.2 }}
      className="flex items-center gap-3 px-4 py-3 bg-bg-surface text-sm cursor-pointer"
      style={{
        border: `1px solid ${colors.border}`,
        boxShadow: `0 0 15px ${colors.glow}`,
        maxWidth: '280px',
        fontFamily: 'inherit',
      }}
      onClick={() => onRemove(toast.id)}
    >
      <span style={{ color: colors.text }}>
        {toast.type === 'success' ? '✓' : toast.type === 'error' ? '✗' : 'ℹ'}
      </span>
      <span className="text-foreground text-xs tracking-wide">{toast.message}</span>
    </motion.div>
  );
}
