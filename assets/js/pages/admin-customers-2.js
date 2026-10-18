let allCustomers = [];
let currentUserId = null;

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
  render();
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
          </div>
        </div>
        <div class="admin-order-actions">
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
}

async function toggleBan(id, currentlyBanned) {
  const action = currentlyBanned ? 'إلغاء حظر' : 'حظر';
  if (!confirm(`متأكد عايز ${action} هذا العميل؟`)) return;
  const { error } = await supabaseClient.rpc('admin_set_customer_banned', { p_profile_id: id, p_banned: !currentlyBanned });
  if (error) { alert('تعذر تنفيذ العملية أو ليست لديك صلاحية إدارة المشرفين.'); return; }
  await loadCustomers();
}

init();
