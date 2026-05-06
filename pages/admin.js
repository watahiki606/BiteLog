'use strict';

const API_URL = (localStorage.getItem('bl_api_url') || 'https://bitelog-workers.v10acdict.workers.dev').replace(/\/$/, '');
let API_TOKEN = '';
let currentTab = 'food';
let confirmAction = null;

// --- 設定 ---
function loadSetup() {
  API_TOKEN = sessionStorage.getItem('bl_api_token') || '';
  if (API_TOKEN) {
    document.getElementById('setup-overlay').style.display = 'none';
    showTab('food');
  }
}

function saveSetup() {
  API_TOKEN = document.getElementById('setup-token').value.trim();
  if (!API_TOKEN) { toast('パスワードを入力してください'); return; }
  sessionStorage.setItem('bl_api_token', API_TOKEN);
  document.getElementById('setup-overlay').style.display = 'none';
  showTab('food');
}

function openSetup() {
  document.getElementById('setup-token').value = '';
  document.getElementById('setup-overlay').style.display = 'flex';
}

// --- API ---
async function api(path, method = 'GET', body = null) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${API_TOKEN}` },
  };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(API_URL + path, opts);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}

// --- タブ切り替え ---
function showTab(tab) {
  currentTab = tab;
  document.querySelectorAll('#sidebar nav a').forEach(a => a.classList.remove('active'));
  document.getElementById('nav-' + tab).classList.add('active');
  const titles = { food: '食品マスタ', log: '食事ログ', goals: '栄養目標' };
  document.getElementById('page-title').textContent = titles[tab];
  if (tab === 'food') renderFood();
  else if (tab === 'log') renderLog();
  else if (tab === 'goals') renderGoals();
}

// --- Toast ---
function toast(msg, duration = 2500) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), duration);
}

// ================== 食品マスタ ==================
let foodPage = 0;
let foodQuery = '';
let foodTotal = 0;
const FOOD_LIMIT = 30;
const foodCache = new Map();

async function renderFood() {
  const topbarActions = document.getElementById('topbar-actions');
  topbarActions.textContent = '';
  const addBtn = document.createElement('button');
  addBtn.className = 'btn btn-primary';
  addBtn.textContent = '+ 追加';
  addBtn.addEventListener('click', () => openFoodModal());
  topbarActions.appendChild(addBtn);

  const content = document.getElementById('content');
  content.innerHTML = `
    <div class="toolbar">
      <span id="food-count" style="color:#6e6e73; font-size:13px;"></span>
    </div>
    <div class="card">
      <div class="table-wrap">
        <table>
          <thead><tr>
            <th>ブランド</th><th>商品名</th>
            <th>Cal</th><th>P(g)</th><th>F(g)</th><th>糖質(g)</th><th>食繊(g)</th>
            <th>ポーション</th><th>使用回数</th><th>登録者</th><th></th>
          </tr></thead>
          <tbody id="food-tbody"><tr><td colspan="11" class="loading">読み込み中...</td></tr></tbody>
        </table>
      </div>
      <div class="pagination" id="food-pagination"></div>
    </div>`;

  const toolbar = content.querySelector('.toolbar');
  const searchInput = document.createElement('input');
  searchInput.type = 'text';
  searchInput.className = 'search';
  searchInput.id = 'food-search';
  searchInput.placeholder = '商品名・ブランド名で検索...';
  searchInput.value = foodQuery;
  searchInput.addEventListener('input', () => onFoodSearch(searchInput.value));
  toolbar.insertBefore(searchInput, toolbar.firstChild);

  await loadFoodPage();
}

let foodSearchTimer;
function onFoodSearch(val) {
  clearTimeout(foodSearchTimer);
  foodSearchTimer = setTimeout(() => { foodQuery = val; foodPage = 0; loadFoodPage(); }, 300);
}

async function loadFoodPage() {
  try {
    const data = await api(`/api/food-masters?q=${encodeURIComponent(foodQuery)}&limit=${FOOD_LIMIT}&offset=${foodPage * FOOD_LIMIT}`);
    foodTotal = data.total;
    document.getElementById('food-count').textContent = `${foodTotal} 件`;

    const tbody = document.getElementById('food-tbody');
    tbody.textContent = '';

    if (!data.items.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 11;
      const empty = document.createElement('div');
      empty.className = 'empty';
      const p = document.createElement('p');
      p.textContent = 'データがありません';
      empty.appendChild(p);
      td.appendChild(empty);
      tr.appendChild(td);
      tbody.appendChild(tr);
    } else {
      foodCache.clear();
      data.items.forEach(f => {
        foodCache.set(f.id, f);

        const tr = document.createElement('tr');

        const tdBrand = document.createElement('td');
        tdBrand.textContent = f.brandName || '';
        tr.appendChild(tdBrand);

        const tdName = document.createElement('td');
        const strong = document.createElement('strong');
        strong.textContent = f.productName || '';
        tdName.appendChild(strong);
        tr.appendChild(tdName);

        [f.calories, f.protein, f.fat, f.netCarbs, f.dietaryFiber].forEach(val => {
          const td = document.createElement('td');
          td.textContent = val ?? '';
          tr.appendChild(td);
        });

        const tdPortion = document.createElement('td');
        tdPortion.textContent = `${f.portionSize || ''}${f.portionUnit || ''}`;
        tr.appendChild(tdPortion);

        const tdUsage = document.createElement('td');
        const badge = document.createElement('span');
        badge.className = 'badge badge-blue';
        badge.textContent = f.usageCount ?? '';
        tdUsage.appendChild(badge);
        tr.appendChild(tdUsage);

        const tdCreatedBy = document.createElement('td');
        tdCreatedBy.style.fontSize = '0.75em';
        tdCreatedBy.style.color = '#888';
        tdCreatedBy.textContent = f.createdBy || '—';
        tr.appendChild(tdCreatedBy);

        const tdActions = document.createElement('td');
        tdActions.style.whiteSpace = 'nowrap';

        const editBtn = document.createElement('button');
        editBtn.className = 'btn btn-secondary btn-sm';
        editBtn.textContent = '編集';
        editBtn.addEventListener('click', () => {
          const food = foodCache.get(f.id);
          if (food) openFoodModal(food);
        });
        tdActions.appendChild(editBtn);

        tdActions.appendChild(document.createTextNode(' '));

        const delBtn = document.createElement('button');
        delBtn.className = 'btn btn-danger btn-sm';
        delBtn.textContent = '削除';
        delBtn.addEventListener('click', () => confirmDeleteFood(f.id, f.productName));
        tdActions.appendChild(delBtn);

        tr.appendChild(tdActions);
        tbody.appendChild(tr);
      });
    }

    const totalPages = Math.ceil(foodTotal / FOOD_LIMIT);
    const paginationEl = document.getElementById('food-pagination');
    paginationEl.textContent = '';
    if (totalPages > 1) {
      const prevBtn = document.createElement('button');
      prevBtn.className = 'btn btn-secondary btn-sm';
      prevBtn.textContent = '←';
      prevBtn.disabled = foodPage === 0;
      prevBtn.addEventListener('click', () => { foodPage--; loadFoodPage(); });
      paginationEl.appendChild(prevBtn);

      const pageSpan = document.createElement('span');
      pageSpan.textContent = `${foodPage + 1} / ${totalPages}`;
      paginationEl.appendChild(pageSpan);

      const nextBtn = document.createElement('button');
      nextBtn.className = 'btn btn-secondary btn-sm';
      nextBtn.textContent = '→';
      nextBtn.disabled = foodPage >= totalPages - 1;
      nextBtn.addEventListener('click', () => { foodPage++; loadFoodPage(); });
      paginationEl.appendChild(nextBtn);
    }
  } catch (e) {
    const tbody = document.getElementById('food-tbody');
    tbody.textContent = '';
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 10;
    td.style.color = 'red';
    td.style.padding = '16px';
    td.textContent = e.message;
    tr.appendChild(td);
    tbody.appendChild(tr);
  }
}

function openFoodModal(food = null) {
  document.getElementById('food-modal-title').textContent = food ? '食品マスタを編集' : '食品マスタを追加';
  document.getElementById('food-id').value = food?.id || '';
  document.getElementById('food-brand').value = food?.brandName || '';
  document.getElementById('food-name').value = food?.productName || '';
  document.getElementById('food-cal').value = food?.calories ?? '';
  document.getElementById('food-protein').value = food?.protein ?? '';
  document.getElementById('food-fat').value = food?.fat ?? '';
  document.getElementById('food-netcarbs').value = food?.netCarbs ?? '';
  document.getElementById('food-fiber').value = food?.dietaryFiber ?? '';
  document.getElementById('food-portion').value = food?.portionSize ?? '';
  document.getElementById('food-unit').value = food?.portionUnit || 'g';
  document.getElementById('food-modal').classList.add('open');
}

function closeFoodModal() { document.getElementById('food-modal').classList.remove('open'); }

async function saveFood() {
  const id = document.getElementById('food-id').value;
  const brandName = document.getElementById('food-brand').value.trim();
  const productName = document.getElementById('food-name').value.trim();
  const portionUnit = document.getElementById('food-unit').value.trim() || 'g';
  if (!productName) { toast('商品名は必須です'); return; }

  const body = {
    id: id || crypto.randomUUID(),
    brandName, productName,
    calories: parseFloat(document.getElementById('food-cal').value) || 0,
    protein: parseFloat(document.getElementById('food-protein').value) || 0,
    fat: parseFloat(document.getElementById('food-fat').value) || 0,
    netCarbs: parseFloat(document.getElementById('food-netcarbs').value) || 0,
    dietaryFiber: parseFloat(document.getElementById('food-fiber').value) || 0,
    portionSize: parseFloat(document.getElementById('food-portion').value) || 100,
    portionUnit,
    uniqueKey: `${brandName}|${productName}|${portionUnit}`,
  };

  try {
    if (id) await api(`/api/food-masters/${id}`, 'PUT', body);
    else await api('/api/food-masters', 'POST', body);
    closeFoodModal();
    toast(id ? '更新しました' : '追加しました');
    loadFoodPage();
  } catch (e) { toast('エラー: ' + e.message); }
}

function confirmDeleteFood(id, name) {
  document.getElementById('confirm-msg').textContent = `「${name}」を削除しますか？関連する食事ログにはスナップショットが保存されます。`;
  confirmAction = () => deleteFood(id);
  document.getElementById('confirm-modal').classList.add('open');
}

async function deleteFood(id) {
  try {
    await api(`/api/food-masters/${id}`, 'DELETE');
    closeConfirm();
    toast('削除しました');
    loadFoodPage();
  } catch (e) { toast('エラー: ' + e.message); }
}

// ================== 食事ログ ==================
let logDate = new Date().toISOString().slice(0, 10);

async function renderLog() {
  document.getElementById('topbar-actions').textContent = '';
  const content = document.getElementById('content');
  content.innerHTML = `
    <div class="toolbar"></div>
    <div id="log-stats" class="stats"></div>
    <div class="card">
      <div class="table-wrap">
        <table>
          <thead><tr>
            <th>時刻</th><th>食事タイプ</th><th>食品</th>
            <th>サービング</th><th>Cal</th><th>P</th><th>F</th><th>糖質</th><th></th>
          </tr></thead>
          <tbody id="log-tbody"><tr><td colspan="9" class="loading">読み込み中...</td></tr></tbody>
        </table>
      </div>
    </div>`;

  const toolbar = content.querySelector('.toolbar');
  const dateInput = document.createElement('input');
  dateInput.type = 'date';
  dateInput.id = 'log-date';
  dateInput.value = logDate;
  dateInput.addEventListener('change', () => { logDate = dateInput.value; loadLog(); });
  toolbar.appendChild(dateInput);

  await loadLog();
}

const mealTypeLabels = { Breakfast: '朝食', Lunch: '昼食', Dinner: '夕食', Snack: '間食', Other: 'その他' };
const mealBadgeColors = { Breakfast: 'badge-blue', Lunch: 'badge-green', Dinner: 'badge-orange', Snack: 'badge-red', Other: 'badge-blue' };
const ALLOWED_MEAL_TYPES = new Set(Object.keys(mealTypeLabels));

async function loadLog() {
  try {
    const data = await api(`/api/log-items?logDate=${logDate}`);
    const items = data.items;

    const totals = items.reduce((acc, item) => {
      const fm = item.foodMaster || item.nutritionSnapshot || {};
      const s = item.numberOfServings;
      const ps = (fm.portionSize || 100);
      const ratio = s / ps;
      acc.cal += (fm.calories || 0) * ratio;
      acc.protein += (fm.protein || 0) * ratio;
      acc.fat += (fm.fat || 0) * ratio;
      acc.carbs += ((fm.netCarbs || 0) + (fm.dietaryFiber || 0)) * ratio;
      return acc;
    }, { cal: 0, protein: 0, fat: 0, carbs: 0 });

    const logStats = document.getElementById('log-stats');
    logStats.textContent = '';
    [
      { label: 'カロリー', value: Math.round(totals.cal), unit: ' kcal' },
      { label: 'タンパク質', value: totals.protein.toFixed(1), unit: ' g' },
      { label: '脂質', value: totals.fat.toFixed(1), unit: ' g' },
      { label: '炭水化物', value: totals.carbs.toFixed(1), unit: ' g' },
      { label: '件数', value: items.length, unit: '' },
    ].forEach(({ label, value, unit }) => {
      const card = document.createElement('div');
      card.className = 'stat-card';
      const labelEl = document.createElement('div');
      labelEl.className = 'label';
      labelEl.textContent = label;
      const valueEl = document.createElement('div');
      valueEl.className = 'value';
      valueEl.textContent = value;
      if (unit) {
        const unitSpan = document.createElement('span');
        unitSpan.style.fontSize = '14px';
        unitSpan.style.fontWeight = '400';
        unitSpan.textContent = unit;
        valueEl.appendChild(unitSpan);
      }
      card.appendChild(labelEl);
      card.appendChild(valueEl);
      logStats.appendChild(card);
    });

    const tbody = document.getElementById('log-tbody');
    tbody.textContent = '';

    if (!items.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 9;
      const empty = document.createElement('div');
      empty.className = 'empty';
      const p = document.createElement('p');
      p.textContent = 'この日の食事記録はありません';
      empty.appendChild(p);
      td.appendChild(empty);
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    items.forEach(item => {
      const fm = item.foodMaster || item.nutritionSnapshot || {};
      const s = item.numberOfServings;
      const ps = fm.portionSize || 100;
      const ratio = s / ps;
      const time = item.timestamp
        ? new Date(item.timestamp).toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })
        : '-';

      const tr = document.createElement('tr');

      const tdTime = document.createElement('td');
      tdTime.textContent = time;
      tr.appendChild(tdTime);

      const tdMealType = document.createElement('td');
      const badge = document.createElement('span');
      const safeType = ALLOWED_MEAL_TYPES.has(item.mealType) ? item.mealType : 'Other';
      badge.className = `badge ${mealBadgeColors[safeType]}`;
      badge.textContent = mealTypeLabels[safeType];
      tdMealType.appendChild(badge);
      tr.appendChild(tdMealType);

      const tdFoodName = document.createElement('td');
      if (item.isMasterDeleted) {
        const span = document.createElement('span');
        span.style.color = '#aeaeb2';
        span.textContent = fm.productName || '削除済み';
        tdFoodName.appendChild(span);
      } else {
        tdFoodName.textContent = (fm.brandName ? fm.brandName + ' ' : '') + (fm.productName || '');
      }
      tr.appendChild(tdFoodName);

      const tdServing = document.createElement('td');
      tdServing.textContent = `${s} ${fm.portionUnit || ''}`;
      tr.appendChild(tdServing);

      [
        Math.round((fm.calories || 0) * ratio),
        ((fm.protein || 0) * ratio).toFixed(1),
        ((fm.fat || 0) * ratio).toFixed(1),
        ((fm.netCarbs || 0) * ratio).toFixed(1),
      ].forEach(val => {
        const td = document.createElement('td');
        td.textContent = val;
        tr.appendChild(td);
      });

      const tdDel = document.createElement('td');
      const delBtn = document.createElement('button');
      delBtn.className = 'btn btn-danger btn-sm';
      delBtn.textContent = '削除';
      delBtn.addEventListener('click', () => confirmDeleteLog(item.id));
      tdDel.appendChild(delBtn);
      tr.appendChild(tdDel);

      tbody.appendChild(tr);
    });
  } catch (e) {
    const tbody = document.getElementById('log-tbody');
    tbody.textContent = '';
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 9;
    td.style.color = 'red';
    td.style.padding = '16px';
    td.textContent = e.message;
    tr.appendChild(td);
    tbody.appendChild(tr);
  }
}

function confirmDeleteLog(id) {
  document.getElementById('confirm-msg').textContent = 'この食事記録を削除しますか？';
  confirmAction = () => deleteLog(id);
  document.getElementById('confirm-modal').classList.add('open');
}

async function deleteLog(id) {
  try {
    await api(`/api/log-items/${id}`, 'DELETE');
    closeConfirm();
    toast('削除しました');
    loadLog();
  } catch (e) { toast('エラー: ' + e.message); }
}

// ================== 栄養目標 ==================
async function renderGoals() {
  document.getElementById('topbar-actions').textContent = '';
  const content = document.getElementById('content');
  content.textContent = '';
  const loading = document.createElement('div');
  loading.className = 'loading';
  loading.textContent = '読み込み中...';
  content.appendChild(loading);

  try {
    const g = await api('/api/nutrition-goals');

    content.textContent = '';
    const card = document.createElement('div');
    card.className = 'card';
    card.style.maxWidth = '480px';

    [
      { label: 'タンパク質目標 (g/日)', id: 'g-protein',  val: g.targetProtein },
      { label: '脂質目標 (g/日)',        id: 'g-fat',      val: g.targetFat },
      { label: '糖質目標 (g/日)',        id: 'g-netcarbs', val: g.targetNetCarbs },
      { label: '食物繊維目標 (g/日)',    id: 'g-fiber',    val: g.targetFiber },
    ].forEach(({ label, id, val }) => {
      const row = document.createElement('div');
      row.className = 'form-row';
      const lbl = document.createElement('label');
      lbl.textContent = label;
      const input = document.createElement('input');
      input.type = 'number';
      input.id = id;
      input.min = '0';
      input.step = '1';
      input.value = val;
      input.addEventListener('input', updateTargetCal);
      row.appendChild(lbl);
      row.appendChild(input);
      card.appendChild(row);
    });

    const calInfo = document.createElement('div');
    calInfo.style.cssText = 'margin-top:8px; padding:12px; background:#f5f5f7; border-radius:8px; font-size:13px; color:#6e6e73;';
    calInfo.textContent = '目標カロリー: ';
    const calStrong = document.createElement('strong');
    calStrong.id = 'target-cal';
    calStrong.textContent = calcCal(g);
    calInfo.appendChild(calStrong);
    calInfo.appendChild(document.createTextNode(' kcal'));
    card.appendChild(calInfo);

    const btnWrap = document.createElement('div');
    btnWrap.style.marginTop = '20px';
    const saveBtn = document.createElement('button');
    saveBtn.className = 'btn btn-primary';
    saveBtn.textContent = '保存';
    saveBtn.addEventListener('click', saveGoals);
    btnWrap.appendChild(saveBtn);
    card.appendChild(btnWrap);

    content.appendChild(card);
  } catch (e) {
    content.textContent = '';
    const errDiv = document.createElement('div');
    errDiv.style.cssText = 'color:red;padding:24px';
    errDiv.textContent = e.message;
    content.appendChild(errDiv);
  }
}

function calcCal(g) {
  return Math.round(g.targetProtein * 4 + g.targetFat * 9 + g.targetNetCarbs * 4 + g.targetFiber * 2);
}

function updateTargetCal() {
  const g = {
    targetProtein: parseFloat(document.getElementById('g-protein').value) || 0,
    targetFat: parseFloat(document.getElementById('g-fat').value) || 0,
    targetNetCarbs: parseFloat(document.getElementById('g-netcarbs').value) || 0,
    targetFiber: parseFloat(document.getElementById('g-fiber').value) || 0,
  };
  document.getElementById('target-cal').textContent = calcCal(g);
}

async function saveGoals() {
  const body = {
    targetProtein: parseFloat(document.getElementById('g-protein').value) || 0,
    targetFat: parseFloat(document.getElementById('g-fat').value) || 0,
    targetNetCarbs: parseFloat(document.getElementById('g-netcarbs').value) || 0,
    targetFiber: parseFloat(document.getElementById('g-fiber').value) || 0,
  };
  try {
    await api('/api/nutrition-goals', 'PUT', body);
    toast('保存しました');
  } catch (e) { toast('エラー: ' + e.message); }
}

// --- 共通 ---
function closeConfirm() {
  document.getElementById('confirm-modal').classList.remove('open');
  confirmAction = null;
}

// --- 初期化 ---
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('setup-save-btn').addEventListener('click', saveSetup);
  document.getElementById('setup-change-btn').addEventListener('click', openSetup);
  document.getElementById('food-cancel-btn').addEventListener('click', closeFoodModal);
  document.getElementById('food-save-btn').addEventListener('click', saveFood);
  document.getElementById('confirm-cancel-btn').addEventListener('click', closeConfirm);
  document.getElementById('confirm-ok').addEventListener('click', () => {
    if (confirmAction) confirmAction();
  });
  document.querySelectorAll('#sidebar nav a[data-tab]').forEach(a => {
    a.addEventListener('click', () => showTab(a.dataset.tab));
  });
  loadSetup();
});
