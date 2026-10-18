'use strict';
const params = new URLSearchParams(window.location.search);
const productId = params.get('id');
let product = null;
let exchangeRate = 1;
let optionGroups = [];
let selections = new Map();
let selectionOrder = [];
let quantity = 1;

const $ = (id) => document.getElementById(id);
function text(value, fallback = '') { return typeof value === 'string' && value.trim() ? value.trim() : fallback; }
function safeUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return '';
  try { const url = new URL(value, window.location.href); return ['http:', 'https:'].includes(url.protocol) ? url.href : ''; } catch { return ''; }
}
function moneyUsd(value) { const n = Number(value); return Number.isFinite(n) ? n : 0; }
function moneySdg(value) { return formatSDG(Math.max(0, moneyUsd(value) * exchangeRate)) + ' ج.س'; }
function updateCartBadge() { try { $('globalCartCount').textContent = String((JSON.parse(localStorage.getItem('meem_store_cart') || '[]') || []).length); } catch { $('globalCartCount').textContent = '0'; } }

function normalizeOptionTree(row) {
  const tree = Array.isArray(row.option_tree) ? row.option_tree : [];
  if (tree.length) {
    const groups = tree.map((group, index) => ({
      id: text(group?.id, `group_${index}`),
      label: text(group?.label, 'اختر الخيار'),
      required: group?.required === true,
      options: Array.isArray(group?.options) ? group.options.map((option, optionIndex) => normalizeOption(option, `option_${index}_${optionIndex}`)) : []
    })).filter(group => group.options.length);
    return flattenBaseOptionGroup(groups);
  }

  const legacy = Array.isArray(row.options) ? row.options : [];
  if (!legacy.length) return [];
  const groups = new Map();
  legacy.forEach((raw, index) => {
    let groupLabel = text(raw?.group, '');
    let optionLabel = text(raw?.label, 'خيار');
    if (!groupLabel && optionLabel.includes(' - ')) {
      const parts = optionLabel.split(' - '); groupLabel = text(parts.shift(), 'خيارات المنتج'); optionLabel = text(parts.join(' - '), 'خيار');
    }
    groupLabel = groupLabel || 'خيارات المنتج';
    const groupId = slug(groupLabel) || `legacy_group_${index}`;
    if (!groups.has(groupId)) groups.set(groupId, { id: groupId, label: groupLabel, required: true, options: [] });
    groups.get(groupId).options.push(normalizeOption({ ...raw, label: optionLabel }, `legacy_option_${index}`));
  });
  return flattenBaseOptionGroup([...groups.values()]);
}
function flattenBaseOptionGroup(groups) {
  if (groups.length !== 1) return groups;
  const group = groups[0];
  if (group.options.length !== 1 || !group.options[0]?.children?.length) return groups;
  const base = group.options[0];
  return [{
    id: `${group.id}__${base.id}`,
    label: 'اختر الخيار المطلوب',
    required: group.required || true,
    options: base.children
  }];
}
function normalizeOption(raw, fallbackId) {
  return {
    id: text(raw?.id, fallbackId),
    label: text(raw?.label, 'خيار'),
    price_usd: moneyUsd(raw?.price_usd ?? raw?.price),
    children_label: text(raw?.children_label, 'الخيارات الفرعية'),
    children: Array.isArray(raw?.children) ? raw.children.map((child, index) => normalizeOption(child, `${fallbackId}_child_${index}`)) : []
  };
}
function slug(value) { return String(value).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_|_$/g, '').slice(0, 80); }
function optionsAreRequired() { return product?.options_required === true || (!Array.isArray(product?.option_tree) || product.option_tree.length === 0) && Array.isArray(product?.options) && product.options.length > 0; }

function selectedFinalOption() {
  let final = null;
  for (const group of optionGroups) {
    const option = selections.get(group.id);
    if (!option) break;
    final = option;
    let childGroup = childGroupFor(group, option);
    while (childGroup) {
      const child = selections.get(childGroup.id);
      if (!child) break;
      final = child;
      childGroup = childGroupFor(childGroup, child);
    }
  }
  return final;
}
function childGroupFor(group, option) {
  return option?.children?.length ? { id: `${group.id}__${option.id}`, label: option.children_label || 'الخيارات الفرعية', required: optionsAreRequired(), options: option.children } : null;
}
function selectedUsd() { return selectedFinalOption() ? selectedFinalOption().price_usd : moneyUsd(product?.price_usd); }
function updatePriceUI() {
  const price = moneySdg(selectedUsd() * quantity);
  const heroPrice = $('heroPriceDisplay');
  const summaryTotal = $('summaryTotal');
  const fixedPrice = $('fixedPriceAmount');
  if (heroPrice) heroPrice.textContent = price;
  if (summaryTotal) summaryTotal.textContent = price;
  if (fixedPrice) {
    fixedPrice.textContent = price;
    fixedPrice.classList.remove('placeholder');
  }
}

