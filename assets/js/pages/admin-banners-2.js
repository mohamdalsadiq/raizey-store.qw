/* =========================================================
   MEEM STORE — إدارة البنرات
   الكتابة كلها عبر RPCs محمية (is_admin + has_admin_permission + audit log).
   كل إخراج بيانات يمر عبر textContent / DOM — لا innerHTML.
   ========================================================= */
const DESKTOP_BOX = { w: 1920, h: 640 };
const BU = window.MeemBannerUtils;
const MAX_BYTES = 300 * 1024;
const ALLOWED_PAGES = [
  ['index.html', 'الصفحة الرئيسية'],
  ['index.html#products', 'الصفحة الرئيسية — قسم المنتجات'],
  ['offers.html', 'صفحة العروض'],
  ['wallet.html', 'المحفظة وشحن الرصيد'],
  ['cart.html', 'السلة'],
  ['my-orders.html', 'سجل الطلبات'],
  ['search.html', 'البحث'],
  ['account.html', 'إعدادات الحساب'],
  ['referrals.html', 'الإحالات'],
  ['notifications.html', 'الإشعارات'],
  ['privacy.html', 'الخصوصية']
];

const $ = (id) => document.getElementById(id);
function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
}
function show(node, on) { if (node) node.hidden = !on; }
function blank(node) { while (node.firstChild) node.removeChild(node.firstChild); }

const state = {
  banners: [], editing: null, products: [], categories: [], pvView: 'desktop',
  mobileRatio: '16:9', previewUrls: [],
  slots: { desktop: null, mobile: null }
};
function newSlot() { return { file: null, img: null, mode: 'cover', fx: .5, fy: .5, url: '', blob: null }; }

/* ---------- الصور: اقتصاص / خلفية ضبابية / تصدير WebP < 300KB ---------- */
function loadImageFromFile(file) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('تعذر قراءة ملف الصورة')); };
    img.src = url;
  });
}

function drawSlot(canvas, img, box, mode, fx, fy) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width = box.w, H = canvas.height = box.h;
  ctx.clearRect(0, 0, W, H);
  if (!img) { ctx.fillStyle = '#04123F'; ctx.fillRect(0, 0, W, H); return; }
  const targetRatio = box.w / box.h;

  if (mode === 'contain') {
    const cs = Math.max(W / img.width, H / img.height);
    ctx.save();
    ctx.filter = 'blur(22px) brightness(.55)';
    ctx.drawImage(img, (W - img.width * cs) / 2, (H - img.height * cs) / 2, img.width * cs, img.height * cs);
    ctx.restore();
    const fs = Math.min(W / img.width, H / img.height);
    const fw = img.width * fs, fh = img.height * fs;
    ctx.drawImage(img, (W - fw) / 2, (H - fh) / 2, fw, fh);
    return;
  }

  let sw, sh;
  if (img.width / img.height > targetRatio) { sh = img.height; sw = sh * targetRatio; }
  else { sw = img.width; sh = sw / targetRatio; }
  const sx = Math.min(Math.max(fx * img.width - sw / 2, 0), Math.max(img.width - sw, 0));
  const sy = Math.min(Math.max(fy * img.height - sh / 2, 0), Math.max(img.height - sh, 0));
  ctx.drawImage(img, sx, sy, sw, sh, 0, 0, W, H);
}

function canvasToWebp(canvas) {
  return new Promise((resolve, reject) => {
    const attempt = (q) => {
      canvas.toBlob((blob) => {
        if (!blob) { reject(new Error('تعذر تصدير الصورة')); return; }
        if (blob.size <= MAX_BYTES || q <= 0.5) { resolve(blob); return; }
        attempt(Math.round((q - 0.06) * 100) / 100);
      }, 'image/webp', q);
    };
    attempt(0.86);
  });
}

function slotBox(name) { return name === 'desktop' ? DESKTOP_BOX : BU.mobileBox(state.mobileRatio); }

