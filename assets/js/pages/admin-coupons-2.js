let coupons = [];
let editingId = null;

const formModal = document.getElementById('formModal');
const codeInput = document.getElementById('codeInput');
const generateCodeBtn = document.getElementById('generateCodeBtn');
const discountInput = document.getElementById('discountInput');
const maxUsesInput = document.getElementById('maxUsesInput');
const expiresInput = document.getElementById('expiresInput');
const activeInput = document.getElementById('activeInput');
const formError = document.getElementById('formError');

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }
  const { data: canManageCoupons, error: permissionError } = await supabaseClient.rpc('has_admin_permission', { permission_key: 'manage_coupons' });
  if (permissionError || canManageCoupons !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  document.getElementById('addNewBtn').addEventListener('click', () => openForm(null));
  document.getElementById('formCancelBtn').addEventListener('click', closeForm);
  document.getElementById('formSaveBtn').addEventListener('click', saveCoupon);

  await loadCoupons();
}

async function loadCoupons() {
  const { data } = await supabaseClient.from('coupons').select('*').order('created_at', { ascending: false });
  coupons = data || [];
  render();
}

function render() {
  const container = document.getElementById('couponsList');
  if (coupons.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد كوبونات بعد</div>`;
    return;
  }

  container.innerHTML = coupons.map(c => `
    <div class="manage-item">
      <div class="manage-item-info">
        <div class="manage-item-name">
          ${escapeHtml(c.code)}
          ${!c.is_active ? '<span class="inactive-badge">معطّل</span>' : ''}
        </div>
        <div class="manage-item-sub">
          خصم ${c.discount_percent}% — استُخدم ${c.uses_count}${c.max_uses ? ' / ' + c.max_uses : ''}
          ${c.expires_at ? ' — ينتهي ' + new Date(c.expires_at).toLocaleDateString('ar-EG') : ''}
        </div>
      </div>
      <div class="manage-item-actions">
        <button class="icon-action-btn" data-action="edit" data-id="${c.id}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-pen"></use></svg></button>
        <button class="icon-action-btn" data-action="delete" data-id="${c.id}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg></button>
      </div>
    </div>
  `).join('');

  container.querySelectorAll('[data-action="edit"]').forEach(btn => {
    btn.addEventListener('click', () => openForm(btn.dataset.id));
  });
  container.querySelectorAll('[data-action="delete"]').forEach(btn => {
    btn.addEventListener('click', () => deleteCoupon(btn.dataset.id));
  });
}

function openForm(id) {
  editingId = id;
  formError.textContent = '';

  if (id) {
    const c = coupons.find(x => x.id === id);
    document.getElementById('formModalTitle').textContent = 'تعديل الكوبون';
    codeInput.value = c.code;
    discountInput.value = c.discount_percent;
    maxUsesInput.value = c.max_uses || '';
    expiresInput.value = c.expires_at ? c.expires_at.slice(0, 10) : '';
    activeInput.value = String(c.is_active);
  } else {
    document.getElementById('formModalTitle').textContent = 'كوبون جديد';
    codeInput.value = '';
    discountInput.value = '';
    maxUsesInput.value = '';
    expiresInput.value = '';
    activeInput.value = 'true';
  }

  formModal.classList.add('show');
}

function closeForm() {
  formModal.classList.remove('show');
  editingId = null;
}

function generateCouponCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  let out = '';
  for (let i = 0; i < 12; i += 1) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

generateCodeBtn.addEventListener('click', () => {
  codeInput.value = generateCouponCode();
  formError.textContent = '';
});

async function saveCoupon() {
  const code = codeInput.value.trim().toUpperCase();
  const discount = parseFloat(discountInput.value);
  const maxUses = maxUsesInput.value ? parseInt(maxUsesInput.value) : null;
  const expiresAt = expiresInput.value ? new Date(expiresInput.value).toISOString() : null;

  if (!code) { formError.textContent = 'أدخل كود الكوبون'; return; }
  if (code.replace(/[^A-Za-z0-9]/g, '').length < 10) {
    formError.textContent = 'كود الكوبون يجب أن يكون 10 خانات أبجدية-رقمية على الأقل';
    return;
  }
  if (!discount || discount <= 0 || discount > 100) { formError.textContent = 'أدخل نسبة خصم صحيحة (1-100)'; return; }

  const payload = {
    code,
    discount_percent: discount,
    max_uses: maxUses,
    expires_at: expiresAt,
    is_active: activeInput.value === 'true'
  };

  const { error } = editingId
    ? await supabaseClient.from('coupons').update(payload).eq('id', editingId)
    : await supabaseClient.from('coupons').insert(payload);

  if (error) {
    formError.textContent = error.message.includes('duplicate') ? 'الكود ده مستخدم بالفعل' : 'حصل خطأ، حاول تاني';
    return;
  }

  closeForm();
  await loadCoupons();
}

async function deleteCoupon(id) {
  if (!confirm('متأكد عايز تحذف الكوبون ده؟')) return;
  const { error } = await supabaseClient.from('coupons').delete().eq('id', id);
  if (error) { alert('تعذّر حذف الكوبون: ' + getFriendlyError(error)); return; }
  await loadCoupons();
}

init();
