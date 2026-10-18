let codes = [];
let currentFilter = 'all';
let currentAdminId = null;

const formModal      = document.getElementById('formModal');
const amountInput    = document.getElementById('amountInput');
const noteInput      = document.getElementById('noteInput');
const customerInput  = document.getElementById('customerInput');
const customerHint   = document.getElementById('customerHint');
const expiresInput   = document.getElementById('expiresInput');
const formError      = document.getElementById('formError');

const stateLabels = { active: 'نشط', used: 'مستخدم', expired: 'منتهٍ', cancelled: 'ملغى' };

function genCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // بلا حروف/أرقام متشابهة
  const rnd = (n) => {
    const buf = new Uint32Array(n);
    (window.crypto || window.msCrypto).getRandomValues(buf);
    return Array.from(buf, v => alphabet[v % alphabet.length]).join('');
  };
  return `MEEM-${rnd(4)}-${rnd(4)}`;
}

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }
  const { data: canManageSettings, error: permissionError } = await supabaseClient.rpc('has_admin_permission', { permission_key: 'manage_settings' });
  if (permissionError || canManageSettings !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }
  currentAdminId = session.user.id;
  document.getElementById('adminPage').style.display = 'block';

  document.getElementById('addNewBtn').addEventListener('click', openForm);
  document.getElementById('formCancelBtn').addEventListener('click', closeForm);
  document.getElementById('formSaveBtn').addEventListener('click', saveCode);

  document.querySelectorAll('.chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      currentFilter = chip.dataset.filter;
      render();
    });
  });

  await loadCodes();
}

async function loadCodes() {
  const { data, error } = await supabaseClient
    .from('payment_codes')
    .select('*, used_profile:profiles!payment_codes_used_by_fkey(full_name, whatsapp_number), target_profile:profiles!payment_codes_user_id_fkey(full_name, whatsapp_number)')
    .order('created_at', { ascending: false });

  if (error) {
    const fb = await supabaseClient.from('payment_codes').select('*').order('created_at', { ascending: false });
    codes = fb.data || [];
  } else {
    codes = data || [];
  }
  render();
}

function effectiveState(c) {
  if (c.status === 'active' && c.expires_at && new Date(c.expires_at) < new Date()) return 'expired';
  return c.status;
}

function render() {
  const list = document.getElementById('codesList');
  const filtered = currentFilter === 'all' ? codes : codes.filter(c => effectiveState(c) === currentFilter);

  if (!filtered.length) {
    list.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد رموز مطابقة</div>`;
    return;
  }

  list.innerHTML = filtered.map(c => {
    const st = effectiveState(c);
    const stKnown = Object.prototype.hasOwnProperty.call(stateLabels, st);
    const stKey = stKnown ? st : 'unknown';
    const created = new Date(c.created_at).toLocaleDateString('ar-EG', { year:'numeric', month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' });
    const usedAt = c.used_at ? new Date(c.used_at).toLocaleDateString('ar-EG', { year:'numeric', month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' }) : null;
    const target = c.target_profile;
    const user = c.used_profile;
    return `
      <div class="code-card">
        <div style="display: flex; align-items: center; justify-content: space-between; gap: 10px;">
          <span class="code-value">${escapeHtml(c.code)}</span>
          <span class="code-state state-${stKey}">${stKnown ? stateLabels[st] : escapeHtml(st)}</span>
        </div>
        <div class="code-meta">
          المبلغ: <strong>${formatSDG(c.amount)} ج.س</strong><br>
          ${c.note ? `ملاحظة: ${escapeHtml(c.note)}<br>` : ''}
          ${target ? `مخصص لـ: ${escapeHtml(target.full_name || '')} — ${escapeHtml(target.whatsapp_number || '')}<br>` : ''}
          أُنشئ: ${created}<br>
          ${c.expires_at ? `ينتهي: ${new Date(c.expires_at).toLocaleDateString('ar-EG')}<br>` : ''}
          ${usedAt ? `استُخدم: ${usedAt}${user ? ` — ${escapeHtml(user.full_name || '')} (${escapeHtml(user.whatsapp_number || '')})` : ''}<br>` : ''}
          ${c.order_id ? `الطلب: ${escapeHtml(String(c.order_id).slice(0, 8))}<br>` : ''}
        </div>
        <div class="admin-order-actions" style="margin-top: 10px;">
          <button class="admin-btn" data-copy="${safeDataAttr(c.code)}">نسخ الرمز</button>
          ${st === 'active' ? `<button class="admin-btn btn-reject" data-cancel="${safeDataAttr(c.id)}">إلغاء</button>` : ''}
        </div>
      </div>`;
  }).join('');

  list.querySelectorAll('[data-copy]').forEach(btn => {
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(btn.dataset.copy);
        const t = btn.textContent; btn.textContent = 'تم';
        setTimeout(() => { btn.textContent = t; }, 1500);
      } catch (e) {}
    });
  });

  list.querySelectorAll('[data-cancel]').forEach(btn => {
    btn.addEventListener('click', async () => {
      if (!confirm('إلغاء هذا الرمز نهائياً؟')) return;
      const { error } = await supabaseClient.rpc('admin_cancel_payment_code', { p_code_id: btn.dataset.cancel });
      if (error) { alert('تعذّر إلغاء الرمز: ' + getFriendlyError(error)); return; }
      await loadCodes();
    });
  });
}

function openForm() {
  amountInput.value = '';
  noteInput.value = '';
  customerInput.value = '';
  customerHint.textContent = '';
  expiresInput.value = '';
  formError.textContent = '';
  formModal.classList.add('show');
}

function closeForm() { formModal.classList.remove('show'); }

async function resolveCustomer(phone) {
  const q = phone.trim();
  if (!q) return null;
  const { data } = await supabaseClient
    .from('profiles').select('id, full_name, whatsapp_number')
    .ilike('whatsapp_number', `%${q}%`).limit(2);
  if (!data || data.length !== 1) return 'not_found';
  return data[0];
}

async function saveCode() {
  formError.textContent = '';
  const amount = Number(amountInput.value);
  if (!amount || amount <= 0) { formError.textContent = 'اكتب مبلغاً صحيحاً.'; return; }

  let userId = null;
  if (customerInput.value.trim()) {
    const found = await resolveCustomer(customerInput.value);
    if (found === 'not_found' || !found) {
      formError.textContent = 'لم يُعثر على عميل واحد بهذا الرقم. اترك الحقل فارغاً أو اكتب الرقم كاملاً.';
      return;
    }
    userId = found.id;
    customerHint.textContent = `العميل: ${found.full_name || ''}`;
  }

  const payload = {
    code: genCode(),
    amount,
    note: noteInput.value.trim() || null,
    user_id: userId,
    expires_at: expiresInput.value ? new Date(expiresInput.value + 'T23:59:59').toISOString() : null,
    status: 'active',
    created_by: currentAdminId
  };

  const { error } = await supabaseClient.from('payment_codes').insert(payload);
  if (error) { formError.textContent = 'تعذّر توليد الرمز: ' + error.message; return; }

  await supabaseClient.from('audit_logs').insert({
    admin_id: currentAdminId, action: 'توليد رمز دفع',
    details: { code: payload.code, amount, note: payload.note }
  });

  closeForm();
  await loadCodes();
}

init();