function refreshSlot(name) {
  const slot = state.slots[name];
  const canvas = $(name + 'Canvas');
  drawSlot(canvas, slot.img, slotBox(name), slot.mode, slot.fx, slot.fy);
  $(name + 'SizeNote').textContent = slot.img
    ? 'سيُصدَّر ' + slotBox(name).w + '×' + slotBox(name).h + ' WebP'
    : '';
}

async function exportSlot(name) {
  const slot = state.slots[name];
  const canvas = $(name + 'Canvas');
  drawSlot(canvas, slot.img, slotBox(name), slot.mode, slot.fx, slot.fy);
  const blob = await canvasToWebp(canvas);
  if (blob.size > MAX_BYTES) throw new Error('الصورة أكبر من 300KB بعد الضغط');
  slot.blob = blob;
  $(name + 'SizeNote').textContent = Math.round(blob.size / 1024) + ' KB / 300 KB';
  return blob;
}

function bindCrop(name) {
  const wrap = $(name + 'CropWrap');
  const focus = $(name + 'Focus');
  let dragging = false;
  const setFrom = (event) => {
    const slot = state.slots[name];
    const r = wrap.getBoundingClientRect();
    slot.fx = Math.min(Math.max((event.clientX - r.left) / r.width, 0), 1);
    slot.fy = Math.min(Math.max((event.clientY - r.top) / r.height, 0), 1);
    focus.style.left = (slot.fx * 100) + '%';
    focus.style.top = (slot.fy * 100) + '%';
    refreshSlot(name);
  };
  wrap.addEventListener('pointerdown', (e) => { dragging = true; try { wrap.setPointerCapture(e.pointerId); } catch (_) {} setFrom(e); });
  wrap.addEventListener('pointermove', (e) => { if (dragging) setFrom(e); });
  wrap.addEventListener('pointerup', async () => { dragging = false; try { await exportSlot(name); renderPreview(); } catch (e) { formError.textContent = e.message; } });
  wrap.addEventListener('pointercancel', () => { dragging = false; });

  $(name + 'ModeToggle').addEventListener('click', async (e) => {
    const slot = state.slots[name];
    const btn = e.target.closest('button[data-mode]');
    if (!btn) return;
    slot.mode = btn.dataset.mode;
    [...$(name + 'ModeToggle').querySelectorAll('button')]
      .forEach((b) => b.classList.toggle('active', b === btn));
    refreshSlot(name);
    if (slot.img) { try { await exportSlot(name); renderPreview(); } catch (err) { formError.textContent = err.message; } }
  });
}

async function pickFile(name, file) {
  const allowed = ['image/jpeg', 'image/png', 'image/webp'];
  if (allowed.indexOf(file.type) === -1) throw new Error('صيغة غير مدعومة (JPG / PNG / WEBP فقط)');
  if (file.size > 12 * 1024 * 1024) throw new Error('ملف المصدر كبير جداً (الحد 12MB)');
  const img = await loadImageFromFile(file);
  const slot = state.slots[name];
  slot.file = file; slot.img = img; slot.fx = .5; slot.fy = .5; slot.url = ''; slot.blob = null;
  $(name + 'CropWrap').hidden = false;
  $(name + 'Focus').style.left = '50%';
  $(name + 'Focus').style.top = '50%';
  $(name + 'SlotState').textContent = file.name + ' — ' + img.width + '×' + img.height;
  if (name === 'desktop') $('desktopCropHint').hidden = false;
  refreshSlot(name);
}

