import { useState, useMemo, useCallback } from 'react';
import { motion } from 'motion/react';
import {
  LineChart, Line, BarChart, Bar,
  XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine,
} from 'recharts';
import type { ToastMessage } from '@/components/Toast';
import { useSummary, useGoals, type Goals } from '@/hooks/useStatistics';
import {
  dailyTotals, fillDays, bucketed, periodTotal, dailyAverage,
  goalAchievedDays, pfcBalance, mealTypeTotals, carbs,
  formatDate,
  type NutritionValues, type Bucket,
} from '@/lib/statistics';

type Period = 'week' | 'month' | 'year';
type Metric = 'calories' | 'protein' | 'fat' | 'carbs';
type Aggregation = 'average' | 'total';

interface Props {
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}

const METRIC_CONFIG: Record<Metric, { label: string; unit: string; color: string }> = {
  calories: { label: 'CALORIES', unit: 'kcal', color: '#ffff00' },
  protein:  { label: 'PROTEIN',  unit: 'g',    color: '#00ff41' },
  fat:      { label: 'FAT',      unit: 'g',    color: '#ff00ff' },
  carbs:    { label: 'CARBS',    unit: 'g',    color: '#00e5ff' },
};

const MEAL_COLORS: Record<string, string> = {
  Breakfast: '#00ff41',
  Lunch:     '#00e5ff',
  Dinner:    '#ff00ff',
  Snack:     '#ffff00',
  Other:     '#6060a0',
};

const PERIOD_DAYS: Record<Period, number> = { week: 7, month: 30, year: 365 };

