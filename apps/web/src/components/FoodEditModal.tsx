import { useState } from 'react';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';
import type { FoodMaster } from '@/hooks/useFoodMasters';
import { useFoodDetail, type FoodComponent } from '@/hooks/useComposition';
import { Field, Modal, fieldClass as fc } from '@/components/Modal';
import ComponentsEditor from '@/components/ComponentsEditor';
import {
  LABEL_NUTRIENTS, NUTRIENTS, addedInputsFrom, addedInputsToBody, carbohydrateOf, changedAddedBody, defaultComponentGrams,
  emptyAddedInputs, inputStep, pickNutrients, withCarbohydrate, withFiber, zeroNutrients,
  type AddedInputs, type AddedNutrientId, type CoreNutrientId,
} from '@/lib/nutrients';

const emptyForm = {
  brandName: '',
  productName: '',
  ...zeroNutrients(),
  portionSize: 100,
  portionUnit: 'g',
};

type FormData = typeof emptyForm;

// 入力欄に出す名前。web は独自の英語の言葉で並べているので、定義の表示名ではなくこちらを使う
const FIELD_LABELS: Record<CoreNutrientId, string> = {
  calories: 'Calories',
  protein: 'Protein',
  fat: 'Fat',
  // 入力欄はラベルと同じ並びの炭水化物とうち食物繊維。保存は糖質と食物繊維のまま
  netCarbs: 'Carbs',
  dietaryFiber: 'of which Fiber',
};

const NUTRIENT_FIELDS = NUTRIENTS.filter((n) => n.core).map((n) => ({
  id: n.id as CoreNutrientId,
  label: `${FIELD_LABELS[n.id as CoreNutrientId]} (${n.unit})`,
  // 整数だけの栄養素は刻みを付けない。ブラウザの既定の 1 になる
  step: n.fractionDigits > 0 ? String(inputStep(n)) : undefined,
}));

// あとから足した栄養素。空欄は「分からない」として保存する。
// 詳しい栄養素は食品表示に載ることがまれなので欄を出さず、成分表とのひも付けから補う
const ADDED_FIELDS = LABEL_NUTRIENTS.map((n) => ({
  id: n.id as AddedNutrientId,
  name: n.names.en,
  unit: n.unit,
  step: String(inputStep(n)),
}));

const COMPOSITION = 'composition_table';