/* ---------- القوائم المرجعية ---------- */
async function loadRefData() {
  blank(pageSelect);
  ALLOWED_PAGES.forEach(([value, label]) => {
    const o = el('option', null, label); o.value = value; pageSelect.appendChild(o);
  });
  const { data: products } = await supabaseClient.from('products')
    .select('id, name, is_active').order('name').limit(500);
  state.products = products || [];
  blank(productSelect);
  productSelect.appendChild(el('option', null, '— اختر منتجاً —'));
  state.products.forEach((p) => {
    const o = el('option', null, p.name + (p.is_active ? '' : ' (معطّل)'));
    o.value = p.id; productSelect.appendChild(o);
  });
  const { data: cats } = await supabaseClient.from('categories')
    .select('id, name, is_active').order('display_order').limit(300);
  state.categories = cats || [];
  blank(categorySelect);
  categorySelect.appendChild(el('option', null, '— اختر قسماً —'));
  state.categories.forEach((c) => {
    const o = el('option', null, c.name + (c.is_active ? '' : ' (معطّل)'));
    o.value = c.id; categorySelect.appendChild(o);
  });
}

/* ---------- قائمة البنرات ---------- */
function linkLabel(b) {
  const map = { none: 'بدون رابط', page: 'صفحة داخلية', product: 'منتج', category: 'قسم', offers: 'صفحة العروض', whatsapp: 'واتساب', url: 'رابط خارجي' };
  let target = '';
  if (b.link_type === 'product') {
    const p = state.products.filter((x) => x.id === b.link_target)[0];
    target = p ? ' — ' + p.name : '';
  } else if (b.link_type === 'category') {
    const c = state.categories.filter((x) => x.id === b.link_target)[0];
    target = c ? ' — ' + c.name : '';
  } else if (b.link_target) {
    target = ' — ' + b.link_target;
  }
  return (map[b.link_type] || b.link_type) + target;
}

/* نسبة الموبايل + إعدادات السلايدر إعدادات عامة في public.settings. */
async function loadRatioSetting() {
  const sel = $('mobileRatioSelect');
  const saveSetting = async (key, value, noteFn, okMsg) => {
    try {
      const { error } = await supabaseClient.from('settings')
        .upsert({ key, value, updated_at: new Date().toISOString() }, { onConflict: 'key' });
      if (error) throw error;
      if (noteFn) noteFn(okMsg, false);
      return true;
    } catch (err) {
      if (noteFn) noteFn('تعذر الحفظ: ' + (err && err.message ? err.message : err), true);
      return false;
    }
  };
  if (sel) {
    sel.addEventListener('change', async () => {
      const old = state.mobileRatio;
      sel.disabled = true;
      if (await saveSetting('banner_mobile_ratio', sel.value, setRatioNote, 'تم حفظ نسبة الموبايل: ' + sel.value)) {
        state.mobileRatio = sel.value;
        if (state.slots.mobile?.img) await exportSlot('mobile');
        renderPreview();
      } else sel.value = old;
      sel.disabled = false;
    });
  }

  const autoplay = $('autoplaySelect'), interval = $('intervalInput'), effect = $('effectSelect');
  const setSliderNote = (t, isErr) => { const n = $('sliderNote'); if (n) { n.textContent = t; n.style.color = isErr ? 'var(--danger)' : 'var(--mm-text-muted)'; } };
  const clampIv = (v) => Math.min(10, Math.max(3, parseInt(v, 10) || 5));
  if (autoplay) autoplay.addEventListener('change', () => saveSetting('banner_autoplay', autoplay.value, setSliderNote, 'تم حفظ التشغيل التلقائي: ' + (autoplay.value === 'true' ? 'تشغيل' : 'إيقاف')));
  if (interval) interval.addEventListener('change', () => { interval.value = clampIv(interval.value); saveSetting('banner_interval', String(interval.value), setSliderNote, 'تم حفظ المدة: ' + interval.value + ' ثواني'); });
  if (effect) effect.addEventListener('change', () => saveSetting('banner_effect', effect.value, setSliderNote, 'تم حفظ نوع الانتقال: ' + effect.value));

  try {
    const { data } = await supabaseClient.from('settings')
      .select('key,value').in('key', ['banner_mobile_ratio', 'banner_mobile_aspect', 'banner_autoplay', 'banner_interval', 'banner_effect']);
    const map = {};
    (data || []).forEach((r) => { map[r.key] = r.value; });
    const v = map.banner_mobile_ratio || map.banner_mobile_aspect || '16:9';
    state.mobileRatio = BU.ratios[String(v)] ? String(v) : '16:9';
    if (sel) sel.value = state.mobileRatio;
    if (autoplay) autoplay.value = (String(map.banner_autoplay).toLowerCase() === 'false' || String(map.banner_autoplay).toLowerCase() === 'off') ? 'false' : 'true';
    if (interval) interval.value = String(clampIv(map.banner_interval));
    if (effect) effect.value = String(map.banner_effect).toLowerCase() === 'fade' ? 'fade' : 'slide';
  } catch (e) { /* keep the defaults */ }
}

