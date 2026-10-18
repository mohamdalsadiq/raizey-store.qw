let methods = [];
let editingId = null;
let currentAdminId = null;

// سجل نشاط للأدمن — يُكتب في القاعدة عبر دالة SECURITY DEFINER
async function logAudit(action, targetId, details) {
  try {
    const { error } = await supabaseClient.rpc('append_admin_audit_log', {
      p_action: action,
      p_target_table: 'payment_methods',
      p_target_id: targetId ? String(targetId) : null,
      p_details: details || {}
    });
    if (error) throw error;
  } catch (e) {
    // السجل الاحتياطي في audit_logs حتى لا تمر العملية بدون تسجيل
    try {
      await supabaseClient.from('audit_logs').insert({
        admin_id: currentAdminId, action, details: { payment_method_id: targetId, ...(details || {}) }
      });
    } catch (err) {
      devWarn('[MEEM] audit log failed');
    }
  }
}

const formModal = document.getElementById('formModal');
const nameInput = document.getElementById('nameInput');
const accountNameInput = document.getElementById('accountNameInput');
const accountNumberInput = document.getElementById('accountNumberInput');
const binInput = document.getElementById('binInput');
const bankKeyInput = document.getElementById('bankKeyInput');
const instructionsInput = document.getElementById('instructionsInput');
const orderInput = document.getElementById('orderInput');
const activeInput = document.getElementById('activeInput');
const formError = document.getElementById('formError');
const iconUploadBox = document.getElementById('iconUploadBox');
const iconFileInput = document.getElementById('iconFileInput');
const iconUploadLabel = document.getElementById('iconUploadLabel');
const iconUrlInput = document.getElementById('iconUrlInput');
const iconPreviewWrap = document.getElementById('iconPreviewWrap');
const iconPreview = document.getElementById('iconPreview');
const iconRemoveBtn = document.getElementById('iconRemoveBtn');

// ── أيقونة وسيلة الدفع: رفع إلى Supabase Storage + معاينة + إزالة ──────────
function setIconLabel(text) { iconUploadLabel.textContent = text || 'اضغط لرفع أيقونة (PNG / JPG / WEBP)'; }
function setIconPreview(url) {
  const safe = typeof sanitizeUrl === 'function' ? sanitizeUrl(url) : '';
  if (safe) {
    iconUrlInput.value = safe;
    iconPreview.src = safe;
    iconPreviewWrap.style.display = 'flex';
  } else {
    iconUrlInput.value = '';
    iconPreview.removeAttribute('src');
    iconPreviewWrap.style.display = 'none';
  }
}
async function uploadIconFile(file) {
  const allowed = ['image/jpeg', 'image/png', 'image/webp'];
  if (!allowed.includes(file.type)) throw new Error('invalid_image_type');
  if (file.size > 5 * 1024 * 1024) throw new Error('image_too_large');
  const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
  const path = `payment-methods/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
  const { error } = await supabaseClient.storage.from('product-images').upload(path, file);
  if (error) throw error;
  const { data } = supabaseClient.storage.from('product-images').getPublicUrl(path);
  return data.publicUrl;
}

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile, error: profileError } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).maybeSingle();

  if (profileError || !profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  // وسائل الدفع جزء من إعدادات المتجر — نتحقق من الصلاحية في السيرفر
  const { data: canManageSettings, error: permError } = await supabaseClient
    .rpc('has_admin_permission', { permission_key: 'manage_settings' });

  if (permError || canManageSettings !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  currentAdminId = session.user.id;

  document.getElementById('adminPage').style.display = 'block';
  document.getElementById('addNewBtn').addEventListener('click', () => openForm(null));
  document.getElementById('formCancelBtn').addEventListener('click', closeForm);
  document.getElementById('formSaveBtn').addEventListener('click', saveMethod);

  iconUploadBox.addEventListener('click', () => iconFileInput.click());
  iconUploadBox.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); iconFileInput.click(); }
  });
  iconFileInput.addEventListener('change', async () => {
    const file = iconFileInput.files && iconFileInput.files[0];
    if (!file) return;
    setIconLabel('جارِ الرفع...');
    try {
      const url = await uploadIconFile(file);
      setIconPreview(url);
      setIconLabel(file.name);
    } catch (e) {
      setIconPreview('');
      iconFileInput.value = '';
      setIconLabel('فشل الرفع — اختر صورة JPG/PNG/WEBP أقل من 5MB');
    }
  });
  iconRemoveBtn.addEventListener('click', () => {
    setIconPreview('');
    iconFileInput.value = '';
    setIconLabel('');
  });

  await loadMethods();
}

async function loadMethods() {
  const { data, error } = await supabaseClient.from('payment_methods').select('*').order('display_order');
  if (error) {
    document.getElementById('methodsList').innerHTML =
      `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">تعذّر تحميل وسائل الدفع. حدّث الصفحة وحاول مجدداً.</div>`;
    return;
  }
  methods = data || [];
  render();
}

