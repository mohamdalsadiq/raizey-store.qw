'use strict';
const params = new URLSearchParams(window.location.search);
const categoryId = params.get('id');
let exchangeRate = 1;
let products = [];
let selectedProduct = null;
let selectedInternalOption = null;
let quantity = 1;
let categoryImageUrl = '';

function safeText(value, fallback = '') { return typeof value === 'string' && value.trim() ? value.trim() : fallback; }
function safeUrl(value) { if (typeof value !== 'string' || !value.trim()) return ''; try { const url = new URL(value, window.location.href); return ['http:','https:'].includes(url.protocol) ? url.href : ''; } catch { return ''; } }
function money(value) { return typeof formatSDG === 'function' ? formatSDG(Math.max(0, Number(value) || 0)) : Math.round(Number(value) || 0).toLocaleString('ar-EG'); }
function usd(value) { const n = Number(value); return Number.isFinite(n) ? n : 0; }
function updateCartBadge() { try { document.getElementById('globalCartCount').textContent = String((JSON.parse(localStorage.getItem('meem_store_cart') || '[]') || []).length); } catch { document.getElementById('globalCartCount').textContent = '0'; } }
function showState(title, description, icon = 'package-open') { const box = document.getElementById('loadingBox'); box.innerHTML = `${window.rzIconMarkup(icon)}<h3>${escapeHtml(title)}</h3><p>${escapeHtml(description)}</p>`; box.hidden = false; document.getElementById('content').hidden = true; }
function getUnitPrice() { return selectedInternalOption ? usd(selectedInternalOption.price_usd ?? selectedInternalOption.price) : usd(selectedProduct?.price_usd); }
function getCurrentPrice() { return getUnitPrice() * (quantity > 0 ? quantity : 1); }
function updateQtyUI() { const valueEl = document.getElementById('qtyValue'); if (valueEl) valueEl.textContent = String(quantity); const minusBtn = document.getElementById('qtyMinusBtn'); if (minusBtn) minusBtn.disabled = quantity <= 1; }
function updatePrice() {
  const unit = getUnitPrice(); const qty = quantity > 0 ? quantity : 1; const total = unit * qty;
  const value = `${money(total * exchangeRate)} ج.س`;
  document.getElementById('fixedPriceAmount').textContent = value;
  const heroPrice = document.getElementById('selectedProductPrice'); if (heroPrice) heroPrice.textContent = value;
  updateQtyUI();
  const summary = document.getElementById('qtyPriceSummary');
  if (summary) {
    if (qty > 1) { summary.hidden = false; summary.innerHTML = `<span class="qty-unit">سعر الوحدة: <b>${money(unit * exchangeRate)} ج.س</b></span><span class="qty-total">الإجمالي: <b>${money(total * exchangeRate)} ج.س</b></span>`; }
    else { summary.hidden = true; summary.innerHTML = ''; }
  }
}
function changeQuantity(delta) { let next = (quantity > 0 ? quantity : 1) + delta; if (next < 1) next = 1; if (next > 99) next = 99; quantity = next; updatePrice(); }
function normalizedOptions(product) { return Array.isArray(product?.options) ? product.options.filter(Boolean).map((option, index) => ({ id: safeText(option?.id, `option_${index}`), label: safeText(option?.label, 'خيار'), price_usd: usd(option?.price_usd ?? option?.price) })) : []; }
function readFields(product) { return Array.isArray(product?.required_fields) ? product.required_fields : []; }
function renderOptions() {
  const grid = document.getElementById('productOptions'); grid.replaceChildren();
  products.forEach((product, index) => {
    const button = document.createElement('button'); button.type = 'button'; button.className = 'product-option'; button.dataset.productId = product.id; button.setAttribute('aria-pressed', selectedProduct?.id === product.id ? 'true' : 'false');
    if (selectedProduct?.id === product.id) button.classList.add('selected');
    const check = window.rzIcon('check'); check.classList.add('check');
    const name = document.createElement('span'); name.className = 'product-option-name'; name.textContent = safeText(product.name, `خيار ${index + 1}`);
    const price = document.createElement('span'); price.className = 'product-option-price'; price.textContent = `${money(usd(product.price_usd) * exchangeRate)} ج.س`;
    button.append(check, name, price); button.addEventListener('click', () => selectProduct(product.id)); grid.appendChild(button);
  });
  document.getElementById('packageCount').textContent = `${products.length} خيار متاح`;
}
function renderSelectedProduct() {
  if (!selectedProduct) { document.getElementById('selectedPanel').hidden = true; return; }
  quantity = 1;
  const panel = document.getElementById('selectedPanel'); panel.hidden = false; panel.replaceChildren();
  const head = document.createElement('div'); head.className = 'selected-product-head';
  const imageBox = document.createElement('div'); imageBox.className = 'selected-product-image'; const image = categoryImageUrl;
  if (image) { const img = document.createElement('img'); img.src = image; img.alt = safeText(selectedProduct.name, 'المنتج'); img.onerror = () => imageBox.replaceChildren(window.rzIcon('package-open')); imageBox.appendChild(img); } else imageBox.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package-open"></use></svg>';
  const headCopy = document.createElement('div'); const title = document.createElement('h3'); title.textContent = safeText(selectedProduct.name, 'المنتج'); const desc = document.createElement('p'); desc.textContent = safeText(selectedProduct.description, 'أكمل بيانات الطلب المطلوبة للمتابعة.'); headCopy.append(title, desc);
  if (safeText(selectedProduct.delivery_badge_text)) { const badge = document.createElement('span'); badge.className = 'product-badge'; badge.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-zap"></use></svg> ' + escapeHtml(selectedProduct.delivery_badge_text); headCopy.appendChild(badge); }
  head.append(imageBox, headCopy); panel.appendChild(head);
  const options = normalizedOptions(selectedProduct);
  if (options.length) {
    const titleBox = document.createElement('div'); titleBox.className = 'form-section-title'; titleBox.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-list-checks"></use></svg> اختر العرض'; panel.appendChild(titleBox);
    const optionGrid = document.createElement('div'); optionGrid.className = 'option-grid';
    options.forEach((option, index) => { const button = document.createElement('button'); button.type = 'button'; button.className = 'product-option'; button.dataset.internalId = option.id; button.setAttribute('aria-pressed', (selectedInternalOption?.id || options[0].id) === option.id ? 'true' : 'false'); if ((selectedInternalOption?.id || options[0].id) === option.id) { button.classList.add('selected'); if (!selectedInternalOption) selectedInternalOption = options[0]; } button.innerHTML = `<span class="product-option-name">${escapeHtml(option.label)}</span><span class="product-option-price">${money(option.price_usd * exchangeRate)} ج.س</span>`; button.addEventListener('click', () => { selectedInternalOption = option; optionGrid.querySelectorAll('.product-option').forEach(btn => { const isSel = btn.dataset.internalId === option.id; btn.classList.toggle('selected', isSel); btn.setAttribute('aria-pressed', isSel ? 'true' : 'false'); }); updatePrice(); }); optionGrid.appendChild(button); });
    panel.appendChild(optionGrid);
  }
  const qtyBox = document.createElement('div'); qtyBox.className = 'qty-stepper';
  const qtyLabel = document.createElement('span'); qtyLabel.className = 'qty-stepper-label'; qtyLabel.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-layers"></use></svg> الكمية';
  const qtyControls = document.createElement('div'); qtyControls.className = 'qty-stepper-controls';
  const minusBtn = document.createElement('button'); minusBtn.type = 'button'; minusBtn.id = 'qtyMinusBtn'; minusBtn.className = 'qty-btn'; minusBtn.setAttribute('aria-label', 'إنقاص الكمية'); minusBtn.disabled = quantity <= 1; minusBtn.innerHTML = '&minus;'; minusBtn.addEventListener('click', () => changeQuantity(-1));
  const qtyValueEl = document.createElement('span'); qtyValueEl.id = 'qtyValue'; qtyValueEl.className = 'qty-value'; qtyValueEl.textContent = String(quantity);
  const plusBtn = document.createElement('button'); plusBtn.type = 'button'; plusBtn.id = 'qtyPlusBtn'; plusBtn.className = 'qty-btn'; plusBtn.setAttribute('aria-label', 'زيادة الكمية'); plusBtn.innerHTML = '&plus;'; plusBtn.addEventListener('click', () => changeQuantity(1));
  qtyControls.append(minusBtn, qtyValueEl, plusBtn); qtyBox.append(qtyLabel, qtyControls); panel.appendChild(qtyBox);
  const qtySummary = document.createElement('div'); qtySummary.id = 'qtyPriceSummary'; qtySummary.className = 'qty-price-summary'; qtySummary.hidden = true; panel.appendChild(qtySummary);
  const fields = readFields(selectedProduct);
  if (fields.length) {
    const titleBox = document.createElement('div'); titleBox.className = 'form-section-title'; titleBox.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-square-pen"></use></svg> بيانات الطلب'; panel.appendChild(titleBox);
    fields.forEach(field => { const wrap = document.createElement('div'); wrap.className = 'field'; const label = document.createElement('label'); label.textContent = safeText(field.label, 'بيانات العميل'); const input = document.createElement('input'); input.type = 'text'; input.maxLength = 500; input.dataset.fieldKey = safeText(field.key, 'field'); input.dataset.fieldLabel = safeText(field.label, 'بيانات العميل'); input.placeholder = safeText(field.placeholder, `اكتب ${safeText(field.label, 'البيانات')} هنا...`); wrap.append(label, input); panel.appendChild(wrap); });
  }
  const error = document.createElement('div'); error.className = 'form-error'; error.id = 'formError'; error.tabIndex = -1; panel.appendChild(error);
  const confirm = document.createElement('button'); confirm.type = 'button'; confirm.className = 'action-btn confirm-btn'; confirm.id = 'confirmOrderBtn'; confirm.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-check"></use></svg> تأكيد الطلب'; confirm.addEventListener('click', confirmOrder);
  const add = document.createElement('button'); add.type = 'button'; add.className = 'action-btn cart-btn'; add.id = 'addToCartBtn'; add.innerHTML = '<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-shopping-cart"></use></svg> إضافة إلى السلة'; add.addEventListener('click', addToCart);
  panel.append(confirm, add);
  if (safeText(selectedProduct.instructions)) { const notes = document.createElement('div'); notes.className = 'product-instructions'; notes.innerHTML = `<strong><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-info"></use></svg> التفاصيل وطريقة الاستلام</strong>${escapeHtml(selectedProduct.instructions).replace(/\n/g, '<br>')}`; panel.appendChild(notes); }
  updatePrice();
}
function selectProduct(id) { selectedProduct = products.find(product => String(product.id) === String(id)) || products[0] || null; selectedInternalOption = null; renderOptions(); renderSelectedProduct(); document.getElementById('selectedPanel')?.scrollIntoView({ behavior:'smooth', block:'start' }); }
function collectFields() { const values = {}, labels = {}; for (const input of document.querySelectorAll('#selectedPanel [data-field-key]')) { const value = input.value.trim(); if (!value) return null; values[input.dataset.fieldKey] = value; labels[input.dataset.fieldKey] = input.dataset.fieldLabel || input.dataset.fieldKey; } return { values, labels }; }
function buildCartItem() { if (!selectedProduct) return null; const fields = collectFields(); if (!fields) return null; const priceUsd = selectedInternalOption ? usd(selectedInternalOption.price_usd ?? selectedInternalOption.price) : usd(selectedProduct.price_usd); return { cart_item_id:`${Date.now()}_${Math.random().toString(36).slice(2,8)}`, product_id:selectedProduct.id, name:selectedProduct.name, price_sdg:priceUsd * exchangeRate, quantity:(quantity > 0 ? quantity : 1), image_url:selectedProduct.image_url, selected_option:selectedInternalOption ? { id:selectedInternalOption.id, label:selectedInternalOption.label, price_usd:priceUsd, price_sdg:priceUsd * exchangeRate } : null, field_values:fields.values, field_labels:fields.labels }; }
function setError(message, success = false) { const box = document.getElementById('formError'); if (!box) return; box.textContent = message; box.style.color = success ? 'var(--cat-primary)' : ''; box.focus?.(); }
function addToCart() { const item = buildCartItem(); if (!item) { setError('اختر الباقة وأكمل بيانات الطلب المطلوبة أولاً.'); return; } let cart = []; try { cart = JSON.parse(localStorage.getItem('meem_store_cart') || '[]') || []; } catch { cart = []; } cart.push(item); localStorage.setItem('meem_store_cart', JSON.stringify(cart)); updateCartBadge(); setError('تمت إضافة الخيار إلى السلة.', true); }
async function confirmOrder() { const item = buildCartItem(); if (!item) { setError('اختر الباقة وأكمل بيانات الطلب المطلوبة أولاً.'); return; } const { data:{ session } } = await supabaseClient.auth.getSession(); if (!session) { sessionStorage.setItem('redirect_after_login', window.location.href); window.location.href = 'login.html'; return; } sessionStorage.setItem('meem_direct_buy', JSON.stringify({ created_at:Date.now(), items:[item] })); window.location.href = 'checkout-v2.html'; }
function renderCategory(category) { document.title = `${safeText(category.name, 'الباقات')} — MEEM STORE`; document.getElementById('categoryTitle').textContent = safeText(category.name, 'الباقات'); document.getElementById('categoryDescription').textContent = safeText(category.description, 'اختر الخيار المناسب لك وأكمل الطلب بخطوات بسيطة وآمنة.'); const image = safeUrl(category.image_url); categoryImageUrl = image; if (image) document.getElementById('categoryArt').replaceChildren(Object.assign(document.createElement('img'), { src:image, alt:safeText(category.name, 'القسم') })); document.getElementById('loadingBox').hidden = true; document.getElementById('content').hidden = false; if (products.length) selectProduct(products[0].id); else { document.getElementById('productOptions').innerHTML = '<div class="catalog-state"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package-open"></use></svg><h3>لا توجد خيارات متاحة حاليًا</h3><p>سيتم إضافة عروض جديدة لهذا التصنيف قريبًا.</p></div>'; } }
async function init() { updateCartBadge(); if (!categoryId) { window.location.href = 'index.html'; return; } exchangeRate = Number(await getExchangeRate()) || 1; const [categoryResponse, productsResponse] = await Promise.all([supabaseClient.from('categories').select('id,name,description,image_url').eq('id', categoryId).eq('is_active', true).single(), supabaseClient.from('products').select('id,name,description,image_url,price_usd,has_options,options,delivery_badge_text,instructions,required_fields,display_order').eq('category_id', categoryId).eq('is_active', true).order('display_order')]); if (categoryResponse.error || !categoryResponse.data) { showState('القسم غير متاح', 'ربما تم إخفاؤه أو حُذف. ارجع للمتجر واختر قسمًا آخر.', 'circle-alert'); return; } if (productsResponse.error) { showState('تعذر تحميل الخيارات', 'حدّث الصفحة وحاول مرة أخرى.', 'rotate-cw'); return; } products = productsResponse.data || []; renderCategory(categoryResponse.data); }
init().catch((error) => { devLog('[MEEM] category init error:', error); showState('تعذر تحميل الخيارات', 'تحقق من اتصالك ثم أعد المحاولة.', 'triangle-alert'); });