function setRatioNote(text, isError) {
  const n = $('mobileRatioNote');
  if (!n) return;
  n.textContent = text;
  n.style.color = isError ? 'var(--danger)' : 'var(--mm-text-muted)';
}

async function loadBanners() {
  const { data, error } = await supabaseClient.from('banners').select('*')
    .order('sort_order', { ascending: true }).order('created_at', { ascending: true });
  if (error) {
    blank(bannersList);
    bannersList.appendChild(el('div', null, 'تعذر تحميل البنرات: ' + error.message));
    return;
  }
  state.banners = data || [];
  renderList();
}

function renderList() {
  blank(bannersList);
  if (!state.banners.length) {
    bannersList.appendChild(el('div', null, 'لا توجد بنرات بعد — أضف أول بنر.'));
    return;
  }
  state.banners.forEach((b) => {
    const card = el('div', 'bn-card' + (b.is_active ? '' : ' is-off'));
    const img = el('img', 'bn-thumb');
    img.src = b.image_desktop_url;
    img.alt = b.alt_text || 'معاينة البنر';
    img.width = 160; img.height = 60; img.loading = 'lazy'; img.decoding = 'async';
    card.appendChild(img);

    const body = el('div', 'bn-card-body');
    body.appendChild(el('p', 'bn-card-title',
      b.title || (b.banner_style === 'image_only' ? '(صورة فقط بدون نص)' : '(بدون عنوان)')));
    const meta = el('div', 'bn-meta');
    const isDraft = b.status === 'draft';
    meta.appendChild(el('span', 'bn-pill' + (isDraft ? ' off' : ''), isDraft ? 'مسودة' : 'منشور'));
    meta.appendChild(el('span', 'bn-pill' + (b.is_active ? '' : ' off'), b.is_active ? 'مفعّل' : 'معطّل'));
    meta.appendChild(el('span', null, b.banner_style === 'image_text' ? 'صورة + نص' : 'صورة فقط'));
    meta.appendChild(el('span', null, 'الترتيب: ' + b.sort_order));
    meta.appendChild(el('span', null, linkLabel(b)));
    if (b.starts_at || b.ends_at) {
      const f = (v) => v ? new Date(v).toLocaleString('ar-EG', { timeZone: 'Africa/Khartoum', dateStyle: 'medium', timeStyle: 'short' }) : '—';
      meta.appendChild(el('span', null, 'من ' + f(b.starts_at) + ' إلى ' + f(b.ends_at) + ' (الخرطوم UTC+2)'));
    }
    body.appendChild(meta);

    const actions = el('div', 'bn-actions');
    const mk = (label, fn, cls) => {
      const btn = el('button', cls || null, label);
      btn.type = 'button';
      btn.addEventListener('click', fn);
      return btn;
    };
    actions.appendChild(mk('تعديل', () => openForm(b)));
    actions.appendChild(mk('أعلى', () => reorder(b.id, 'up')));
    actions.appendChild(mk('أسفل', () => reorder(b.id, 'down')));
    actions.appendChild(mk(b.is_active ? 'تعطيل' : 'تفعيل', () => toggleActive(b)));
    actions.appendChild(mk(isDraft ? 'نشر' : 'إلى مسودة', () => toggleStatus(b)));
    actions.appendChild(mk('نسخ', () => copyBanner(b)));
    actions.appendChild(mk('حذف', () => removeBanner(b), 'danger'));
    body.appendChild(actions);
    card.appendChild(body);
    bannersList.appendChild(card);
  });
}