function ensureDefaultSelections() {
  const visit = (group) => {
    const required = group.required || optionsAreRequired();
    if (required && !selections.has(group.id) && group.options.length) {
      const first = group.options[0];
      selections.set(group.id, first);
      selectionOrder.push({ groupId: group.id, option: first });
    }
    const selected = selections.get(group.id);
    const child = childGroupFor(group, selected);
    if (child) visit(child);
  };
  optionGroups.forEach(visit);
}

function renderOptionTree() {
  const container = $('optionTree');
  container.replaceChildren();
  const renderGroup = (group, depth = 0) => {
    const section = document.createElement('section');
    section.className = `option-group ${group.required || optionsAreRequired() ? 'required' : 'optional'}`;
    section.dataset.groupId = group.id;
    const title = document.createElement('div'); title.className = 'option-group-title';
    const label = document.createElement('span'); label.textContent = group.label;
    const hint = document.createElement('small'); hint.textContent = group.required || optionsAreRequired() ? 'اختر واحدًا' : 'اختياري';
    title.append(label, hint);
    const grid = document.createElement('div'); grid.className = 'option-grid';
    group.options.forEach(option => {
      const button = document.createElement('button'); button.type = 'button'; button.className = 'option-button'; button.dataset.optionId = option.id;
      button.setAttribute('aria-pressed', selections.get(group.id)?.id === option.id ? 'true' : 'false');
      const check = window.rzIcon('check'); check.classList.add('check');
      const optionLabel = document.createElement('span'); optionLabel.className = 'option-label'; optionLabel.textContent = option.label;
      const optionPrice = document.createElement('span'); optionPrice.className = 'option-price'; optionPrice.textContent = moneySdg(option.price_usd);
      button.append(check, optionLabel, optionPrice);
      if (selections.get(group.id)?.id === option.id) button.classList.add('selected');
      button.addEventListener('click', () => {
        selections.set(group.id, option);
        selectionOrder = selectionOrder.filter(item => item.groupId !== group.id && !item.groupId.startsWith(`${group.id}__`));
        selectionOrder.push({ groupId: group.id, option });
        for (const key of [...selections.keys()]) if (key.startsWith(`${group.id}__`)) selections.delete(key);
        renderOptionTree(); updatePriceUI();
      });
      grid.appendChild(button);
    });
    section.append(title, grid);
    const selected = selections.get(group.id);
    if (selected?.children?.length) {
      const childGroup = childGroupFor(group, selected);
      section.appendChild(renderGroup(childGroup, depth + 1));
    }
    return section;
  };
  optionGroups.forEach(group => container.appendChild(renderGroup({ ...group, required: group.required || optionsAreRequired() })));
  $('optionTree').hidden = optionGroups.length === 0;
}

