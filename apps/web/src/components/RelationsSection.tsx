import { useMemo, useState } from 'react';
import { motion } from 'motion/react';
import {
  ComposedChart, ScatterChart, Scatter, Line, ErrorBar,
  XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine,
} from 'recharts';
import { Segmented } from '@/components/Segmented';
import { BODY_METRICS, type BodyMetricKey, type DailyStat } from '@/lib/correlation';
import {
  buildWeeks, windowPairs, relationMatrix, windowProfile, nextDayEffects, intakeRelations,
  scatterPoints, estimate, ENERGY_SOURCES, SOURCE_KEYS, WINDOWS,
  type Estimate, type Mode, type SourceKey, type IntakeTarget,
} from '@/lib/relations';

type Tab = 'body' | 'intake';

const SOURCE_LABEL: Record<SourceKey | 'rest', string> = {
  kcal: 'KCAL', protein: 'PROTEIN', fat: 'FAT', carbs: 'CARBS', other: 'OTHER', rest: 'REST',
};

// 増減の向きだけを表す2色。増えるのが良いか悪いかは指標による（筋肉量など）ので、赤/緑は使わない。
const UP = '#ea580c';
const DOWN = '#0284c7';
const SURFACE = '#0d0d22';
const INK = '#c8c8f0';
const MUTED = '#6060a0';
const ACCENT = '#00e5ff';

const tooltipStyle = {
  contentStyle: { background: SURFACE, border: '1px solid #1a1a3e', borderRadius: 0, fontSize: 10, fontFamily: 'JetBrains Mono, monospace' },
  labelStyle: { color: MUTED },
};
const tick = { fill: MUTED, fontSize: 9, fontFamily: 'JetBrains Mono, monospace' };

function significant(e: Estimate): boolean {
  return e.lo > 0 || e.hi < 0;
}

/** 色の濃さは係数の大きさではなく「0からどれだけ確かに離れているか」。指標ごとに単位が違っても比べられる。 */
function cellColor(e: Estimate | null): string {
  if (!e) return 'transparent';
  const se = (e.hi - e.lo) / (2 * 1.96);
  const t = se > 0 ? Math.abs(e.coef) / se : 0;
  const strength = significant(e) ? 0.3 + 0.6 * Math.min((t - 1.96) / 4, 1) : 0.08;
  const color = e.coef >= 0 ? UP : DOWN;
  return `color-mix(in oklab, ${color} ${Math.round(strength * 100)}%, ${SURFACE})`;
}

function fmt(v: number): string {
  // 小さい値は小数点以下の桁数で丸めると目盛りが重なる（0.012 と 0.008 が両方 0.01）ので、有効数字で丸める。
  const a = Math.abs(v);
  const s = a >= 10 ? v.toFixed(0) : a >= 1 ? v.toFixed(1) : String(Number(v.toPrecision(2)));
  return v > 0 ? `+${s}` : s;
}

function describe(e: Estimate | null, unit: string): string {
  if (!e) return 'データが足りません';
  return `${fmt(e.coef)} ${unit}  95%: ${fmt(e.lo)} 〜 ${fmt(e.hi)}  ${e.n}期間`;
}

interface Props {
  items: DailyStat[]; // 全期間の日次
}