async function reorder(id, direction) {
  const { error } = await supabaseClient.rpc('admin_reorder_banner', { p_id: id, p_direction: direction });
  if (error) { alert('تعذر تغيير الترتيب: ' + error.message); return; }
  await loadBanners();
}
async function toggleActive(b) {
  const { error } = await supabaseClient.rpc('admin_set_banner_active', { p_id: b.id, p_active: !b.is_active });
  if (error) { alert('تعذر التغيير: ' + error.message); return; }
  await loadBanners();
}
async function toggleStatus(b) {
  const next = b.status === 'draft' ? 'published' : 'draft';
  const { error } = await supabaseClient.rpc('admin_set_banner_status', { p_id: b.id, p_status: next });
  if (error) {
    const m = (error.message || '').trim();
    alert(m === 'ALT_REQUIRED' ? 'لا يمكن النشر قبل كتابة النص البديل (alt) للصورة.' : 'تعذر التغيير: ' + m);
    return;
  }
  await loadBanners();
}
async function copyBanner(b) {
  const { error } = await supabaseClient.rpc('admin_copy_banner', { p_id: b.id });
  if (error) { alert('تعذر النسخ: ' + error.message); return; }
  await loadBanners();
}
async function removeBanner(b) {
  if (!confirm('حذف البنر «' + (b.title || b.alt_text || 'صورة فقط') + '» نهائياً؟ لا يمكن التراجع عن الحذف.')) return;
  const { error } = await supabaseClient.rpc('admin_delete_banner', { p_id: b.id });
  if (error) { alert('تعذر الحذف: ' + error.message); return; }
  await loadBanners();
}

/* ---------- النموذج ---------- */
function resetForm() {
  styleInput.value = 'image_text';
  [titleInput, subtitleInput, ctaInput, altInput, urlInput, waMessageInput, startInput, endInput]
    .forEach((i) => { i.value = ''; });
  linkTypeInput.value = 'none';
  pageSelect.value = 'index.html';
  productSelect.value = ''; categorySelect.value = '';
  activeInput.value = 'true'; hideDisabledInput.value = 'true'; $('statusInput').value = 'draft';
  $('ovdInput').value = 'right'; $('ovmInput').value = 'top';
  $('desktopSlotState').textContent = 'لم تُختر صورة بعد';
  $('mobileSlotState').textContent = 'لم تُختر صورة — ستُولَّد من صورة الديسكتوب';
  $('desktopCropWrap').hidden = true; $('mobileCropWrap').hidden = true;
  $('desktopCropHint').hidden = true;
  $('desktopSizeNote').textContent = ''; $('mobileSizeNote').textContent = '';
  $('desktopFileInput').value = ''; $('mobileFileInput').value = '';
  state.slots.desktop = newSlot();
  state.slots.mobile = newSlot();
  document.querySelectorAll('.pv-toggle button[data-mode]').forEach((b) => b.classList.toggle('active', b.dataset.mode === 'cover'));
  formError.textContent = '';
  updateCounters();
  syncStyleFields();
  syncLinkFields();
}