function render() {
  const container = document.getElementById('methodsList');
  if (methods.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد وسائل دفع بعد</div>`;
    return;
  }

  // كل القيم تُمرّر عبر escapeHtml / safeDataAttr لمنع XSS المخزَّن
  container.innerHTML = methods.map(m => {
    const iconUrl = typeof sanitizeUrl === 'function' ? sanitizeUrl(m.icon_url) : '';
    const iconHtml = iconUrl
      ? `<img src="${escapeAttribute(iconUrl)}" alt="" loading="lazy" style="width: 34px;height: 34px;object-fit: contain;">`
      : `<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-landmark"></use></svg>`;
    return `
    <div class="manage-item">
      <div class="manage-item-info">
        <div class="manage-item-thumb" aria-hidden="true" style="width: 44px;height: 44px;flex: 0 0 auto;border-radius: 13px;display: grid;place-items: center;margin-left: 12px;background: var(--bg);border: 1px solid var(--border);color: var(--mm-accent-text);">${iconHtml}</div>
        <div class="manage-item-name">
          ${escapeHtml(m.name || '')}
          ${!m.is_active ? '<span class="inactive-badge">مخفي</span>' : ''}
        </div>
        <div class="manage-item-sub">${escapeHtml(m.account_name || '')} — ${escapeHtml(m.account_number || '')}${m.bank_key ? ' — <span style="color: var(--mm-accent-text); font-weight: 700;">' + escapeHtml(m.bank_key) + '</span>' : ''}${m.bin_prefixes ? ' — <span dir="ltr">' + escapeHtml(m.bin_prefixes) + '</span>' : ''}</div>
      </div>
      <div class="manage-item-actions">
        <button class="icon-action-btn" data-action="edit" data-id="${safeDataAttr(m.id || '')}" aria-label="تعديل" title="تعديل"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-pen"></use></svg></button>
        <button class="icon-action-btn" data-action="delete" data-id="${safeDataAttr(m.id || '')}" aria-label="حذف" title="حذف"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>
      </div>
    </div>
  `;
  }).join('');

  container.querySelectorAll('[data-action="edit"]').forEach(btn => {
    btn.addEventListener('click', () => openForm(btn.dataset.id));
  });
  container.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => deleteMethod(btn.dataset.id));
  });
}

function openForm(id) {
  editingId = id;
  formError.textContent = '';

  const m = id ? methods.find(x => x.id === id) : null;

  if (id && !m) { // الصف حُذف أو تغيّر من جهاز آخر
    editingId = null;
    loadMethods();
    return;
  }

  if (m) {
    document.getElementById('formModalTitle').textContent = 'تعديل وسيلة الدفع';
    nameInput.value = m.name || '';
    accountNameInput.value = m.account_name || '';
    accountNumberInput.value = m.account_number || '';
    binInput.value = m.bin_prefixes || '';
    bankKeyInput.value = m.bank_key || '';
    instructionsInput.value = m.instructions || '';
    orderInput.value = m.display_order ?? 0;
    activeInput.value = String(m.is_active === true);
    setIconPreview(m.icon_url || '');
    setIconLabel(m.icon_url ? 'استبدل الأيقونة الحالية برفع صورة جديدة' : '');
    iconFileInput.value = '';
  } else {
    document.getElementById('formModalTitle').textContent = 'وسيلة دفع جديدة';
    nameInput.value = '';
    accountNameInput.value = '';
    accountNumberInput.value = '';
    binInput.value = '';
    bankKeyInput.value = '';
    instructionsInput.value = '';
    orderInput.value = methods.length;
    activeInput.value = 'true';
    setIconPreview('');
    setIconLabel('');
    iconFileInput.value = '';
  }

  formModal.classList.add('show');
}