export function RelationsSection({ items }: Props) {
  const [tab, setTab] = useState<Tab>('body');
  const [weeks, setWeeks] = useState<number>(4);
  const [mode, setMode] = useState<Mode>('adjusted');
  const [selected, setSelected] = useState<{ source: SourceKey; body: BodyMetricKey }>({ source: 'kcal', body: 'weightKg' });
  const [hover, setHover] = useState<string | null>(null);

  const allWeeks = useMemo(() => buildWeeks(items), [items]);
  const cells = useMemo(() => relationMatrix(allWeeks, weeks, mode), [allWeeks, weeks, mode]);
  const intake = useMemo(() => intakeRelations(allWeeks, weeks), [allWeeks, weeks]);

  // 1期間も係数が出ない指標（その体組成計では測っていない等）は列ごと出さない。
  const metrics = BODY_METRICS.filter((m) => cells.some((c) => c.body === m.key && c.estimate));
  const body = metrics.find((m) => m.key === selected.body) ?? metrics[0];

  if (!body) return null;

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
      className="bg-bg-card border border-border-dim p-4"
    >
      <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
        <span className="text-xs text-muted-foreground tracking-widest">RELATIONS</span>
        <Segmented
          options={[{ key: 'body' as Tab, label: 'body' }, { key: 'intake' as Tab, label: 'intake' }]}
          value={tab}
          onChange={setTab}
        />
      </div>

      <div className="flex flex-wrap items-center gap-3 mb-3">
        <Segmented
          options={WINDOWS.map((w) => ({ key: String(w), label: `${w}w` }))}
          value={String(weeks)}
          onChange={(v) => setWeeks(Number(v))}
        />
        {tab === 'body' && (
          <Segmented
            options={[{ key: 'single' as Mode, label: 'alone' }, { key: 'adjusted' as Mode, label: 'others fixed' }]}
            value={mode}
            onChange={setMode}
          />
        )}
      </div>

      {tab === 'body' ? (
        <>
          <p className="text-xs text-muted-foreground mb-3 leading-relaxed">
            1日 +100kcal 多く食べた{weeks}週間の前後で、体組成がどれだけ変わったか。
            {mode === 'adjusted' ? '他の栄養素は同じだったとした場合の値。' : 'その栄養素だけで見た値で、一緒に増えた他の栄養素の分も含む。'}
            OTHER は記録カロリーから PFC 換算を引いた残りで、アルコールのほか、PFC が入力されていない食品の分も入る。
          </p>
          <div className="overflow-x-auto">
            <table className="text-xs border-separate" style={{ borderSpacing: 2 }}>
              <thead>
                <tr>
                  <th />
                  {metrics.map((m) => (
                    <th key={m.key} className="w-16 font-normal tracking-wider px-1 pb-1 text-left align-bottom leading-tight" style={{ color: MUTED }}>
                      <div>{m.label}</div>
                      <div className="opacity-70">{m.unit || '—'}</div>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {SOURCE_KEYS.map((s) => (
                  <tr key={s}>
                    <th className="font-normal tracking-widest pr-2 text-left" style={{ color: MUTED }}>{SOURCE_LABEL[s]}</th>
                    {metrics.map((m) => {
                      const e = cells.find((c) => c.source === s && c.body === m.key)!.estimate;
                      const active = selected.source === s && body.key === m.key;
                      const text = `${SOURCE_LABEL[s]} × ${m.label}: ${describe(e, m.unit)}`;
                      return (
                        <td key={m.key} className="p-0">
                          <button
                            type="button"
                            onClick={() => setSelected({ source: s, body: m.key })}
                            onMouseEnter={() => setHover(text)}
                            onMouseLeave={() => setHover(null)}
                            onFocus={() => setHover(text)}
                            onBlur={() => setHover(null)}
                            aria-label={text}
                            aria-pressed={active}
                            className="w-16 h-8 tabular-nums"
                            style={{
                              background: cellColor(e),
                              color: INK,
                              outline: active ? `2px solid ${ACCENT}` : 'none',
                              outlineOffset: -2,
                            }}
                          >{e && significant(e) ? fmt(e.coef) : ''}</button>
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Legend hover={hover} />
          <Detail items={items} allWeeks={allWeeks} weeks={weeks} mode={mode} source={selected.source} body={body} />
        </>
      ) : (
        <IntakeTable intake={intake} weeks={weeks} hover={hover} setHover={setHover} />
      )}
    </motion.div>
  );
}

function Legend({ hover }: { hover: string | null }) {
  return (
    <div className="mt-2 text-xs min-h-8" style={{ color: MUTED }}>
      {hover ?? (
        <span className="flex flex-wrap items-center gap-x-4 gap-y-1">
          <span className="flex items-center gap-1.5"><i className="w-3 h-3 inline-block" style={{ background: UP }} />増えた</span>
          <span className="flex items-center gap-1.5"><i className="w-3 h-3 inline-block" style={{ background: DOWN }} />減った</span>
          <span>濃いほど確か。数字の無い薄いマスは0と区別できない</span>
        </span>
      )}
    </div>
  );
}

function Detail({ items, allWeeks, weeks, mode, source, body }: {
  items: DailyStat[];
  allWeeks: ReturnType<typeof buildWeeks>;
  weeks: number;
  mode: Mode;
  source: SourceKey;
  body: (typeof BODY_METRICS)[number];
}) {
  const pairs = useMemo(() => windowPairs(allWeeks, weeks), [allWeeks, weeks]);
  const current = useMemo(() => estimate(pairs, source, body.key, mode, 2 * weeks), [pairs, source, body.key, mode, weeks]);
  const points = useMemo(() => scatterPoints(pairs, source, body.key, mode), [pairs, source, body.key, mode]);
  const profile = useMemo(() => windowProfile(allWeeks, source, body.key, mode), [allWeeks, source, body.key, mode]);
  const nextDay = useMemo(() => nextDayEffects(items, source, body.key, mode), [items, source, body.key, mode]);

  // 散布図の回帰線。点の重心を通り、傾きは係数（+100kcal あたり）。
  const line = useMemo(() => {
    if (!current || points.length === 0) return null;
    const xs = points.map((p) => p.x);
    const mx = xs.reduce((s, v) => s + v, 0) / xs.length;
    const my = points.reduce((s, p) => s + p.y, 0) / points.length;
    const slope = current.coef / 100;
    const x0 = Math.min(...xs), x1 = Math.max(...xs);
    return [{ x: x0, y: my + slope * (x0 - mx) }, { x: x1, y: my + slope * (x1 - mx) }] as const;
  }, [current, points]);

  const unit = body.unit;
  const errRow = (label: string, e: Estimate | null) => ({
    label, coef: e?.coef ?? null, err: e ? [e.coef - e.lo, e.hi - e.coef] : null,
  });
  const profileData = profile.map((p) => errRow(`${p.weeks}w`, p.estimate));
  const nextDayData = nextDay.map((d) => errRow(['当日', '前日', '前々日'][d.lag], d.estimate));

  return (
    <div className="mt-4 pt-4 border-t border-border-dim">
      <div className="flex flex-wrap items-baseline gap-x-3 mb-3 text-xs">
        <span className="tracking-widest" style={{ color: ACCENT }}>{SOURCE_LABEL[source]} × {body.label}</span>
        <span className="tabular-nums" style={{ color: INK }}>{describe(current, unit)}</span>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <figure>
          <figcaption className="text-xs text-muted-foreground mb-1">
            {weeks}週間の1日平均摂取と、前後の変化{mode === 'adjusted' && source !== 'kcal' ? '。他の栄養素で説明できない分どうし' : ''}
          </figcaption>
          <ResponsiveContainer width="100%" height={180}>
            <ScatterChart margin={{ top: 8, right: 8, bottom: 4, left: 0 }}>
              <XAxis type="number" dataKey="x" name="kcal/日" tick={tick} axisLine={false} tickLine={false}
                domain={['auto', 'auto']} tickFormatter={(v) => String(Math.round(v))} />
              <YAxis type="number" dataKey="y" name={`変化 ${unit}`} tick={tick} axisLine={false} tickLine={false}
                width={36} domain={['auto', 'auto']} tickFormatter={(v) => fmt(v)} />
              <ReferenceLine y={0} stroke="#ffffff20" />
              <Tooltip {...tooltipStyle} cursor={{ stroke: '#ffffff30' }}
                formatter={(v, name) => [name === 'kcal/日' ? `${Math.round(Number(v))} kcal/日` : `${fmt(Number(v))} ${unit}`, String(name)]} />
              <Scatter data={points} fill={ACCENT} fillOpacity={0.35} shape="circle" />
              {line && <ReferenceLine segment={line} stroke={INK} strokeWidth={2} ifOverflow="extendDomain" />}
            </ScatterChart>
          </ResponsiveContainer>
        </figure>
        <CoefChart
          caption="期間の長さを変えたとき。溜まり続けるものは期間とともに大きくなり、一時的なものは頭打ちになる"
          data={profileData} unit={unit} highlight={`${weeks}w`}
        />
        <CoefChart
          caption="朝から翌朝の変化を、当日・前日・前々日の摂取で見たとき"
          data={nextDayData} unit={unit}
        />
      </div>
    </div>
  );
}

function CoefChart({ caption, data, unit, highlight }: {
  caption: string;
  data: { label: string; coef: number | null; err: number[] | null }[];
  unit: string;
  highlight?: string;
}) {
  return (
    <figure>
      <figcaption className="text-xs text-muted-foreground mb-1">{caption}</figcaption>
      <ResponsiveContainer width="100%" height={180}>
        <ComposedChart data={data} margin={{ top: 8, right: 8, bottom: 4, left: 0 }}>
          <XAxis dataKey="label" tick={tick} axisLine={false} tickLine={false} />
          <YAxis tick={tick} axisLine={false} tickLine={false} width={36} domain={['auto', 'auto']} tickFormatter={(v) => fmt(v)} />
          <ReferenceLine y={0} stroke="#ffffff30" />
          <Tooltip {...tooltipStyle} cursor={{ stroke: '#ffffff30' }}
            formatter={(v, _n, item) => {
              const err = (item.payload as { err: number[] | null }).err;
              const c = Number(v);
              return [err ? `${fmt(c)} ${unit}  95%: ${fmt(c - err[0])} 〜 ${fmt(c + err[1])}` : '—', '+100kcal/日'];
            }} />
          <Line dataKey="coef" stroke={ACCENT} strokeWidth={2} connectNulls={false} isAnimationActive={false}
            dot={(props) => {
              const { cx, cy, payload } = props as { cx?: number; cy?: number; payload: { label: string } };
              if (cx == null || cy == null) return <g key={payload.label} />;
              const on = payload.label === highlight;
              return <circle key={payload.label} cx={cx} cy={cy} r={on ? 5 : 4} fill={on ? ACCENT : SURFACE} stroke={ACCENT} strokeWidth={2} />;
            }}>
            <ErrorBar dataKey="err" width={6} strokeWidth={1.5} stroke={MUTED} />
          </Line>
        </ComposedChart>
      </ResponsiveContainer>
    </figure>
  );
}

function IntakeTable({ intake, weeks, hover, setHover }: {
  intake: ReturnType<typeof intakeRelations>;
  weeks: number;
  hover: string | null;
  setHover: (v: string | null) => void;
}) {
  const targets: IntakeTarget[] = [...ENERGY_SOURCES, 'rest'];
  return (
    <>
      <p className="text-xs text-muted-foreground mb-3 leading-relaxed">
        ある栄養素が1日 +100kcal 多かった{weeks}週間に、他の栄養素が何kcal 動いたか。
        REST は自分以外の合計で、−100 なら増えた分を他で完全に打ち消している。
      </p>
      <div className="overflow-x-auto">
        <table className="text-xs border-separate" style={{ borderSpacing: 2 }}>
          <thead>
            <tr>
              <th />
              {targets.map((t) => (
                <th key={t} className="w-16 font-normal tracking-wider px-1 pb-1 text-left" style={{ color: MUTED }}>{SOURCE_LABEL[t]}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {ENERGY_SOURCES.map((x) => (
              <tr key={x}>
                <th className="font-normal tracking-widest pr-2 text-left" style={{ color: MUTED }}>+{SOURCE_LABEL[x]}</th>
                {targets.map((y) => {
                  if (y === x) return <td key={y} />;
                  const e = intake.find((r) => r.x === x && r.y === y)!.estimate;
                  const text = `${SOURCE_LABEL[x]} +100kcal → ${SOURCE_LABEL[y]}: ${describe(e, 'kcal')}`;
                  return (
                    <td key={y} className="p-0">
                      <div
                        tabIndex={0}
                        role="img"
                        aria-label={text}
                        onMouseEnter={() => setHover(text)}
                        onMouseLeave={() => setHover(null)}
                        onFocus={() => setHover(text)}
                        onBlur={() => setHover(null)}
                        className="w-16 h-8 flex items-center justify-center tabular-nums"
                        style={{ background: cellColor(e), color: INK }}
                      >{e && significant(e) ? fmt(e.coef) : ''}</div>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Legend hover={hover} />
    </>
  );
}