function openForm(banner) {
  state.editing = banner || null;
  resetForm();
  $('formModalTitle').textContent = banner ? 'تعديل البنر' : 'بنر جديد';
  if (banner) {
    styleInput.value = banner.banner_style;
    titleInput.value = banner.title || '';
    subtitleInput.value = banner.subtitle || '';
    ctaInput.value = banner.cta_text || '';
    altInput.value = banner.alt_text || '';
    linkTypeInput.value = banner.link_type;
    if (banner.link_type === 'page') pageSelect.value = banner.link_target || 'index.html';
    if (banner.link_type === 'product') productSelect.value = banner.link_target || '';
    if (banner.link_type === 'category') categorySelect.value = banner.link_target || '';
    if (banner.link_type === 'url') urlInput.value = banner.link_target || '';
    waMessageInput.value = banner.whatsapp_message || '';
    $('ovdInput').value = banner.overlay_position_desktop || 'right';
    $('ovmInput').value = banner.overlay_position_mobile || 'top';
    activeInput.value = String(banner.is_active);
    hideDisabledInput.value = String(banner.hide_if_target_inactive);
    $('statusInput').value = banner.status === 'draft' ? 'draft' : 'published';
    // Khartoum is UTC+2 with no DST: convert the stored UTC instant for the input.
    const toLocal = BU.utcToKhartoum;
    startInput.value = toLocal(banner.starts_at);
    endInput.value = toLocal(banner.ends_at);
    state.slots.desktop.url = banner.image_desktop_url;
    state.slots.mobile.url = banner.image_mobile_url || '';
    $('desktopSlotState').textContent = 'الحالية: ' + banner.image_desktop_url;
    if (banner.image_mobile_url) $('mobileSlotState').textContent = 'الحالية: ' + banner.image_mobile_url;
  }
  updateCounters();
  syncStyleFields();
  syncLinkFields();
  if (!formModal.open) formModal.showModal();
  formModal.classList.add('show');
}
function closeForm() { formModal.close(); formModal.classList.remove('show'); state.editing = null; state.previewUrls.forEach(URL.revokeObjectURL); state.previewUrls = []; }

function updateCounters() {
  [[titleInput, 'titleCounter', 45], [subtitleInput, 'subtitleCounter', 90], [ctaInput, 'ctaCounter', 20]]
    .forEach(([input, id, max]) => {
      const c = $(id);
      c.textContent = input.value.length + ' / ' + max;
      c.classList.toggle('over', input.value.length > max);
    });
}

function syncStyleFields() {
  const hasText = styleInput.value === 'image_text';
  document.querySelectorAll('#textFields > .field').forEach((f) => { f.hidden = !hasText; });
  $('overlayRow').hidden = !hasText;
}

function syncLinkFields() {
  const t = linkTypeInput.value;
  show($('pageField'), t === 'page');
  show($('productField'), t === 'product');
  show($('categoryField'), t === 'category');
  show($('urlField'), t === 'url');
  show($('whatsappField'), t === 'whatsapp');
  renderPreview();
}

function currentPayload() {
  const t = linkTypeInput.value;
  let target = null;
  if (t === 'page') target = pageSelect.value;
  else if (t === 'product') target = productSelect.value || null;
  else if (t === 'category') target = categorySelect.value || null;
  else if (t === 'url') target = urlInput.value.trim();
  // The datetime-local value is Khartoum wall time (UTC+2); store the true UTC instant.
  const toIso = BU.khartoumToUtc;
  return {
    banner_style: styleInput.value,
    status: $('statusInput').value,
    title: titleInput.value.trim() || null,
    subtitle: subtitleInput.value.trim() || null,
    cta_text: ctaInput.value.trim() || null,
    alt_text: altInput.value.trim(),
    image_desktop_url: state.slots.desktop.url || '',
    image_mobile_url: state.slots.mobile.url || null,
    link_type: t,
    link_target: target,
    whatsapp_message: waMessageInput.value.trim() || null,
    overlay_position_desktop: $('ovdInput').value,
    overlay_position_mobile: $('ovmInput').value,
    hide_if_target_inactive: hideDisabledInput.value === 'true',
    is_active: activeInput.value === 'true',
    starts_at: toIso(startInput.value),
    ends_at: toIso(endInput.value),
    sort_order: state.editing ? state.editing.sort_order : (state.banners.length + 1)
  };
}