/** 食品を作る、直す。成分表とのひも付けもここで行う */
export default function FoodEditModal({ editing, onClose, onSaved, onToast }: {
  /** 直す食品。null なら作る */
  editing: (FoodMaster & { nutrientSource?: string | null }) | null;
  onClose: () => void;
  onSaved: () => void;
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}) {
  const [form, setForm] = useState<FormData>(() => editing
    ? { brandName: editing.brandName, productName: editing.productName, ...pickNutrients(editing), portionSize: editing.portionSize, portionUnit: editing.portionUnit }
    : emptyForm);
  const initialAdded = editing ? addedInputsFrom(editing) : emptyAddedInputs();
  const [addedForm, setAddedForm] = useState<AddedInputs>(initialAdded);
  /** 手で触ったひも付け。null のうちは、読んだ詳細のひも付けをそのまま出す */
  const [editedComponents, setEditedComponents] = useState<FoodComponent[] | null>(null);
  const initialAllFromTable = editing?.nutrientSource === COMPOSITION;
  const [allFromTable, setAllFromTable] = useState(initialAllFromTable);
  const { data: detail } = useFoodDetail(editing?.id ?? null);

  // ひも付けは一覧に付かないので、詳細から読む
  const components = editedComponents ?? detail?.components ?? [];
  const componentsTouched = editedComponents !== null;

  function setField<K extends keyof FormData>(key: K, val: FormData[K]) {
    setForm((f) => ({ ...f, [key]: val }));
  }

  // 糖質の欄には炭水化物を出す。食物繊維を直しても炭水化物は保ち、糖質を計算し直す
  function fieldValue(id: CoreNutrientId): number {
    return id === 'netCarbs' ? carbohydrateOf(form) : form[id];
  }

  function setNutrient(id: CoreNutrientId, value: number) {
    if (id === 'netCarbs') setForm((f) => withCarbohydrate(f, value));
    else if (id === 'dietaryFiber') setForm((f) => withFiber(f, value));
    else setField(id, value);
  }

  function changeComponents(next: FoodComponent[]) {
    setEditedComponents(next);
  }

  async function handleSave() {
    if (form.netCarbs < 0) {
      onToast({ message: '食物繊維は炭水化物より多くできません', type: 'error' });
      return;
    }
    if (components.some((c) => !(c.grams > 0))) {
      onToast({ message: '成分表の食材の重さを入れてください', type: 'error' });
      return;
    }
    if (allFromTable && components.length === 0) {
      onToast({ message: '成分表から取るには、成分表の食材を選んでください', type: 'error' });
      return;
    }
    const componentsBody = components.map((c) => ({ foodNumber: c.foodNumber, grams: c.grams }));
    try {
      const client = createClient();
      if (editing) {
        const body: Record<string, unknown> = { ...form, ...changedAddedBody(initialAdded, addedForm) };
        if (componentsTouched || allFromTable !== initialAllFromTable) body.components = componentsBody;
        if (allFromTable !== initialAllFromTable) body.nutrientSource = allFromTable ? COMPOSITION : 'manual';
        // PUT は Hono RPC がバリデータなしで json ボディを型推論できないため、
        // param だけ渡し、ボディは init で送る。
        // init.headers は渡さない: Hono クライアントが {headers, ...opt.init} の順で
        // 展開するため、init.headers を渡すと Authorization ごと上書きされ 401 になる。
        // サーバは c.req.json() で読み、Content-Type を見ないため body のみで十分。
        const res = await client.api['food-masters'][':id'].$put(
          { param: { id: editing.id } },
          { init: { body: JSON.stringify(body) } }
        );
        if (res.status === 403) {
          onToast({ message: '他のユーザーが作成した食品は編集できません', type: 'error' });
          return;
        }
        if (!res.ok) throw new Error();
      } else {
        const id = crypto.randomUUID();
        const uniqueKey = `${form.brandName}|${form.productName}|${form.portionUnit}`;
        const res = await client.api['food-masters'].$post({
          // reject を付けないと、同じ名前と単位の食品があるとき既存の食品が返り、追加できたように見える
          json: {
            ...form, ...addedInputsToBody(addedForm, false),
            nutrientSource: allFromTable ? COMPOSITION : 'manual',
            ...(components.length > 0 ? { components: componentsBody } : {}),
            id, uniqueKey, onConflict: 'reject',
          },
        });
        if (res.status === 409) {
          onToast({ message: '同じブランド名・商品名・単位の食品が登録済みです', type: 'error' });
          return;
        }
        if (!res.ok) throw new Error();
      }
      onToast({ message: editing ? '更新しました' : '追加しました', type: 'success' });
      onSaved();
    } catch {
      onToast({ message: '保存に失敗しました', type: 'error' });
    }
  }

  const sources = detail?.nutrientSources ?? {};

  return (
    <Modal title={editing ? 'EDIT FOOD' : 'ADD FOOD'} onClose={onClose} onSave={handleSave} wide>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Product Name" colSpan={2}><input type="text" value={form.productName} onChange={(e) => setField('productName', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        <Field label="Brand Name" colSpan={2}><input type="text" value={form.brandName} onChange={(e) => setField('brandName', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        <Field label="Portion Size"><input type="number" step="0.1" value={form.portionSize} onChange={(e) => setField('portionSize', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        <Field label="Portion Unit"><input type="text" value={form.portionUnit} onChange={(e) => setField('portionUnit', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>

        <Field label="Composition table (per portion)" colSpan={2}>
          <ComponentsEditor components={components} onChange={changeComponents}
            defaultGrams={defaultComponentGrams(form.portionSize, form.portionUnit)}
            productName={form.productName} />
          <label className="flex items-center gap-2 mt-2 text-xs text-muted-foreground">
            <input type="checkbox" checked={allFromTable} onChange={(e) => setAllFromTable(e.target.checked)} />
            ALL VALUES FROM THE TABLE. Otherwise only unknown nutrients are filled
          </label>
        </Field>

        {NUTRIENT_FIELDS.map((f) => (
          <Field key={f.id} label={f.label}><input type="number" step={f.step} value={fieldValue(f.id)} disabled={allFromTable} onChange={(e) => setNutrient(f.id, Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        ))}
        <Field label="Net Carbs (g)"><p className="px-3 py-1.5 text-xs text-muted-foreground">{form.netCarbs < 0 ? '—' : form.netCarbs}</p></Field>
        {ADDED_FIELDS.map((f) => (
          // 見出しは大文字にするので、単位だけは元の書き方で出す。µg が MG に見えるため
          <Field key={f.id} label={<>{f.name} <span className="normal-case">({f.unit})</span>{sources[f.id] === COMPOSITION && <span className="text-neon-green"> · TABLE</span>}</>}>
            <input type="number" step={f.step} placeholder="unknown" value={addedForm[f.id]} disabled={allFromTable}
              onChange={(e) => setAddedForm((a) => ({ ...a, [f.id]: e.target.value }))} className={fc} style={{ fontFamily: 'inherit' }} />
          </Field>
        ))}
      </div>
    </Modal>
  );
}
