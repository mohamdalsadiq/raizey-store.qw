let allCustomers = [];
let currentUserId = null;
let receiptUsage = new Map();
let receiptPolicy = null;

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }
  currentUserId = session.user.id;

  const { data: profile } = await supabaseClient
    .from('profiles').select('role').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin') {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  document.getElementById('searchInput').addEventListener('input', render);

  await loadCustomers();
}

async function loadCustomers() {
  const { data } = await supabaseClient
    .from('profiles')
    .select('*, wallets(balance)')
    .order('created_at', { ascending: false });

  allCustomers = data || [];
  receiptUsage = new Map();
  receiptPolicy = null;
  // The RPC enforces permission + enrolled MFA; a role label in the browser
  // never grants the ability to change policy or release a suspension.
  for (let offset = 0; offset < allCustomers.length; offset += 200) {
    const { data: scanState, error } = await supabaseClient.rpc('admin_receipt_scan_states', {
      p_users: allCustomers.slice(offset, offset + 200).map(c => c.id)
    });
    if (error) break;
    receiptPolicy = scanState?.policy || receiptPolicy;
    for (const item of scanState?.customers || []) receiptUsage.set(item.userId, item.usage);
  }
  renderReceiptPolicy();
  render();
}

function renderReceiptPolicy() {
  document.getElementById('receiptPolicyPanel')?.remove();
  if (!receiptPolicy) return;
  const panel = document.createElement('form');
  panel.id = 'receiptPolicyPanel';
  panel.className = 'manage-item';
  panel.style.cssText = 'display:block;margin-bottom:16px;padding:16px';
  const fields = [
    ['user_daily_limit', 'فحوص مكتملة لكل عميل يومياً', 1, 20],
    ['global_daily_limit', 'سقف محاولات الصور للمتجر يومياً', 1, 20000],
    ['provider_daily_limit', 'سقف استدعاءات الموديل يومياً', 1, 50000],
    ['concurrency_limit', 'عدد الفحوص المتزامنة', 1, 50]
  ];
  panel.innerHTML = '<strong>سياسة الفحص الذكي</strong><p>هذه حدود المتجر. القدرة الفعلية تعتمد أيضاً على حصة مزود الفحص.</p>' +
    fields.map(([key, label, min, max]) => `<label style="display:block;margin:8px 0">${label}
      <input name="${key}" type="number" required min="${min}" max="${max}" step="1" value="${Number(receiptPolicy[key])}"></label>`).join('') +
    '<button class="admin-btn btn-confirm" type="submit">حفظ حدود الفحص</button>';
  panel.addEventListener('submit', async event => {
    event.preventDefault();
    if (!panel.reportValidity()) return;
    const inputs = new FormData(panel), button = panel.querySelector('button');
    button.disabled = true;
    try {
      const { error } = await supabaseClient.rpc('admin_update_receipt_scan_policy', {
        p_user_limit: Number(inputs.get('user_daily_limit')),
        p_global_limit: Number(inputs.get('global_daily_limit')),
        p_provider_limit: Number(inputs.get('provider_daily_limit')),
        p_concurrency: Number(inputs.get('concurrency_limit'))
      });
      if (error) { alert('تعذر حفظ السياسة. تحقق من صلاحيتك والتحقق بخطوتين وحدود القيم.'); return; }
      await loadCustomers();
    } finally { button.disabled = false; }
  });
  document.getElementById('customersList').before(panel);
}