/* المعاينة تستخدم نفس باني الشرائح الذي يستخدمه الموقع */
function renderPreview() {
  const frame = $('pvFrame');
  blank(frame);
  let payload;
  try { payload = currentPayload(); } catch (_) { frame.appendChild(el('p', 'slot-note', 'تحقق من تاريخ الجدولة.')); return; }
  state.previewUrls.forEach(URL.revokeObjectURL); state.previewUrls = [];
  function previewUrl(blob) { const url = URL.createObjectURL(blob); state.previewUrls.push(url); return url; }
  if (!payload.image_desktop_url && state.slots.desktop.blob) {
    payload.image_desktop_url = previewUrl(state.slots.desktop.blob);
  }
  const isMobile = state.pvView === 'mobile';
  if (isMobile) {
    if (!payload.image_mobile_url && state.slots.mobile.blob) {
      payload.image_mobile_url = previewUrl(state.slots.mobile.blob);
    }
    if (!payload.image_mobile_url) {
      payload.image_mobile_url = payload.image_desktop_url;
    }
  }
  if (!payload.image_desktop_url) {
    frame.appendChild(el('div', 'slot-note', 'اختر صورة لعرض المعاينة.'));
    return;
  }
  var ratioMap = BU.ratios;
  frame.style.aspectRatio = isMobile ? (ratioMap[state.mobileRatio] || '16 / 9') : '3 / 1';
  $('pvStage').classList.toggle('is-mobile', isMobile);
  const slide = window.MeemBanners.buildSlide(payload, 0, { preview: true, view: state.pvView });
  if (!slide) { frame.appendChild(el('div', 'slot-note', 'تعذر بناء المعاينة.')); return; }
  frame.appendChild(slide);
}

/* ---------- الحفظ ---------- */
function uniqueName(prefix) {
  // Unique per upload (uuid when available) so a re-upload never serves a stale cache.
  const id = (window.crypto && typeof window.crypto.randomUUID === 'function')
    ? window.crypto.randomUUID()
    : (Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10));
  return prefix + '-' + id + '.webp';
}

async function uploadBlob(blob, kind) {
  const path = uniqueName(kind);
  const { error } = await supabaseClient.storage.from('banners').upload(path, blob, { contentType: 'image/webp' });
  if (error) throw new Error('فشل رفع الصورة: ' + error.message);
  const { data } = supabaseClient.storage.from('banners').getPublicUrl(path);
  return data.publicUrl;
}

async function save() {
  formError.textContent = '';
  const btn = $('formSaveBtn');
  if (btn.disabled) return;
  btn.disabled = true;
  try {
    const draft = currentPayload();
    if (draft.status === 'published' && !draft.alt_text) throw new Error('ALT_REQUIRED');
    if (draft.starts_at && draft.ends_at && draft.ends_at <= draft.starts_at) throw new Error('INVALID_SCHEDULE');
    const d = state.slots.desktop, m = state.slots.mobile;
    if (d.img) { d.url = await uploadBlob(await exportSlot('desktop'), 'desktop'); }
    else if (!d.url) throw new Error('اختر صورة الديسكتوب أولاً');

    if (m.img) {
      m.url = await uploadBlob(await exportSlot('mobile'), 'mobile');
    } else if (!m.url) {
      if (!d.img) throw new Error('لا يمكن توليد صورة الموبايل بدون صورة ديسكتوب جديدة');
      const canvas = $('mobileCanvas');
      drawSlot(canvas, d.img, slotBox('mobile'), d.mode, d.fx, d.fy);
      const blob = await canvasToWebp(canvas);
      if (blob.size > MAX_BYTES) throw new Error('صورة الموبايل المولَّدة أكبر من 300KB');
      m.url = await uploadBlob(blob, 'mobile');
    }

    const payload = currentPayload();
    const { error } = await supabaseClient.rpc('admin_save_banner', {
      p_id: state.editing ? state.editing.id : null,
      p_payload: payload
    });
    if (error) throw new Error(error.message);
    closeForm();
    await loadBanners();
  } catch (e) {
    const map = {
      TITLE_REQUIRED: 'العنوان مطلوب لنمط "صورة + نص".',
      TITLE_TOO_LONG: 'العنوان أطول من 45 حرفاً.',
      SUBTITLE_TOO_LONG: 'النص الفرعي أطول من 90 حرفاً.',
      CTA_TOO_LONG: 'نص الزر أطول من 20 حرفاً.',
      INVALID_URL: 'الرابط الخارجي يجب أن يبدأ بـ https:// ويكون صالحاً.',
      PAGE_NOT_ALLOWED: 'الصفحة المختارة غير مسموحة.',
      PRODUCT_NOT_FOUND: 'المنتج غير موجود.',
      CATEGORY_NOT_FOUND: 'القسم غير موجود.',
      ALT_REQUIRED: 'النص البديل (alt) إلزامي قبل النشر.',
      INVALID_SCHEDULE: 'أدخل مواعيد صحيحة، على أن يكون الانتهاء بعد البداية بتوقيت الخرطوم.',
      INVALID_STATUS: 'حالة البنر غير صحيحة.',
      INVALID_IMAGE_DESKTOP_URL: 'رابط الصورة يجب أن يكون داخل مجلد المشروع (assets/banners) أو تخزين المشروع.',
      INVALID_IMAGE_MOBILE_URL: 'رابط صورة الموبايل غير مقبول.',
      PERMISSION_REQUIRED: 'لا تملك صلاحية إدارة الإعدادات.',
      ADMIN_REQUIRED: 'صلاحيتك كمشرف لم تعد فعّالة — أعد تحميل الصفحة.'
    };
    formError.textContent = map[(e.message || '').trim()] || e.message || 'تعذر الحفظ';
  } finally {
    btn.disabled = false;
  }
}