function closeForm() {
  formModal.classList.remove('show');
  editingId = null;
}

async function saveMethod() {
  const name = nameInput.value.trim();
  const accountName = accountNameInput.value.trim();
  const accountNumber = accountNumberInput.value.trim();

  if (!name) { formError.textContent = 'أدخل اسم الوسيلة'; return; }
  if (!accountName) { formError.textContent = 'أدخل اسم صاحب الحساب'; return; }
  if (!accountNumber) { formError.textContent = 'أدخل رقم الحساب'; return; }

  // P2-RCP-001: تحقق من صيغة BIN — كل قيمة 17 خانة رقمية (فواصل مسموحة)
  const binRaw = binInput.value.trim();
  if (binRaw) {
    const parts = binRaw.split(/[,;\s]+/).filter(Boolean);
    const invalid = parts.find(p => !/^\d{17}$/.test(p));
    if (invalid) {
      formError.textContent = 'رقم BIN غير صالح: "' + invalid.slice(0, 20) + '" — يجب أن يكون 17 خانة رقمية (مثال: 57040290563000001). افصل عدة قيم بفاصلة.';
      return;
    }
  }

  const payload = {
    name,
    account_name: accountName,
    account_number: accountNumber,
    bin_prefixes: binInput.value.trim() || null,
    bank_key: bankKeyInput.value || null,
    instructions: instructionsInput.value.trim() || null,
    icon_url: iconUrlInput.value.trim() || null,
    display_order: parseInt(orderInput.value) || 0,
    is_active: activeInput.value === 'true'
  };

  const saveBtn = document.getElementById('formSaveBtn');
  saveBtn.disabled = true;
  const originalLabel = saveBtn.textContent;
  saveBtn.textContent = 'جارِ الحفظ...';

  const wasEditing = editingId;
  const { data, error } = wasEditing
    ? await supabaseClient.from('payment_methods').update(payload).eq('id', wasEditing).select('id').maybeSingle()
    : await supabaseClient.from('payment_methods').insert(payload).select('id').maybeSingle();

  saveBtn.disabled = false;
  saveBtn.textContent = originalLabel;

  if (error) {
    formError.textContent = typeof getFriendlyError === 'function'
      ? getFriendlyError(error.message)
      : 'حصل خطأ، حاول تاني';
    return;
  }

  // لا نُسجّل رقم الحساب كاملاً في السجل — آخر 4 خانات فقط
  await logAudit(
    wasEditing ? 'تعديل وسيلة دفع' : 'إضافة وسيلة دفع',
    wasEditing || (data && data.id),
    { name, account_name: accountName, account_number_last4: accountNumber.slice(-4), is_active: payload.is_active }
  );

  closeForm();
  await loadMethods();
}

async function deleteMethod(id) {
  const m = methods.find(x => x.id === id);
  if (!confirm('متأكد عايز تحذف وسيلة الدفع دي؟')) return;

  const { error } = await supabaseClient.from('payment_methods').delete().eq('id', id);
  if (error) {
    alert('تعذّر حذف وسيلة الدفع. قد تكون مرتبطة بطلبات أو شحنات سابقة — يمكنك إخفاؤها بدل حذفها.');
    return;
  }

  await logAudit('حذف وسيلة دفع', id, {
    name: m ? m.name : null,
    account_number_last4: m && m.account_number ? String(m.account_number).slice(-4) : null
  });

  await loadMethods();
}

init();