// period に対して意味のある集計単位だけを出す（棒が1本しか出ない組み合わせを避ける）。
const BUCKETS_FOR: Record<Period, Bucket[]> = {
  week:  ['day'],
  month: ['day', 'week'],
  year:  ['day', 'week', 'month'],
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DAYS   = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function metricValue(v: NutritionValues, m: Metric): number {
  switch (m) {
    case 'calories': return v.calories;
    case 'protein':  return v.protein;
    case 'fat':      return v.fat;
    case 'carbs':    return carbs(v);
  }
}

/** 今日を基準に、offset ページ分だけ過去にずらした表示レンジ [from, to]。 */
function rangeFor(period: Period, offset: number): { from: string; to: string } {
  const days = PERIOD_DAYS[period];
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const to = new Date(today);
  to.setDate(to.getDate() - offset * days);
  const from = new Date(to);
  from.setDate(from.getDate() - (days - 1));
  return { from: formatDate(from), to: formatDate(to) };
}

function makeXFormatter(period: Period, bucket: Bucket) {
  return (dateStr: string) => {
    const d = new Date(dateStr + 'T00:00:00');
    if (bucket === 'month') return MONTHS[d.getMonth()];
    if (bucket === 'day' && period === 'week') return DAYS[d.getDay()];
    return `${d.getMonth() + 1}/${d.getDate()}`;
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

/** 区切りトグル（period / metric / bucket / aggregation 共通の小ボタン群）。 */
function Segmented<T extends string>({ options, value, onChange, colorFor }: {
  options: { key: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  colorFor?: (key: T) => string;
}) {
  return (
    <div className="flex gap-1">
      {options.map(({ key, label }) => {
        const active = value === key;
        const color = colorFor?.(key) ?? '#00e5ff';
        return (
          <button
            key={key}
            onClick={() => onChange(key)}
            aria-pressed={active}
            className="px-2.5 py-1 text-xs tracking-widest uppercase transition-all"
            style={{
              border:     `1px solid ${active ? color : '#1a1a3e'}`,
              color:      active ? color : '#6060a0',
              background: active ? `${color}18` : 'transparent',
            }}
          >{label}</button>
        );
      })}
    </div>
  );
}

const chartTooltipStyle = {
  contentStyle: { background: '#0d0d22', border: '1px solid #1a1a3e', borderRadius: 0, fontSize: 10, fontFamily: 'JetBrains Mono, monospace' },
  labelStyle:   { color: '#6060a0' },
};

// ─── Main page ───────────────────────────────────────────────

export default function StatisticsPage({ onToast }: Props) {
  const [period, setPeriod]           = useState<Period>('month');
  const [metric, setMetric]           = useState<Metric>('calories');
  const [bucket, setBucket]           = useState<Bucket>('day');
  const [aggregation, setAggregation] = useState<Aggregation>('total');
  const [offset, setOffset]           = useState(0);

  const { from, to } = useMemo(() => rangeFor(period, offset), [period, offset]);

  const onError = useCallback(
    () => onToast({ message: 'データの取得に失敗しました', type: 'error' }),
    [onToast]
  );
  const { data: items = [], isLoading } = useSummary(from, to, onError);
  const { data: goalsData } = useGoals();
  const goals: Goals = goalsData ?? { calories: 0, protein: 0, fat: 0, netCarbs: 0, fiber: 0 };

  // period を変えるとページサイズと使える単位が変わるので、レンジを最新に戻し bucket を補正。
  const changePeriod = (p: Period) => {
    setPeriod(p);
    setOffset(0);
    if (!BUCKETS_FOR[p].includes(bucket)) setBucket('day');
  };

  const availableBuckets = BUCKETS_FOR[period];
  const days = PERIOD_DAYS[period];

  // ─── Derived data（items / period / offset / bucket / aggregation に連動して再計算）─

  const filledDaily = useMemo(
    () => fillDays(dailyTotals(items), from, to),
    [items, from, to]
  );

  const chartData = useMemo(() => {
    const series = bucket === 'day'
      ? filledDaily
      : bucketed(filledDaily, bucket, aggregation === 'average');
    return series.map((d) => ({ date: d.date, value: metricValue(d.values, metric) }));
  }, [filledDaily, bucket, aggregation, metric]);

  const avg     = useMemo(() => dailyAverage(items, days), [items, days]);
  const total   = useMemo(() => periodTotal(items), [items]);
  const balance = useMemo(() => pfcBalance(items), [items]);
  const meals   = useMemo(() => mealTypeTotals(items), [items]);

  const activeDays = filledDaily.filter((d) => d.values.calories > 0).length;
  const goalDays   = goalAchievedDays(items, goals.calories);

  // エネルギー/日（1日平均の PFC エネルギー）。
  const energyPerDay = avg.protein * 4 + avg.fat * 9 + avg.netCarbs * 4 + avg.dietaryFiber * 2;
  const maxMealCal   = Math.max(...Object.values(meals).map((v) => v.calories), 1);

  const metricConf = METRIC_CONFIG[metric];
  const xFormatter = makeXFormatter(period, bucket);

  // 合計バケットでは日次目標と比較できないため、目標線は日次か平均のときだけ。
  const showGoalLine = metric === 'calories' && goals.calories > 0
    && (bucket === 'day' || aggregation === 'average');

  // ─── Date navigation ──────────────────────────────────────
  const navLabel = `${from.replaceAll('-', '/')} – ${to.replaceAll('-', '/')}`;

  // ─── Render ───────────────────────────────────────────────

  return (
    <div className="flex flex-col h-full overflow-y-auto">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-border-dim flex-shrink-0">
        <div>
          <h2 className="text-sm font-bold tracking-widest text-neon-cyan text-glow-cyan uppercase">Statistics</h2>
          <p className="text-xs text-muted-foreground mt-0.5">{activeDays} active days</p>
        </div>
        <Segmented
          options={(['week', 'month', 'year'] as Period[]).map((p) => ({ key: p, label: p }))}
          value={period}
          onChange={changePeriod}
        />
      </div>

      <div className="flex-1 p-6 space-y-4">

        {/* Date navigation */}
        <div className="flex items-center justify-between text-xs">
          <button
            onClick={() => setOffset((o) => o + 1)}
            aria-label="前の期間"
            className="px-3 py-1.5 tracking-widest transition-all"
            style={{ border: '1px solid #1a1a3e', color: '#6060a0' }}
          >◀</button>
          <span className="text-muted-foreground tracking-widest">{navLabel}</span>
          <button
            onClick={() => setOffset((o) => Math.max(o - 1, 0))}
            aria-label="次の期間"
            disabled={offset === 0}
            className="px-3 py-1.5 tracking-widest transition-all"
            style={{
              border: '1px solid #1a1a3e',
              color: offset === 0 ? '#2a2a4e' : '#6060a0',
              cursor: offset === 0 ? 'not-allowed' : 'pointer',
            }}
          >▶</button>
        </div>

        {/* Trend Chart */}
        <motion.div
          initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
          className="bg-bg-card border border-border-dim p-4"
        >
          <div className="flex items-center justify-between mb-3">
            <span className="text-xs text-muted-foreground tracking-widest">TREND</span>
            <Segmented
              options={(Object.keys(METRIC_CONFIG) as Metric[]).map((k) => ({ key: k, label: METRIC_CONFIG[k].label }))}
              value={metric}
              onChange={setMetric}
              colorFor={(k) => METRIC_CONFIG[k].color}
            />
          </div>

          {/* Bucket / aggregation controls */}
          <div className="flex items-center justify-between mb-4">
            {availableBuckets.length > 1 ? (
              <Segmented
                options={availableBuckets.map((b) => ({ key: b, label: b }))}
                value={bucket}
                onChange={setBucket}
              />
            ) : <span />}
            {bucket !== 'day' && (
              <Segmented
                options={(['average', 'total'] as Aggregation[]).map((a) => ({ key: a, label: a }))}
                value={aggregation}
                onChange={setAggregation}
              />
            )}
          </div>

          {isLoading ? (
            <div className="h-44 flex items-center justify-center text-muted-foreground tracking-widest text-xs">LOADING...</div>
          ) : (
            <ResponsiveContainer width="100%" height={176}>
              {bucket === 'day' ? (
                <LineChart data={chartData} margin={{ top: 5, right: 4, bottom: 5, left: 4 }}>
                  <XAxis
                    dataKey="date"
                    tickFormatter={xFormatter}
                    tick={{ fill: '#6060a0', fontSize: 9, fontFamily: 'JetBrains Mono, monospace' }}
                    axisLine={false} tickLine={false}
                    interval={chartData.length <= 8 ? 0 : 'preserveStartEnd'}
                  />
                  <YAxis hide domain={[0, 'auto']} />
                  <Tooltip
                    {...chartTooltipStyle}
                    itemStyle={{ color: metricConf.color }}
                    formatter={(v) => [`${Math.round(Number(v) * 10) / 10} ${metricConf.unit}`, metricConf.label]}
                    labelFormatter={(label) => xFormatter(String(label))}
                  />
                  {showGoalLine && (
                    <ReferenceLine
                      y={goals.calories}
                      stroke="#ffffff25"
                      strokeDasharray="4 4"
                      label={{ value: `${goals.calories} goal`, fill: '#6060a0', fontSize: 8, fontFamily: 'JetBrains Mono, monospace', position: 'insideTopRight' }}
                    />
                  )}
                  <Line
                    type="monotone"
                    dataKey="value"
                    stroke={metricConf.color}
                    strokeWidth={1.5}
                    dot={chartData.length <= 14 ? { r: 3, fill: metricConf.color, stroke: 'none' } : false}
                    activeDot={{ r: 4, fill: metricConf.color, stroke: 'none' }}
                    style={{ filter: `drop-shadow(0 0 4px ${metricConf.color}80)` }}
                  />
                </LineChart>
              ) : (
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
                  {showGoalLine && (
                    <ReferenceLine
                      y={goals.calories}
                      stroke="#ffffff25"
                      strokeDasharray="4 4"
                      label={{ value: `${goals.calories} goal`, fill: '#6060a0', fontSize: 8, fontFamily: 'JetBrains Mono, monospace', position: 'insideTopRight' }}
                    />
                  )}
                  <Bar dataKey="value" fill={metricConf.color} fillOpacity={0.75} radius={[1, 1, 0, 0]}
                    style={{ filter: `drop-shadow(0 0 3px ${metricConf.color}60)` }}
                  />
                </BarChart>
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
            <MacroBar label="PROTEIN" value={avg.protein}     target={goals.protein}                unit="g" color="#00ff41" />
            <MacroBar label="FAT"     value={avg.fat}         target={goals.fat}                    unit="g" color="#ff00ff" />
            <MacroBar label="CARBS"   value={carbs(avg)}      target={goals.netCarbs + goals.fiber} unit="g" color="#00e5ff" />
          </motion.div>

          {/* PFC Balance */}
          <motion.div
            initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.14 }}
            className="bg-bg-card border border-border-dim p-4"
          >
            <div className="text-xs text-muted-foreground tracking-widest mb-3">PFC BALANCE</div>
            <div className="flex h-3 mb-4 overflow-hidden" style={{ border: '1px solid #1a1a3e' }}>
              {balance.protein + balance.fat + balance.carbs > 0 ? (
                <>
                  <div className="h-full" style={{ width: `${balance.protein}%`, background: '#00ff41', boxShadow: '0 0 6px #00ff4180' }} />
                  <div className="h-full" style={{ width: `${balance.fat}%`,     background: '#ff00ff', boxShadow: '0 0 6px #ff00ff80' }} />
                  <div className="h-full" style={{ width: `${balance.carbs}%`,   background: '#00e5ff', boxShadow: '0 0 6px #00e5ff80' }} />
                </>
              ) : (
                <div className="h-full w-full" style={{ background: '#1a1a3e' }} />
              )}
            </div>
            <div className="space-y-2.5">
              {[
                { label: 'PROTEIN', pct: balance.protein, color: '#00ff41' },
                { label: 'FAT',     pct: balance.fat,     color: '#ff00ff' },
                { label: 'CARBS',   pct: balance.carbs,   color: '#00e5ff' },
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
              <div className="text-neon-yellow font-bold">{Math.round(energyPerDay)}<span className="text-muted-foreground font-normal text-xs"> kcal</span></div>
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
                const cal   = meals[mealType]?.calories ?? 0;
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
              <div className="text-neon-yellow font-bold">{Math.round(total.calories).toLocaleString()}<span className="text-muted-foreground font-normal text-xs"> kcal</span></div>
            </div>
          </motion.div>

        </div>
      </div>
    </div>
  );
}
