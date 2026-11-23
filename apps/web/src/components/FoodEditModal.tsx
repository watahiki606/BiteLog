import { useState } from 'react';
import { createClient } from '@/lib/api';
import type { ToastMessage } from '@/components/Toast';
import type { FoodMaster } from '@/hooks/useFoodMasters';
import type { CompositionFood } from '@/hooks/useComposition';
import { Field, Modal, fieldClass as fc } from '@/components/Modal';
import CompositionPicker from '@/components/CompositionPicker';
import {
  ADDED_NUTRIENTS, CORE_NUTRIENT_IDS, LABEL_NUTRIENTS, NUTRIENTS, addedInputsFrom, addedInputsToBody, carbohydrateOf,
  defaultPickGrams, emptyAddedInputs, inputStep, mergePicked, pickNutrients, pickedTexts, withCarbohydrate, withFiber,
  zeroNutrients, type AddedInputs, type AddedNutrientId, type CoreNutrientId, type NutrientDefinition, type PickFieldId,
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

// あとから足した栄養素。空欄は「分からない」として保存する
function addedFields(nutrients: readonly NutrientDefinition[]) {
  return nutrients.map((n) => ({ id: n.id as AddedNutrientId, name: n.names.en, unit: n.unit, step: String(inputStep(n)) }));
}
const ADDED_FIELDS = addedFields(LABEL_NUTRIENTS);
// 詳しい栄養素は食品表示に載ることがまれなので、欄は畳んだ中に出す
const DETAIL_FIELDS = addedFields(ADDED_NUTRIENTS.filter((n) => n.detail));

/** 最初の5項目の欄は数で持つ。0 は空欄とみなし、成分表から選んだ値を入れてよい欄にする */
function coreText(value: number): string {
  return value === 0 ? '' : String(value);
}

/** 食品を作る、直す。成分表から選んで値を欄に入れることもできる */
export default function FoodEditModal({ editing, onClose, onSaved, onToast }: {
  /** 直す食品。null なら作る */
  editing: FoodMaster | null;
  onClose: () => void;
  onSaved: () => void;
  onToast: (msg: Omit<ToastMessage, 'id'>) => void;
}) {
  const [form, setForm] = useState<FormData>(() => editing
    ? { brandName: editing.brandName, productName: editing.productName, ...pickNutrients(editing), portionSize: editing.portionSize, portionUnit: editing.portionUnit }
    : emptyForm);
  const [addedForm, setAddedForm] = useState<AddedInputs>(() => (editing ? addedInputsFrom(editing) : emptyAddedInputs()));
  const [picked, setPicked] = useState<{ name: string; grams: number } | null>(null);
  /** 最後に成分表から入れた欄の文字。選び直したとき、手で直していない欄だけを入れ替える */
  const [pickedFields, setPickedFields] = useState<Partial<Record<PickFieldId, string>>>({});
  const [showsDetail, setShowsDetail] = useState(false);

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

  /** 成分表から選んだ食品の、重さの分の値を欄に入れる */
  function fill(food: CompositionFood, grams: number) {
    const texts = pickedTexts(food.per100g, grams);
    const current: Partial<Record<PickFieldId, string>> = { ...addedForm };
    for (const id of CORE_NUTRIENT_IDS) current[id] = coreText(form[id]);
    const changes = mergePicked(current, texts, pickedFields);
    setForm((f) => {
      const next = { ...f };
      for (const id of CORE_NUTRIENT_IDS) {
        const text = changes[id];
        if (text !== undefined) next[id] = Number(text || 0);
      }
      return next;
    });
    setAddedForm((a) => {
      const next = { ...a };
      for (const [id, text] of Object.entries(changes)) {
        if (id in next) next[id as AddedNutrientId] = text ?? '';
      }
      return next;
    });
    setPickedFields(texts);
    setPicked({ name: food.name, grams });
    // 詳しい栄養素にも値が入る。畳んだままだと入ったことが見えない
    if (DETAIL_FIELDS.some((f) => texts[f.id] !== undefined)) setShowsDetail(true);
  }

  async function handleSave() {
    if (form.netCarbs < 0) {
      onToast({ message: '食物繊維は炭水化物より多くできません', type: 'error' });
      return;
    }
    try {
      const client = createClient();
      if (editing) {
        // 空欄は null で送り、分からないに戻す
        const body = { ...form, ...addedInputsToBody(addedForm, true) };
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
            nutrientSource: 'manual',
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

  function addedField(f: (typeof ADDED_FIELDS)[number]) {
    return (
      // 見出しは大文字にするので、単位だけは元の書き方で出す。µg が MG に見えるため
      <Field key={f.id} label={<>{f.name} <span className="normal-case">({f.unit})</span></>}>
        <input type="number" step={f.step} placeholder="unknown" value={addedForm[f.id]}
          onChange={(e) => setAddedForm((a) => ({ ...a, [f.id]: e.target.value }))} className={fc} style={{ fontFamily: 'inherit' }} />
      </Field>
    );
  }

  return (
    <Modal title={editing ? 'EDIT FOOD' : 'ADD FOOD'} onClose={onClose} onSave={handleSave} wide>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Product Name" colSpan={2}><input type="text" value={form.productName} onChange={(e) => setField('productName', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        <Field label="Brand Name" colSpan={2}><input type="text" value={form.brandName} onChange={(e) => setField('brandName', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        <Field label="Portion Size"><input type="number" step="0.1" value={form.portionSize} onChange={(e) => setField('portionSize', Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        <Field label="Portion Unit"><input type="text" value={form.portionUnit} onChange={(e) => setField('portionUnit', e.target.value)} className={fc} style={{ fontFamily: 'inherit' }} /></Field>

        <Field label="Pick from composition table (edible grams per portion)" colSpan={2}>
          <CompositionPicker productName={form.productName} defaultGrams={defaultPickGrams(form.portionSize, form.portionUnit)}
            picked={picked} onPick={fill} />
        </Field>

        {NUTRIENT_FIELDS.map((f) => (
          <Field key={f.id} label={f.label}><input type="number" step={f.step} value={fieldValue(f.id)} onChange={(e) => setNutrient(f.id, Number(e.target.value))} className={fc} style={{ fontFamily: 'inherit' }} /></Field>
        ))}
        <Field label="Net Carbs (g)"><p className="px-3 py-1.5 text-xs text-muted-foreground">{form.netCarbs < 0 ? '—' : form.netCarbs}</p></Field>
        {ADDED_FIELDS.map(addedField)}
        <details className="col-span-2" open={showsDetail} onToggle={(e) => setShowsDetail(e.currentTarget.open)}>
          <summary className="cursor-pointer py-2 text-xs tracking-widest text-muted-foreground">DETAILED NUTRIENTS</summary>
          <div className="grid grid-cols-2 gap-3">{DETAIL_FIELDS.map(addedField)}</div>
        </details>
      </div>
    </Modal>
  );
}
