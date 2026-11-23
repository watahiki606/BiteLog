// shared/nutrients.json から iOS 用のファイルを書き出す。
// Xcode のプロジェクトは BiteLog フォルダの外を読めないので、JSON を直接読ませずに生成する。
//
// 使い方: bun run generate:nutrients
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const root = join(import.meta.dir, '..');

const GROUPS = ['energy', 'macro', 'lipid', 'carbohydrate', 'vitamin', 'mineral'];
const LABELS = ['mandatory', 'recommended', 'optional'];
const UNITS = ['kcal', 'g', 'mg', 'µg'];
const LANGUAGES = ['ja', 'en'];
const COMPOSITION_TABLES = ['main', 'fattyAcid'];

type Nutrient = {
  id: string;
  column: string;
  unit: string;
  fractionDigits: number;
  group: string;
  core: boolean;
  /** 成分表から補うだけの詳しい栄養素。入力欄と1日の合計に出さない */
  detail: boolean;
  label: string;
  names: Record<string, string>;
  shortNames: Record<string, string>;
  /** 日本食品標準成分表のどの列から値を取るか。minus があれば、その列を引く */
  composition?: { table: string; tag: string; minus?: string };
};

function validate(nutrients: Nutrient[]): void {
  const errors: string[] = [];
  const seen = new Set<string>();
  for (const [i, n] of nutrients.entries()) {
    const at = `${i}番目 (${n.id})`;
    if (!/^[a-z][A-Za-z0-9]*$/.test(n.id)) errors.push(`${at}: id は小文字で始まる英数字にする`);
    if (!/^[a-z][a-z0-9_]*$/.test(n.column)) errors.push(`${at}: column は小文字とアンダースコアにする`);
    if (seen.has(n.id) || seen.has(`column:${n.column}`)) errors.push(`${at}: id か column が重なっている`);
    seen.add(n.id);
    seen.add(`column:${n.column}`);
    if (!UNITS.includes(n.unit)) errors.push(`${at}: unit は ${UNITS.join(', ')} のどれか`);
    if (!Number.isInteger(n.fractionDigits) || n.fractionDigits < 0) errors.push(`${at}: fractionDigits は 0 以上の整数`);
    if (!GROUPS.includes(n.group)) errors.push(`${at}: group は ${GROUPS.join(', ')} のどれか`);
    if (typeof n.core !== 'boolean') errors.push(`${at}: core は true か false`);
    if (typeof n.detail !== 'boolean') errors.push(`${at}: detail は true か false`);
    if (n.core && n.detail) errors.push(`${at}: core と detail は両方 true にできない`);
    if (!LABELS.includes(n.label)) errors.push(`${at}: label は ${LABELS.join(', ')} のどれか`);
    if (n.composition !== undefined) {
      const c = n.composition;
      if (!COMPOSITION_TABLES.includes(c.table)) errors.push(`${at}: composition.table は ${COMPOSITION_TABLES.join(', ')} のどれか`);
      if (typeof c.tag !== 'string' || c.tag === '') errors.push(`${at}: composition.tag が無い`);
      if (c.minus !== undefined && (typeof c.minus !== 'string' || c.minus === '')) errors.push(`${at}: composition.minus が空`);
    }
    for (const lang of LANGUAGES) {
      if (!n.names?.[lang]) errors.push(`${at}: names.${lang} が無い`);
      if (!n.shortNames?.[lang]) errors.push(`${at}: shortNames.${lang} が無い`);
    }
  }
  if (errors.length > 0) {
    console.error(errors.join('\n'));
    process.exit(1);
  }
}

/// Swift の文字列リテラルと .strings の両方で、そのまま書けるようにする
function quote(s: string): string {
  return `"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"`;
}

const HEADER = '生成したファイル。shared/nutrients.json を直して bun run generate:nutrients で作り直す';

function swift(nutrients: Nutrient[]): string {
  const cases = nutrients.map((n) => `  case ${n.id}`).join('\n');
  const definitions = nutrients
    .map(
      (n) => `    case .${n.id}:
      return NutrientDefinition(
        id: .${n.id}, column: ${quote(n.column)}, unit: ${quote(n.unit)}, fractionDigits: ${n.fractionDigits},
        group: .${n.group}, core: ${n.core}, detail: ${n.detail}, label: .${n.label})`,
    )
    .join('\n');
  return `// ${HEADER}

/// 栄養素の識別子。rawValue は API の JSON とスナップショットのキー
enum NutrientID: String, CaseIterable, Codable, Sendable {
${cases}
}

extension NutrientID {
  var definition: NutrientDefinition {
    switch self {
${definitions}
    }
  }
}
`;
}

function strings(nutrients: Nutrient[], lang: string): string {
  const lines = nutrients.flatMap((n) => [
    `${quote(`${n.id}.name`)} = ${quote(n.names[lang])};`,
    `${quote(`${n.id}.shortName`)} = ${quote(n.shortNames[lang])};`,
  ]);
  return `/* ${HEADER} */\n\n${lines.join('\n')}\n`;
}

function write(path: string, content: string): void {
  const full = join(root, path);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, content);
  console.log(`wrote ${path}`);
}

const nutrients: Nutrient[] = JSON.parse(readFileSync(join(root, 'shared/nutrients.json'), 'utf8'));
validate(nutrients);
write('BiteLog/Generated/NutrientDefinitions.swift', swift(nutrients));
for (const lang of LANGUAGES) {
  write(`BiteLog/Resources/${lang}.lproj/Nutrients.strings`, strings(nutrients, lang));
}
