// 文部科学省の Excel から、composition_foods に入れる SQL を書き出す。
//
// 使い方:
//   bun scripts/composition/build-sql.ts <Excel を置いたフォルダ> > composition.sql
//   フォルダに Excel が無ければ manifest.json の URL から落とす。
//
// 新しい依存は足さない。xlsx は zip の中の XML なので、unzip -p で取り出して読む。
// 手順は runbooks/composition_import.md にある。
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { COMPOSITION_NUTRIENTS, compositionNutrients, compositionSearchText } from '../../src/lib/composition';
import manifest from './manifest.json';

/** 脂肪酸成分表から raw_json に残す列。個々の脂肪酸は入れない */
const FATTY_ACID_SUMMARY = ['FACID', 'FASAT', 'FAMS', 'FAPU', 'FAPUN3', 'FAPUN6'];

type Row = { foodNumber: string; group: string; name: string; remarks: string; cells: Record<string, string> };

function unzip(path: string, entry: string): string {
  const result = Bun.spawnSync(['unzip', '-p', path, entry]);
  if (result.exitCode !== 0) throw new Error(`${path} から ${entry} を取り出せない`);
  return result.stdout.toString();
}

function decode(xml: string): string {
  return xml
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/g, '&');
}

/** 共有文字列。ふりがなの rPh は捨てる。残すと「食品群ショクヒングン」のように混ざる */
function sharedStrings(path: string): string[] {
  const xml = unzip(path, 'xl/sharedStrings.xml');
  return [...xml.matchAll(/<si>([\s\S]*?)<\/si>/g)].map(([, si]) =>
    decode([...si.replace(/<rPh[\s\S]*?<\/rPh>/g, '').matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((m) => m[1]).join('')));
}

function columnIndex(ref: string): number {
  let n = 0;
  for (const ch of ref.replace(/\d+$/, '')) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

/** 最初のシート「表全体」を、行ごとのセルの配列にする */
function sheetRows(path: string): string[][] {
  const strings = sharedStrings(path);
  const xml = unzip(path, 'xl/worksheets/sheet1.xml');
  const rows: string[][] = [];
  for (const [, rowXml] of xml.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells: string[] = [];
    for (const [, attrs, inner] of rowXml.matchAll(/<c ([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const ref = /r="([A-Z]+\d+)"/.exec(attrs)?.[1];
      if (!ref) continue;
      const type = /t="([^"]+)"/.exec(attrs)?.[1];
      const v = /<v>([\s\S]*?)<\/v>/.exec(inner ?? '')?.[1];
      let value = '';
      if (type === 's' && v !== undefined) value = strings[Number(v)];
      else if (type === 'inlineStr') value = decode([...(inner ?? '').matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((m) => m[1]).join(''));
      else if (v !== undefined) value = decode(v);
      cells[columnIndex(ref)] = value;
    }
    rows.push(Array.from(cells, (c) => c ?? ''));
  }
  return rows;
}

/** 成分識別子の行から列ごとの Tagname を、5桁の食品番号を持つ行から食品を読む */
function readTable(path: string): Row[] {
  const rows = sheetRows(path);
  const tagRow = rows.find((r) => (r[3] ?? '').startsWith('成分識別子'));
  if (!tagRow) throw new Error(`${path} に成分識別子の行が無い`);
  const tags = tagRow.map((t) => t.trim());
  const remarksIndex = rows.slice(0, 12).map((r) => r.findIndex((c) => c.replace(/\s/g, '').startsWith('備考'))).find((i) => i >= 0) ?? -1;
  return rows
    .filter((r) => /^\d{5}$/.test(r[1] ?? ''))
    .map((r) => {
      const cells: Record<string, string> = {};
      tags.forEach((tag, i) => {
        if (i > 3 && tag !== '' && i !== remarksIndex) cells[tag] = (r[i] ?? '').trim();
      });
      return {
        foodNumber: r[1], group: r[0], name: r[3].replace(/\s+/g, ' ').replace(/　+/g, '　').trim(),
        remarks: remarksIndex >= 0 ? (r[remarksIndex] ?? '') : '', cells,
      };
    });
}

async function source(dir: string, key: 'main' | 'fattyAcid'): Promise<string> {
  const file = manifest.files[key];
  const path = join(dir, file.url.split('/').pop()!);
  if (!existsSync(path)) {
    mkdirSync(dir, { recursive: true });
    const res = await fetch(file.url);
    if (!res.ok) throw new Error(`${file.url} を落とせない: ${res.status}`);
    writeFileSync(path, new Uint8Array(await res.arrayBuffer()));
  }
  const hash = createHash('sha256').update(readFileSync(path)).digest('hex');
  if (hash !== file.sha256) {
    throw new Error(`${path} のハッシュが manifest と違う。文部科学省が差し替えたなら manifest を直す: ${hash}`);
  }
  return path;
}

function sqlString(s: string): string {
  return `'${s.replaceAll("'", "''")}'`;
}

function sqlNumber(v: number | null): string {
  return v === null ? 'NULL' : String(v);
}

const dir = process.argv[2];
if (!dir) {
  console.error('使い方: bun scripts/composition/build-sql.ts <Excel を置いたフォルダ> > composition.sql');
  process.exit(1);
}

const main = readTable(await source(dir, 'main'));
const fattyAcids = new Map(readTable(await source(dir, 'fattyAcid')).map((r) => [r.foodNumber, r.cells]));

const columns = ['food_number', 'food_group', 'name', 'search_text', 'edition', ...COMPOSITION_NUTRIENTS.map((n) => n.column), 'raw_json'];
const lines: string[] = [];
let withFattyAcid = 0;
for (const row of main) {
  const fa = fattyAcids.get(row.foodNumber) ?? {};
  if (fattyAcids.has(row.foodNumber)) withFattyAcid += 1;
  const faSummary = Object.fromEntries(FATTY_ACID_SUMMARY.filter((t) => t in fa).map((t) => [t, fa[t]]));
  // 本表と脂肪酸成分表の両方にある列は本表の値を使う。脂肪酸の列は本表に無いので、成分表の table で分けなくてよい
  const cells = { ...faSummary, ...row.cells };
  const values = compositionNutrients(cells);
  lines.push(
    `INSERT OR REPLACE INTO composition_foods (${columns.join(', ')}) VALUES (` +
      [
        sqlString(row.foodNumber), sqlString(row.group), sqlString(row.name),
        sqlString(compositionSearchText(row.name, row.remarks)), sqlString(manifest.edition),
        ...COMPOSITION_NUTRIENTS.map((n) => sqlNumber(values[n.column])),
        sqlString(JSON.stringify(cells)),
      ].join(', ') + ');',
  );
}

process.stdout.write(lines.join('\n') + '\n');
console.error(`${manifest.title} ${manifest.edition}: ${main.length}食品、うち脂肪酸成分表の値があるもの ${withFattyAcid}`);
for (const n of COMPOSITION_NUTRIENTS) {
  const known = main.filter((r) => compositionNutrients({ ...(fattyAcids.get(r.foodNumber) ?? {}), ...r.cells })[n.column] !== null).length;
  console.error(`  ${n.id}: 値あり ${known}`);
}
