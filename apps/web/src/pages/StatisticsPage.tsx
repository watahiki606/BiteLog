import { useState, useEffect, useCallback } from 'react';
import { motion } from 'motion/react';
import {
  LineChart, Line, BarChart, Bar,
  XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine,
} from 'recharts';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';

type Period = 'week' | 'month' | 'year';
type Metric = 'calories' | 'protein' | 'fat' | 'netCarbs';

interface DaySummary {
  logDate: string;
  mealType: string;
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
}

interface DayTotal {
  date: string;
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
  dietaryFiber: number;
}

interface Goals {
  calories: number;
  protein: number;
  fat: number;
  netCarbs: number;
}

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}

const METRIC_CONFIG: Record<Metric, { label: string; unit: string; color: string }> = {
  calories: { label: 'CALORIES', unit: 'kcal', color: '#ffff00' },
  protein:  { label: 'PROTEIN',  unit: 'g',    color: '#00ff41' },
  fat:      { label: 'FAT',      unit: 'g',    color: '#ff00ff' },
  netCarbs: { label: 'CARBS',    unit: 'g',    color: '#00e5ff' },
};

const MEAL_COLORS: Record<string, string> = {
  Breakfast: '#00ff41',
  Lunch:     '#00e5ff',
  Dinner:    '#ff00ff',
  Snack:     '#ffff00',
  Other:     '#6060a0',
};

const PERIOD_DAYS: Record<Period, number> = { week: 7, month: 30, year: 365 };

function formatDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function getRange(period: Period): { from: string; to: string } {
  const end = new Date();
  const start = new Date();
  start.setDate(start.getDate() - (PERIOD_DAYS[period] - 1));
  return { from: formatDate(start), to: formatDate(end) };
}

function aggregateDaily(items: DaySummary[]): Map<string, DayTotal> {
  const map = new Map<string, DayTotal>();
  for (const item of items) {
    const e = map.get(item.logDate) ?? { date: item.logDate, calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0 };
    map.set(item.logDate, {
      date: item.logDate,
      calories: e.calories + item.calories,
      protein: e.protein + item.protein,
      fat: e.fat + item.fat,
      netCarbs: e.netCarbs + item.netCarbs,
      dietaryFiber: e.dietaryFiber + item.dietaryFiber,
    });
  }
  return map;
}

function fillDays(dailyMap: Map<string, DayTotal>, from: string, to: string): DayTotal[] {
  const result: DayTotal[] = [];
  let current = from;
  while (current <= to) {
    result.push(dailyMap.get(current) ?? { date: current, calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0 });
    const d = new Date(current + 'T00:00:00');
    d.setDate(d.getDate() + 1);
    current = formatDate(d);
  }
  return result;
}