function hasRequiredGap() {
  if (!optionsAreRequired()) return false;
  const checkGroup = (group) => {
    const selected = selections.get(group.id);
    if (!selected) return true;
    const child = childGroupFor(group, selected);
    return child ? checkGroup(child) : false;
  };
  return optionGroups.some(checkGroup);
}
function validateSelection(errorBox) {
  if (hasRequiredGap()) {
    errorBox.textContent = 'اختر جميع الخيارات المطلوبة قبل المتابعة.';
    errorBox.focus?.();
    return false;
  }
  return true;
}
function collectFields() {
  const values = {}, labels = {};
  for (const input of document.querySelectorAll('[data-field-key]')) {
    const value = input.value.trim();
    if (!value) return null;
    values[input.dataset.fieldKey] = value;
    labels[input.dataset.fieldKey] = input.dataset.fieldLabel || input.dataset.fieldKey;
  }
  return { values, labels };
}
function buildCartItem() {
  const fields = collectFields();
  if (!fields) return null;
  const final = selectedFinalOption();
  const selectedPath = selectionOrder.map(item => ({ group_id: item.groupId, option_id: item.option.id, label: item.option.label, price_usd: item.option.price_usd }));
  return {
    cart_item_id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    product_id: product.id,
    name: product.name,
    price_sdg: selectedUsd() * exchangeRate,
    quantity,
    image_url: product.image_url,
    selected_option: final ? { id: final.id, label: final.label, price_usd: final.price_usd, price_sdg: final.price_usd * exchangeRate, path: selectedPath } : null,
    field_values: fields.values,
    field_labels: fields.labels
  };
}
function addToCart() {
  const error = $('formError'); error.textContent = '';
  if (!validateSelection(error)) return;
  const item = buildCartItem();
  if (!item) { error.textContent = 'أكمل بيانات العميل المطلوبة أولاً.'; return; }
  let cart = []; try { cart = JSON.parse(localStorage.getItem('meem_store_cart') || '[]') || []; } catch { cart = []; }
  cart.push(item); localStorage.setItem('meem_store_cart', JSON.stringify(cart)); updateCartBadge();
  error.style.color = 'var(--product-primary)'; error.textContent = 'تمت إضافة المنتج إلى السلة.';
  $('addToCartBtn').innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-check"></use></svg> تمت الإضافة';
  setTimeout(() => { $('addToCartBtn').innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-shopping-cart"></use></svg> إضافة إلى السلة'; error.textContent = ''; error.style.color = ''; }, 2200);
}
async function buyNow() {
  const error = $('formError'); error.textContent = ''; error.style.color = '';
  if (!validateSelection(error)) return;
  const item = buildCartItem();
  if (!item) { error.textContent = 'أكمل بيانات العميل المطلوبة أولاً.'; return; }
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    sessionStorage.setItem('redirect_after_login', window.location.href);
    window.location.href = 'login.html';
    return;
  }
  sessionStorage.setItem('meem_direct_buy', JSON.stringify({ created_at: Date.now(), items: [item] }));
  window.location.href = 'checkout-v2.html';
}

function renderProduct() {
  const imageUrl = safeUrl(product.image_url);
  $('loadingBox').hidden = true; $('content').hidden = false;
  $('content').innerHTML = `
    <div class="product-hero">
      <div class="product-hero-thumb">${imageUrl ? `<img src="${escapeAttribute(imageUrl)}" alt="${escapeAttribute(text(product.name, 'منتج'))}">` : '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package-open"></use></svg>'}</div>
      <div class="product-hero-info"><h1>${escapeHtml(text(product.name, 'منتج رقمي'))}</h1>${text(product.delivery_badge_text) ? `<span class="product-hero-badge"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-zap"></use></svg>${escapeHtml(product.delivery_badge_text)}</span>` : ''}<div class="product-hero-price ${optionGroups.length && optionsAreRequired() ? 'pending' : ''}" id="heroPriceDisplay">${optionGroups.length && optionsAreRequired() ? 'اختر الخيار المطلوب' : moneySdg(selectedUsd() * quantity)}</div></div>
    </div>
    ${optionGroups.length ? '<div class="section-label"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-list-checks"></use></svg> اختر الخيار المطلوب</div><div id="optionTree"></div>' : ''}
    ${(Array.isArray(product.required_fields) && product.required_fields.length) ? `<div class="section-label"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-square-pen"></use></svg> بيانات الطلب</div>${product.required_fields.map(field => `<div class="field"><label>${escapeHtml(text(field.label, 'بيانات العميل'))}</label><input type="text" maxlength="500" data-field-key="${escapeAttribute(text(field.key, 'field'))}" data-field-label="${escapeAttribute(text(field.label, 'بيانات العميل'))}" placeholder="${escapeAttribute(text(field.placeholder, `اكتب ${text(field.label, 'البيانات')} هنا...`))}"></div>`).join('')}` : ''}
    <div class="form-error" id="formError" tabindex="-1"></div>
    <button class="product-confirm-btn" id="buyNowBtn" type="button"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-check"></use></svg> تأكيد الطلب</button>
    <button class="btn-secondary-cart" id="addToCartBtn" type="button"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-shopping-cart"></use></svg> إضافة إلى السلة</button>
    ${product.instructions ? `<div class="product-instructions-box"><div class="product-instructions-title"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-info"></use></svg> التفاصيل وطريقة الاستلام</div><div>${escapeHtml(product.instructions).replace(/\n/g, '<br>')}</div></div>` : ''}
  `;
  if (optionGroups.length) { ensureDefaultSelections(); renderOptionTree(); $('fixedPriceBar').hidden = false; updatePriceUI(); } else { $('fixedPriceBar').hidden = false; updatePriceUI(); }
  $('buyNowBtn').addEventListener('click', buyNow); $('addToCartBtn').addEventListener('click', addToCart);
}

async function init() {
  updateCartBadge();
  if (!productId) { window.location.href = 'index.html'; return; }
  // التصفح عام، ويُطلب تسجيل الدخول فقط عند الضغط على الشراء.
  exchangeRate = Number(await getExchangeRate()) || 1;
  const { data, error } = await supabaseClient.from('products').select('*').eq('id', productId).eq('is_active', true).single();
  if (error || !data) { $('loadingBox').textContent = 'المنتج غير موجود أو غير متاح حالياً.'; return; }
  product = data; optionGroups = normalizeOptionTree(product);
  document.title = `${text(product.name, 'تفاصيل المنتج')} — MEEM STORE`;
  renderProduct();
}
init();
