let currentUser = null;
let cart = [];
let grandTotal = 0;

function safeFormatSDG(val) {
  if (typeof formatSDG === 'function') return formatSDG(val);
  const num = Math.round(val || 0);
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

async function init() {
  try {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) {
      sessionStorage.setItem('redirect_after_login', window.location.href);
      window.location.href = 'login.html';
      return;
    }
    currentUser = session.user;
  } catch (e) {
    console.error('[MEEM] Session check error:', e);
  }

  loadCartData();
}

function loadCartData() {
  try {
    cart = JSON.parse(localStorage.getItem('meem_store_cart')) || [];
  } catch (e) {
    cart = [];
  }

  document.getElementById('loadingBox').style.display = 'none';

  if (!cart || cart.length === 0) {
    showEmptyCartState();
    return;
  }

  renderCart();
}

function showEmptyCartState() {
  document.getElementById('cartContent').style.display = 'none';
  document.getElementById('clearCartBtn').style.display = 'none';
  document.getElementById('emptyCartBox').style.display = 'block';
}

function renderCart() {
  document.getElementById('emptyCartBox').style.display = 'none';
  document.getElementById('cartContent').style.display = 'block';
  document.getElementById('clearCartBtn').style.display = 'inline-flex';

  const listContainer = document.getElementById('cartItemsList');
  grandTotal = 0;

  listContainer.innerHTML = cart.map((item, index) => {
    const qty = (item.quantity && item.quantity > 0) ? item.quantity : 1;
    const unitPrice = parseFloat(item.price_sdg) || 0;
    const lineSubtotal = unitPrice * qty;
    grandTotal += lineSubtotal;

    const metaText = Object.entries(item.field_values || {})
      .map(([key, val]) => `${escapeHtml(key)}: <span>${escapeHtml(val)}</span>`)
      .join(' | ');

    return `
      <div class="cart-item-row">
        <div class="cart-item-thumb">
          ${item.image_url ? `<img src="${escapeHtml(item.image_url)}" alt="${escapeHtml(item.name)}">` : '<svg class="mm-i" style="font-size: 20px; color: var(--text-muted);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package-open"></use></svg>'}
        </div>
        <div class="cart-item-details">
          <div class="cart-item-name">${escapeHtml(item.name)}</div>
          ${metaText ? `<div class="cart-item-meta">${metaText}</div>` : ''}
          <div class="cart-item-price">${safeFormatSDG(unitPrice)} ج.س &times; ${qty} = <strong>${safeFormatSDG(lineSubtotal)} ج.س</strong></div>
          <div class="cart-qty-stepper">
            <button type="button" data-qty-index="${index}" data-qty-delta="-1" aria-label="إنقاص الكمية" ${qty <= 1 ? 'disabled' : ''}>&minus;</button>
            <span class="qty-value">${qty}</span>
            <button type="button" data-qty-index="${index}" data-qty-delta="1" aria-label="زيادة الكمية">+</button>
          </div>
        </div>
        <button class="remove-item-btn" data-remove-index="${index}" title="حذف العنصر">
          <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg>
        </button>
      </div>
    `;
  }).join('');

  listContainer.querySelectorAll('[data-qty-index]').forEach(button => button.addEventListener('click', () => changeQty(Number(button.dataset.qtyIndex), Number(button.dataset.qtyDelta))));
  listContainer.querySelectorAll('[data-remove-index]').forEach(button => button.addEventListener('click', () => removeItem(Number(button.dataset.removeIndex))));
  document.getElementById('cartGrandTotal').textContent = `${safeFormatSDG(grandTotal)} ج.س`;

  document.getElementById('proceedToCheckoutBtn').onclick = () => {
    // الدفع من السلة: نلغي أي شراء مباشر معلّق حتى لا يختلط الطلبان
    try { sessionStorage.removeItem('meem_direct_buy'); } catch (e) {}
    window.location.href = 'checkout-v2.html';
  };
}

function removeItem(index) {
  cart.splice(index, 1);
  localStorage.setItem('meem_store_cart', JSON.stringify(cart));

  if (cart.length === 0) {
    showEmptyCartState();
  } else {
    renderCart();
  }
}

function clearAllItems() {
  if (confirm('هل أنت تأكد من رغبتك في تفريغ سلة المشتريات بالكامل؟')) {
    cart = [];
    localStorage.removeItem('meem_store_cart');
    showEmptyCartState();
  }
}

function changeQty(index, delta) {
  const item = cart[index];
  if (!item) return;
  let qty = (item.quantity && item.quantity > 0) ? item.quantity : 1;
  qty += delta;
  if (qty < 1) qty = 1;
  if (qty > 99) qty = 99;
  item.quantity = qty;
  localStorage.setItem('meem_store_cart', JSON.stringify(cart));
  renderCart();
}

document.getElementById('clearCartBtn').addEventListener('click', clearAllItems);
init();
