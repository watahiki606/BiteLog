import { useMemo, useState, type ReactNode } from 'react';
import { motion } from 'motion/react';
import type { DailyStat } from '@/lib/correlation';
import { buildWeeks, findings, findingText } from '@/lib/relations';

// 最初に出す件数。多いと、どれが大事か読み取れなくなる。
const FIRST = 5;

interface Props {
  items: DailyStat[]; // 全期間の日次
}

export function RelationsSection({ items }: Props) {
  const [expanded, setExpanded] = useState(false);
  const result = useMemo(() => findings(buildWeeks(items)), [items]);

  let body: ReactNode;
  if (result.kind === 'short') {
    body = (
      <p className="text-xs text-muted-foreground leading-relaxed">
        食事と体組成の記録があと約{result.weeksNeeded}週分たまると、傾向を見られます。
      </p>
    );
  } else {
    const list = result.findings;
    const shown = expanded ? list : list.slice(0, FIRST);
    body = (
      <>
        {list.length > 0 ? (
          <ul className="space-y-3 mb-3">
            {shown.map((f) => {
              const t = findingText(f);
              return (
                <li key={`${f.source}:${f.body}`} className="text-sm leading-relaxed">
                  <div>{t.headline}</div>
                  <div className="text-xs text-muted-foreground">{t.detail}</div>
                </li>
              );
            })}
          </ul>
        ) : null}
        {list.length > FIRST && !expanded && (
          <button onClick={() => setExpanded(true)} className="text-xs text-neon-cyan mb-3">
            ほか {list.length - FIRST} 件
          </button>
        )}
        <p className="text-xs text-muted-foreground leading-relaxed">
          {list.length > 0
            ? 'ほかの組み合わせでは、はっきりした関係は見られませんでした。一緒に動いた傾向で、原因とは限りません。運動など、記録していないことの影響も入ります。'
            : '今の記録では、食べたものと体組成のはっきりした関係は見られませんでした。'}
        </p>
      </>
    );
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
      className="bg-bg-card border border-border-dim p-4"
    >
      <div className="text-xs text-muted-foreground tracking-widest mb-1">RELATIONS</div>
      <div className="text-sm font-bold mb-3">あなたの記録で見られる傾向</div>
      {body}
    </motion.div>
  );
}