function render() {
  const search = document.getElementById('searchInput').value.trim().toLowerCase();
  const filtered = allCustomers.filter(c =>
    (c.full_name || '').toLowerCase().includes(search) ||
    (c.whatsapp_number || '').toLowerCase().includes(search)
  );

  const container = document.getElementById('customersList');
  if (filtered.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا يوجد نتائج</div>`;
    return;
  }

  container.innerHTML = filtered.map(c => {
    const balance = c.wallets?.balance ?? 0;
    const isSelf = c.id === currentUserId;
    const usage = receiptUsage.get(c.id);
    return `
      <div class="manage-item" style="flex-direction: column; align-items: stretch;">
        <div style="display: flex; align-items: center; gap: 12px;">
          <div class="manage-item-info">
            <div class="manage-item-name">
              ${escapeHtml(c.full_name || 'بدون اسم')}
              ${c.role === 'admin' ? '<span class="inactive-badge" style="color: var(--mm-accent-text); background: rgba(255, 212, 0,0.15);">مشرف</span>' : ''}
              ${c.is_banned ? '<span class="inactive-badge" style="color: var(--danger); background: rgba(255,77,79,0.15);">محظور</span>' : ''}
            </div>
            <div class="manage-item-sub">${escapeHtml(c.whatsapp_number || '—')} — رصيد: ${formatSDG(balance)} ج.س</div>
            ${usage ? `<div class="manage-item-sub">الفحص اليوم: ${Number(usage.usedToday)} من ${Number(usage.dailyLimit)} — مخالفات: ${Number(usage.violations)} من ${Number(usage.violationLimit)}${usage.suspended ? ' — الفحص مجمد' : ''}</div>` : ''}
          </div>
        </div>
        <div class="admin-order-actions">
          ${usage && c.role === 'customer' ? `<button class="admin-btn ${usage.suspended ? 'btn-confirm' : 'btn-reject'}" data-action="receipt-suspension" data-id="${c.id}" data-suspended="${usage.suspended}">${usage.suspended ? 'فك تجميد الفحص' : 'تجميد الفحص'}</button>` : ''}
          ${!isSelf ? `
            <button class="admin-btn ${c.is_banned ? 'btn-confirm' : 'btn-reject'}" data-action="ban" data-id="${c.id}" data-banned="${c.is_banned}">
              ${c.is_banned ? 'إلغاء الحظر' : 'حظر'}
            </button>
            <a class="admin-btn btn-complete" href="admin-staff.html" style="display: inline-flex;align-items: center;justify-content: center;text-decoration: none;">${c.role === 'admin' ? 'إدارة الصلاحيات' : 'تعيين كمشرف'}</a>
          ` : '<div style="font-size: 12px; color: var(--text-muted); padding: 8px;">هذا حسابك</div>'}
        </div>
      </div>
    `;
  }).join('');

  container.querySelectorAll('[data-action="ban"]').forEach(btn => {
    btn.addEventListener('click', () => toggleBan(btn.dataset.id, btn.dataset.banned === 'true'));
  });
  container.querySelectorAll('[data-action="receipt-suspension"]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const suspended = btn.dataset.suspended !== 'true';
      const reason = prompt(suspended ? 'اكتب سبب تجميد ميزة الفحص (6 أحرف على الأقل):' : 'اكتب سبب فك التجميد بعد مراجعة الحالة (6 أحرف على الأقل):');
      if (reason === null) return;
      if (reason.trim().length < 6 || reason.trim().length > 500) { alert('السبب يجب أن يكون بين 6 و500 حرف.'); return; }
      btn.disabled = true;
      try {
        const { error } = await supabaseClient.rpc('admin_set_receipt_scan_suspension', {
          p_user: btn.dataset.id, p_suspended: suspended, p_reason: reason.trim()
        });
        if (error) { alert('تعذر تعديل التجميد. تحقق من صلاحيتك والتحقق بخطوتين.'); return; }
        await loadCustomers();
      } finally { btn.disabled = false; }
    });
  });
}

async function toggleBan(id, currentlyBanned) {
  const action = currentlyBanned ? 'إلغاء حظر' : 'حظر';
  if (!confirm(`متأكد عايز ${action} هذا العميل؟`)) return;
  const { error } = await supabaseClient.rpc('admin_set_customer_banned', { p_profile_id: id, p_banned: !currentlyBanned });
  if (error) { alert('تعذر تنفيذ العملية أو ليست لديك صلاحية إدارة المشرفين.'); return; }
  await loadCustomers();
}

init();
