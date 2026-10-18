'use strict';
let exchangeRate = 1;

function esc(value) { return typeof escapeHtml === 'function' ? escapeHtml(value) : String(value == null ? '' : value); }
function money(value) { return typeof formatSDG === 'function' ? formatSDG(Math.max(0, Number(value) || 0)) : Math.round(Number(value) || 0).toLocaleString('ar-EG'); }
function safeUrl(value) {
  if (typeof value !== 'string' || !value.trim()) return '';
  try { const u = new URL(value, window.location.href); return ['http:', 'https:'].includes(u.protocol) ? u.href : ''; } catch (e) { return ''; }
}
function iconMarkup(name) { return typeof window.rzIconMarkup === 'function' ? window.rzIconMarkup(name) : ''; }

function updateCartBadge() {
  const node = document.getElementById('globalCartCount');
  if (!node) return;
  try { node.textContent = String((JSON.parse(localStorage.getItem('meem_store_cart') || '[]') || []).length); }
  catch (e) { node.textContent = '0'; }
}

function showState(title, description, icon) {
  const box = document.getElementById('stateBox');
  while (box.firstChild) box.removeChild(box.firstChild);
  box.insertAdjacentHTML('beforeend', iconMarkup(icon || 'package-open'));
  const h = document.createElement('h3'); h.textContent = title;
  const p = document.createElement('p'); p.textContent = description;
  box.append(h, p);
  box.hidden = false;
  document.getElementById('content').hidden = true;
}

function buildCard(product) {
  const name = typeof product.name === 'string' && product.name.trim() ? product.name.trim() : 'منتج';
  const price = Number(product.price_usd) || 0;
  const compare = Number(product.compare_at_price_usd) || 0;
  const discount = compare > 0 ? Math.round((1 - price / compare) * 100) : 0;

  const card = document.createElement('a');
  card.className = 'game-card offer-card';
  card.href = 'product.html?id=' + encodeURIComponent(String(product.id));
  card.setAttribute('aria-label', 'فتح ' + name + (discount > 0 ? ' — خصم ' + discount + '%' : ''));

  if (discount > 0) {
    const badge = document.createElement('span');
    badge.className = 'offer-badge';
    badge.textContent = 'خصم ' + discount + '%';
    card.appendChild(badge);
  }

  const thumb = document.createElement('div');
  thumb.className = 'game-thumb';
  const imageUrl = safeUrl(product.image_url);
  if (imageUrl) {
    const img = document.createElement('img');
    img.src = imageUrl;
    img.alt = name;
    img.loading = 'lazy';
    img.decoding = 'async';
    img.addEventListener('error', () => { thumb.replaceChildren(); thumb.style.cssText = 'color:var(--mm-haze); font-size:32px;'; thumb.insertAdjacentHTML('beforeend', iconMarkup('gamepad-2')); }, { once: true });
    thumb.appendChild(img);
  } else {
    thumb.style.cssText = 'color:var(--mm-haze); font-size:32px;';
    thumb.insertAdjacentHTML('beforeend', iconMarkup('gamepad-2'));
  }

  const info = document.createElement('div');
  info.className = 'game-info';
  const nameEl = document.createElement('div');
  nameEl.className = 'game-name';
  nameEl.textContent = name;
  const prices = document.createElement('div');
  prices.className = 'offer-prices';
  const newPrice = document.createElement('span');
  newPrice.className = 'offer-new';
  newPrice.textContent = money(price * exchangeRate) + ' ج.س';
  prices.appendChild(newPrice);
  if (compare > price) {
    const oldPrice = document.createElement('span');
    oldPrice.className = 'offer-old';
    oldPrice.textContent = money(compare * exchangeRate) + ' ج.س';
    prices.appendChild(oldPrice);
  }
  info.append(nameEl, prices);
  card.append(thumb, info);
  return card;
}

async function init() {
  updateCartBadge();
  try { exchangeRate = Number(await getExchangeRate()) || 1; } catch (e) { exchangeRate = 1; }

  // The is_on_offer flag only exists after the catalog migration; read the marker
  // first so we never issue a request against a column that is not there yet.
  const BASE_COLS = 'id,name,image_url,price_usd,compare_at_price_usd,category_id,delivery_badge_text';
  let useFlag = false;
  try {
    const { data: marker } = await supabaseClient
      .from('settings').select('value').eq('key', 'offers_use_flag').maybeSingle();
    useFlag = !!(marker && String(marker.value).toLowerCase() === 'true');
  } catch (e) { useFlag = false; }

  const query = useFlag
    ? await supabaseClient.from('products')
        .select(BASE_COLS + ',is_on_offer')
        .eq('is_active', true)
        .order('display_order', { ascending: true }).limit(200)
    : await supabaseClient.from('products')
        .select(BASE_COLS)
        .eq('is_active', true)
        .not('compare_at_price_usd', 'is', null)
        .order('display_order', { ascending: true }).limit(200);
  const { data, error } = query;

  if (error) {
    showState('تعذر تحميل العروض', 'حدّث الصفحة وحاول مرة أخرى.', 'rotate-cw');
    return;
  }

  const offers = (data || [])
    .filter((p) => Number(p.price_usd) >= 0 &&
      (Number(p.compare_at_price_usd) > Number(p.price_usd) || (useFlag && p.is_on_offer === true)))
    .sort((a, b) => {
      const da = a.compare_at_price_usd ? 1 - Number(a.price_usd) / Number(a.compare_at_price_usd) : 0;
      const db = b.compare_at_price_usd ? 1 - Number(b.price_usd) / Number(b.compare_at_price_usd) : 0;
      return db - da;
    });

  if (!offers.length) {
    showState('لا توجد عروض حالياً', 'تابعنا قريباً — نضيف تخفيضات جديدة باستمرار.', 'tag');
    return;
  }

  const grid = document.getElementById('offersGrid');
  while (grid.firstChild) grid.removeChild(grid.firstChild);
  const frag = document.createDocumentFragment();
  offers.forEach((p) => frag.appendChild(buildCard(p)));
  grid.appendChild(frag);
  document.getElementById('stateBox').hidden = true;
  document.getElementById('content').hidden = false;
}

init();