function weeklyBuckets(dailyTotals: DayTotal[]): DayTotal[] {
  const weeks = new Map<string, DayTotal>();
  for (const day of dailyTotals) {
    const d = new Date(day.date + 'T00:00:00');
    const dow = d.getDay();
    d.setDate(d.getDate() - (dow === 0 ? 6 : dow - 1));
    const key = formatDate(d);
    const e = weeks.get(key) ?? { date: key, calories: 0, protein: 0, fat: 0, netCarbs: 0, dietaryFiber: 0 };
    weeks.set(key, {
      date: key,
      calories: e.calories + day.calories,
      protein: e.protein + day.protein,
      fat: e.fat + day.fat,
      netCarbs: e.netCarbs + day.netCarbs,
      dietaryFiber: e.dietaryFiber + day.dietaryFiber,
    });
  }
  return Array.from(weeks.values()).sort((a, b) => a.date.localeCompare(b.date));
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DAYS   = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function makeXFormatter(period: Period) {
  return (dateStr: string) => {
    const d = new Date(dateStr + 'T00:00:00');
    if (period === 'week')  return DAYS[d.getDay()];
    if (period === 'month') return `${d.getMonth() + 1}/${d.getDate()}`;
    return MONTHS[d.getMonth()];
  };
}

// ─── Sub-components ──────────────────────────────────────────

function CalorieRing({ value, target }: { value: number; target: number }) {
  const pct    = target > 0 ? value / target : 0;
  const capped = Math.min(pct, 1);
  const r      = 38;
  const circ   = 2 * Math.PI * r;
  const offset = circ * (1 - capped);
  const color  = pct > 1.1 ? '#ff3366' : pct >= 0.9 ? '#00ff41' : '#00e5ff';

  return (
    <svg width="96" height="96" viewBox="0 0 96 96" style={{ flexShrink: 0 }}>
      <circle cx="48" cy="48" r={r} fill="none" stroke="#1a1a3e" strokeWidth="8" />
      <circle
        cx="48" cy="48" r={r} fill="none"
        stroke={color} strokeWidth="8"
        strokeDasharray={circ}
        strokeDashoffset={offset}
        transform="rotate(-90 48 48)"
        style={{ filter: `drop-shadow(0 0 4px ${color})`, transition: 'stroke-dashoffset 0.5s ease' }}
      />
      <text x="48" y="45" textAnchor="middle" fill={color} fontSize="14" fontWeight="bold" fontFamily="JetBrains Mono, monospace">
        {Math.round(value)}
      </text>
      <text x="48" y="59" textAnchor="middle" fill="#6060a0" fontSize="8" fontFamily="JetBrains Mono, monospace">
        kcal/day
      </text>
    </svg>
  );
}

function MacroBar({ label, value, target, unit, color }: { label: string; value: number; target: number; unit: string; color: string }) {
  const pct  = target > 0 ? Math.min(value / target, 1) : 0;
  const over = target > 0 && value > target;
  return (
    <div className="mb-2.5">
      <div className="flex justify-between text-xs mb-1">
        <span className="tracking-widest" style={{ color }}>{label}</span>
        <span className="text-muted-foreground">{(Math.round(value * 10) / 10)}{unit}</span>
      </div>
      <div className="h-1.5 bg-bg-deep overflow-hidden" style={{ border: '1px solid #1a1a3e' }}>
        <div
          className="h-full transition-all duration-500"
          style={{ width: `${pct * 100}%`, background: over ? '#ff3366' : color, boxShadow: `0 0 6px ${over ? '#ff3366' : color}` }}
        />
      </div>
    </div>
  );
}

const chartTooltipStyle = {
  contentStyle: { background: '#0d0d22', border: '1px solid #1a1a3e', borderRadius: 0, fontSize: 10, fontFamily: 'JetBrains Mono, monospace' },
  labelStyle:   { color: '#6060a0' },
};

// ─── Main page ───────────────────────────────────────────────

export default function StatisticsPage({ onToast }: Props) {
  const [period, setPeriod]   = useState<Period>('month');
  const [metric, setMetric]   = useState<Metric>('calories');
  const [items, setItems]     = useState<DaySummary[]>([]);
  const [goals, setGoals]     = useState<Goals>({ calories: 0, protein: 0, fat: 0, netCarbs: 0 });
  const [loading, setLoading] = useState(false);

  const fetchData = useCallback(async (p: Period) => {
    setLoading(true);
    const { from, to } = getRange(p);
    try {
      const client = createClient();
      const [summaryRes, goalsRes] = await Promise.all([
        client.api['log-items'].summary.$get({ query: { from, to } }),
        client.api['nutrition-goals'].$get(),
      ]);
      if (!summaryRes.ok) throw new Error('summary');
      const summaryData = await summaryRes.json();
      setItems(summaryData.items as DaySummary[]);

      if (goalsRes.ok) {
        const g = await goalsRes.json() as { targetProtein: number; targetFat: number; targetNetCarbs: number; targetFiber: number };
        setGoals({
          calories: Math.round(g.targetProtein * 4 + g.targetFat * 9 + g.targetNetCarbs * 4 + g.targetFiber * 2),
          protein:  g.targetProtein,
          fat:      g.targetFat,
          netCarbs: g.targetNetCarbs,
        });
      }
    } catch {
      onToast({ message: 'データの取得に失敗しました', type: 'error' });
    } finally {
      setLoading(false);
    }
  }, [onToast]);

  useEffect(() => { fetchData(period); }, [period, fetchData]);

  // ─── Derived data ─────────────────────────────────────────

  const { from, to } = getRange(period);
  const days         = PERIOD_DAYS[period];
  const dailyMap     = aggregateDaily(items);
  const dailyFilled  = fillDays(dailyMap, from, to);
  const chartData    = period === 'year' ? weeklyBuckets(dailyFilled) : dailyFilled;
  const xFormatter   = makeXFormatter(period);

  const periodTotal = dailyFilled.reduce(
    (acc, d) => ({ calories: acc.calories + d.calories, protein: acc.protein + d.protein, fat: acc.fat + d.fat, netCarbs: acc.netCarbs + d.netCarbs }),
    { calories: 0, protein: 0, fat: 0, netCarbs: 0 }
  );
  const avg = {
    calories: periodTotal.calories / days,
    protein:  periodTotal.protein  / days,
    fat:      periodTotal.fat      / days,
    netCarbs: periodTotal.netCarbs / days,
  };

  const activeDays = dailyFilled.filter(d => d.calories > 0).length;
  const goalDays   = dailyFilled.filter(d => d.calories > 0 && goals.calories > 0 && Math.abs(d.calories - goals.calories) / goals.calories <= 0.1).length;

  const pfcE     = { p: avg.protein * 4, f: avg.fat * 9, c: avg.netCarbs * 4 };
  const pfcTotal = pfcE.p + pfcE.f + pfcE.c;
  const pfc      = pfcTotal > 0
    ? { protein: (pfcE.p / pfcTotal) * 100, fat: (pfcE.f / pfcTotal) * 100, carbs: (pfcE.c / pfcTotal) * 100 }
    : { protein: 0, fat: 0, carbs: 0 };

  const mealTotals: Record<string, number> = {};
  for (const item of items) {
    mealTotals[item.mealType] = (mealTotals[item.mealType] ?? 0) + item.calories;
  }
  const maxMealCal = Math.max(...Object.values(mealTotals), 1);

  const metricConf = METRIC_CONFIG[metric];

  // ─── Render ───────────────────────────────────────────────

  return (
    <div className="flex flex-col h-full overflow-y-auto">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-border-dim flex-shrink-0">
        <div>
          <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Statistics</h2>
          <p className="text-xs text-muted-foreground mt-0.5">{activeDays} active days</p>
        </div>
        <div className="flex gap-1">
          {(['week', 'month', 'year'] as Period[]).map((p) => (
            <button
              key={p}
              onClick={() => setPeriod(p)}
              className="px-3 py-1.5 text-xs tracking-widest uppercase transition-all"
              style={{
                border:     `1px solid ${period === p ? '#00e5ff' : '#1a1a3e'}`,
                color:      period === p ? '#00e5ff' : '#6060a0',
                background: period === p ? 'rgba(0,229,255,0.08)' : 'transparent',
                boxShadow:  period === p ? '0 0 8px rgba(0,229,255,0.2)' : 'none',
              }}
            >{p}</button>
          ))}
        </div>
      </div>

      <div className="flex-1 p-6 space-y-4">

        {/* Trend Chart */}
        <motion.div
          initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
          className="bg-bg-card border border-border-dim p-4"
        >
          <div className="flex items-center justify-between mb-4">
            <span className="text-xs text-muted-foreground tracking-widest">TREND</span>
            <div className="flex gap-1">
              {(Object.entries(METRIC_CONFIG) as [Metric, (typeof METRIC_CONFIG)[Metric]][]).map(([key, conf]) => (
                <button
                  key={key}
                  onClick={() => setMetric(key)}
                  className="px-2.5 py-1 text-xs tracking-widest uppercase transition-all"
                  style={{
                    border:     `1px solid ${metric === key ? conf.color : '#1a1a3e'}`,
                    color:      metric === key ? conf.color : '#6060a0',
                    background: metric === key ? `${conf.color}18` : 'transparent',
                  }}
                >{conf.label}</button>
              ))}
            </div>
          </div>

          {loading ? (
            <div className="h-44 flex items-center justify-center text-muted-foreground tracking-widest text-xs">LOADING...</div>
          ) : (
            <ResponsiveContainer width="100%" height={176}>
              {period === 'year' ? (
                <BarChart data={chartData} margin={{ top: 5, right: 4, bottom: 5, left: 4 }}>
                  <XAxis
                    dataKey="date"
                    tickFormatter={xFormatter}
                    tick={{ fill: '#6060a0', fontSize: 9, fontFamily: 'JetBrains Mono, monospace' }}
                    axisLine={false} tickLine={false}
                    interval="preserveStartEnd"
                  />
                  <YAxis hide domain={[0, 'auto']} />
                  <Tooltip
                    {...chartTooltipStyle}
                    itemStyle={{ color: metricConf.color }}
                    formatter={(v) => [`${Math.round(Number(v) * 10) / 10} ${metricConf.unit}`, metricConf.label]}
                    labelFormatter={(label) => xFormatter(String(label))}
                  />
                  <Bar dataKey={metric} fill={metricConf.color} fillOpacity={0.75} radius={[1, 1, 0, 0]}
                    style={{ filter: `drop-shadow(0 0 3px ${metricConf.color}60)` }}
                  />
                </BarChart>
              ) : (
                <LineChart data={chartData} margin={{ top: 5, right: 4, bottom: 5, left: 4 }}>
                  <XAxis
                    dataKey="date"
                    tickFormatter={xFormatter}
                    tick={{ fill: '#6060a0', fontSize: 9, fontFamily: 'JetBrains Mono, monospace' }}
                    axisLine={false} tickLine={false}
                    interval={period === 'week' ? 0 : 'preserveStartEnd'}
                  />
                  <YAxis hide domain={[0, 'auto']} />
                  <Tooltip
                    {...chartTooltipStyle}
                    itemStyle={{ color: metricConf.color }}
                    formatter={(v) => [`${Math.round(Number(v) * 10) / 10} ${metricConf.unit}`, metricConf.label]}
                    labelFormatter={(label) => xFormatter(String(label))}
                  />
                  {metric === 'calories' && goals.calories > 0 && (
                    <ReferenceLine
                      y={goals.calories}
                      stroke="#ffffff25"
                      strokeDasharray="4 4"
                      label={{ value: `${goals.calories} goal`, fill: '#6060a0', fontSize: 8, fontFamily: 'JetBrains Mono, monospace', position: 'insideTopRight' }}
                    />
                  )}
                  <Line
                    type="monotone"
                    dataKey={metric}
                    stroke={metricConf.color}
                    strokeWidth={1.5}
                    dot={period === 'week' ? { r: 3, fill: metricConf.color, stroke: 'none' } : false}
                    activeDot={{ r: 4, fill: metricConf.color, stroke: 'none' }}
                    style={{ filter: `drop-shadow(0 0 4px ${metricConf.color}80)` }}
                  />
                </LineChart>
              )}
            </ResponsiveContainer>
          )}
        </motion.div>

        {/* Bottom 3 cards */}
        <div className="grid grid-cols-3 gap-4">

          {/* Daily Average */}
          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.08 }}
            className="bg-bg-card border border-border-dim p-4"
          >
            <div className="text-xs text-muted-foreground tracking-widest mb-3">DAILY AVERAGE</div>
            <div className="flex items-center gap-3 mb-4">
              <CalorieRing value={avg.calories} target={goals.calories} />
              <div className="text-xs space-y-2">
                {goals.calories > 0 && (
                  <div>
                    <div className="text-muted-foreground tracking-widest text-xs">TARGET</div>
                    <div className="text-neon-cyan font-bold">{goals.calories}<span className="text-muted-foreground font-normal text-xs"> kcal</span></div>
                  </div>
                )}
                <div>
                  <div className="text-muted-foreground tracking-widest text-xs">GOAL DAYS</div>
                  <div className="text-neon-green font-bold">{goalDays}<span className="text-muted-foreground font-normal">/{days}d</span></div>
                </div>
              </div>
            </div>
            <MacroBar label="PROTEIN" value={avg.protein}  target={goals.protein}  unit="g" color="#00ff41" />
            <MacroBar label="FAT"     value={avg.fat}       target={goals.fat}      unit="g" color="#ff00ff" />
            <MacroBar label="CARBS"   value={avg.netCarbs}  target={goals.netCarbs} unit="g" color="#00e5ff" />
          </motion.div>

          {/* PFC Balance */}
          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.14 }}
            className="bg-bg-card border border-border-dim p-4"
          >
            <div className="text-xs text-muted-foreground tracking-widest mb-3">PFC BALANCE</div>
            <div className="flex h-3 mb-4 overflow-hidden" style={{ border: '1px solid #1a1a3e' }}>
              {pfcTotal > 0 ? (
                <>
                  <div className="h-full" style={{ width: `${pfc.protein}%`, background: '#00ff41', boxShadow: '0 0 6px #00ff4180' }} />
                  <div className="h-full" style={{ width: `${pfc.fat}%`,     background: '#ff00ff', boxShadow: '0 0 6px #ff00ff80' }} />
                  <div className="h-full" style={{ width: `${pfc.carbs}%`,   background: '#00e5ff', boxShadow: '0 0 6px #00e5ff80' }} />
                </>
              ) : (
                <div className="h-full w-full" style={{ background: '#1a1a3e' }} />
              )}
            </div>
            <div className="space-y-2.5">
              {[
                { label: 'PROTEIN', pct: pfc.protein, color: '#00ff41' },
                { label: 'FAT',     pct: pfc.fat,     color: '#ff00ff' },
                { label: 'CARBS',   pct: pfc.carbs,   color: '#00e5ff' },
              ].map(({ label, pct: p, color }) => (
                <div key={label} className="flex items-center gap-2">
                  <div className="w-2 h-2 flex-shrink-0" style={{ background: color, boxShadow: `0 0 4px ${color}` }} />
                  <span className="text-xs tracking-widest w-14" style={{ color }}>{label}</span>
                  <div className="flex-1 h-1 overflow-hidden" style={{ background: '#1a1a3e' }}>
                    <div className="h-full transition-all duration-500" style={{ width: `${p}%`, background: color }} />
                  </div>
                  <span className="text-xs text-muted-foreground w-8 text-right">{Math.round(p)}%</span>
                </div>
              ))}
            </div>
            <div className="mt-4 pt-3 border-t border-border-dim">
              <div className="text-xs text-muted-foreground tracking-widest">ENERGY / DAY</div>
              <div className="text-neon-yellow font-bold">{Math.round(pfcTotal)}<span className="text-muted-foreground font-normal text-xs"> kcal</span></div>
            </div>
          </motion.div>

          {/* By Meal Type */}
          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}
            className="bg-bg-card border border-border-dim p-4"
          >
            <div className="text-xs text-muted-foreground tracking-widest mb-3">BY MEAL TYPE</div>
            <div className="space-y-2.5">
              {['Breakfast', 'Lunch', 'Dinner', 'Snack', 'Other'].map((mealType) => {
                const cal   = mealTotals[mealType] ?? 0;
                const pct   = cal / maxMealCal;
                const color = MEAL_COLORS[mealType] ?? '#6060a0';
                return (
                  <div key={mealType}>
                    <div className="flex justify-between text-xs mb-1">
                      <span className="tracking-widest" style={{ color }}>{mealType.toUpperCase()}</span>
                      <span className="text-muted-foreground">{Math.round(cal).toLocaleString()} kcal</span>
                    </div>
                    <div className="h-1.5 overflow-hidden" style={{ background: '#1a1a3e' }}>
                      <div
                        className="h-full transition-all duration-500"
                        style={{ width: `${pct * 100}%`, background: color, boxShadow: cal > 0 ? `0 0 6px ${color}80` : 'none' }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
            <div className="mt-4 pt-3 border-t border-border-dim">
              <div className="text-xs text-muted-foreground tracking-widest">TOTAL PERIOD</div>
              <div className="text-neon-yellow font-bold">{Math.round(periodTotal.calories).toLocaleString()}<span className="text-muted-foreground font-normal text-xs"> kcal</span></div>
            </div>
          </motion.div>

        </div>
      </div>
    </div>
  );
}
