/** 統計ページで使う区切りトグル（小ボタン群）。 */
export function Segmented<T extends string>({ options, value, onChange, colorFor }: {
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