/* ---------- التهيئة ---------- */
async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }
  const { data: profile, error: profileError } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).maybeSingle();
  if (profileError || !profile || profile.role !== 'admin' || profile.is_banned === true) {
    $('accessDenied').classList.add('show');
    return;
  }
  const { data: canManage, error: permError } = await supabaseClient
    .rpc('has_admin_permission', { permission_key: 'manage_settings' });
  if (permError || canManage !== true) { $('accessDenied').classList.add('show'); return; }

  $('adminPage').style.display = 'block';

  $('addNewBtn').addEventListener('click', () => openForm(null));
  $('formCancelBtn').addEventListener('click', closeForm);
  formModal.addEventListener('cancel', event => { event.preventDefault(); closeForm(); });
  $('formSaveBtn').addEventListener('click', save);
  $('desktopPickBtn').addEventListener('click', () => $('desktopFileInput').click());
  $('mobilePickBtn').addEventListener('click', () => $('mobileFileInput').click());
  $('desktopFileInput').addEventListener('change', async (e) => {
    const f = e.target.files && e.target.files[0];
    if (!f) return;
    try { await pickFile('desktop', f); await exportSlot('desktop'); renderPreview(); }
    catch (err) { formError.textContent = err.message; }
  });
  $('mobileFileInput').addEventListener('change', async (e) => {
    const f = e.target.files && e.target.files[0];
    if (!f) return;
    try { await pickFile('mobile', f); await exportSlot('mobile'); renderPreview(); }
    catch (err) { formError.textContent = err.message; }
  });
  bindCrop('desktop');
  bindCrop('mobile');
  [titleInput, subtitleInput, ctaInput].forEach((i) => i.addEventListener('input', () => { updateCounters(); renderPreview(); }));
  [altInput, urlInput, waMessageInput, $('ovdInput'), $('ovmInput')].forEach((i) => {
    i.addEventListener('input', renderPreview);
    i.addEventListener('change', renderPreview);
  });
  [styleInput, linkTypeInput].forEach((i) => i.addEventListener('change', () => { syncStyleFields(); syncLinkFields(); }));
  [pageSelect, productSelect, categorySelect].forEach((i) => i.addEventListener('change', syncLinkFields));
  $('pvToggle').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-view]');
    if (!btn) return;
    state.pvView = btn.dataset.view;
    [...$('pvToggle').querySelectorAll('button')].forEach((b) => b.classList.toggle('active', b === btn));
    renderPreview();
  });

  await loadRatioSetting();

  await loadRefData();
  await loadBanners();
}
init();
