const permissionFields = [
  ['can_manage_orders','إدارة الطلبات','clipboard-list'],
  ['can_manage_wallets','إدارة المحافظ','wallet'],
  ['can_manage_products','إدارة المنتجات','package-open'],
  ['can_manage_settings','إدارة الإعدادات','sliders-horizontal'],
  ['can_manage_maintenance','وضع الصيانة','wrench'],
  ['can_manage_admins','إدارة المشرفين','shield-user'],
  ['can_manage_coupons','إدارة الكوبونات','ticket'],
  ['can_manage_gift_cards','إدارة كروت الهدايا','gift'],
  ['can_view_audit_logs','عرض سجل النشاطات','history']
];
let staff = [];

function toast(message, error = false) {
  let box = document.getElementById('staffToast');
  if (!box) { box = document.createElement('div'); box.id = 'staffToast'; box.setAttribute('role','alert'); box.style.cssText='position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:9999;padding:12px 16px;border-radius:12px;max-width:90vw;text-align:center;font-size:13px;'; document.body.appendChild(box); }
  box.textContent = message; box.style.background = error ? 'var(--danger)' : 'var(--bg-card)'; box.style.color = error ? '#fff' : 'var(--ink)'; box.style.border = `1px solid ${error ? 'var(--danger)' : 'var(--border)'}`; box.style.display='block'; clearTimeout(toast.t); toast.t=setTimeout(()=>box.style.display='none',4000);
}
function permissionMarkup(id, perms) {
  const allChecked = !!perms?.is_super_admin;
  return `<label class="permission-item permission-all"><input type="checkbox" data-perm="all" ${allChecked ? 'checked' : ''}> كل الصلاحيات</label>` + permissionFields.map(([key,label,icon]) => `<label class="permission-item"><input type="checkbox" data-perm="${key}" ${allChecked || perms?.[key] ? 'checked' : ''}> ${window.rzIconMarkup(icon)} ${label}</label>`).join('');
}
function normalizePermissionRow(row) {
  return row || {};
}

function getStaffErrorMessage(error) {
  const message = String(error?.message || '').toLowerCase();
  if (message.includes('permission denied') || message.includes('row-level security') || message.includes('rls')) return 'ليس لديك صلاحية قراءة بيانات الفريق. تأكد من حساب السوبر أدمن وسياسات RLS.';
  if (message.includes('does not exist') || message.includes('schema cache') || message.includes('relationship')) return 'لم يتم تحديث مخطط Supabase بعد. شغّل migration الإدارة ثم اضغط إعادة المحاولة.';
  return 'تعذر تحميل قائمة الفريق. اضغط إعادة المحاولة أو راجع سجل الأخطاء.';
}

function render() {
  const container = document.getElementById('staffList');
  if (!staff.length) { container.innerHTML = '<div style="color: var(--text-muted);text-align: center;padding: 30px;">لا يوجد مشرفون بعد.</div>'; return; }
  container.innerHTML = staff.map((person) => {
    const perms = person.admin_permissions?.[0] || person.admin_permissions || {};
    const isSuper = !!perms.is_super_admin;
    return `<article class="staff-card" data-id="${escapeAttribute(person.id)}">
      <div class="staff-card-head"><div><div class="staff-name">${escapeHtml(person.full_name || 'بدون اسم')} ${isSuper ? '<span class="inactive-badge">سوبر أدمن</span>' : ''}</div><div class="staff-meta">${escapeHtml(person.whatsapp_number || '—')} · ${person.role === 'admin' ? 'مشرف' : 'عميل'}</div></div><select class="staff-role" data-role><option value="admin" ${person.role === 'admin' ? 'selected' : ''}>مشرف</option><option value="customer" ${person.role !== 'admin' ? 'selected' : ''}>عميل</option></select></div>
      <div class="permission-grid">${permissionMarkup(person.id, perms)}</div>
      <div class="staff-actions"><button class="btn-confirm" data-save><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-save"></use></svg> حفظ الصلاحيات</button></div>
    </article>`;
  }).join('');
  container.querySelectorAll('[data-perm="all"]').forEach((toggle) => toggle.addEventListener('change', () => { const card=toggle.closest('.staff-card'); card.querySelectorAll('[data-perm]').forEach(input => input.checked=toggle.checked); }));
  container.querySelectorAll('[data-save]').forEach((button) => button.addEventListener('click', () => saveStaff(button.closest('.staff-card'))));
}
async function saveStaff(card) {
  const role = card.querySelector('[data-role]').value;
  const permissions = { all: !!card.querySelector('[data-perm="all"]').checked };
  card.querySelectorAll('[data-perm]:not([data-perm="all"])').forEach(input => { permissions[input.dataset.perm] = input.checked; });
  const button = card.querySelector('[data-save]'); button.disabled=true; button.textContent='جارِ الحفظ...';
  const { error } = await supabaseClient.rpc('admin_set_staff_permissions', { p_profile_id: card.dataset.id, p_role: role, p_permissions: permissions });
  button.disabled=false; button.innerHTML='<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-save"></use></svg> حفظ الصلاحيات';
  if (error) { toast(String(error.message || '').includes('super admin') ? 'تحتاج صلاحية السوبر أدمن.' : 'تعذر حفظ الصلاحيات.', true); return; }
  toast('تم حفظ صلاحيات المشرف وتسجيل العملية.'); await loadStaff();
}
async function loadStaff() {
  const container = document.getElementById('staffList');
  container.innerHTML = '<div style="color: var(--text-muted);font-size: 13px;text-align: center;padding: 30px 0;"><svg class="mm-i mm-spin" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-loader"></use></svg> جارِ التحميل...</div>';

  const [profilesResponse, permissionsResponse] = await Promise.all([
    supabaseClient.from('profiles').select('id, full_name, whatsapp_number, role, is_banned, created_at').order('created_at', { ascending: false }),
    supabaseClient.from('admin_permissions').select('profile_id, is_super_admin, can_manage_orders, can_manage_wallets, can_manage_products, can_manage_settings, can_manage_maintenance, can_manage_admins, can_manage_coupons, can_manage_gift_cards, can_view_audit_logs')
  ]);

  if (profilesResponse.error || permissionsResponse.error) {
    const error = profilesResponse.error || permissionsResponse.error;
    devLog('[MEEM] staff load error:', error);
    container.innerHTML = `<div class="admin-error-state"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-triangle-alert"></use></svg><strong>${escapeHtml(getStaffErrorMessage(error))}</strong><button type="button" class="admin-btn btn-confirm" id="retryStaffBtn"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-rotate-cw"></use></svg> إعادة المحاولة</button></div>`;
    document.getElementById('retryStaffBtn')?.addEventListener('click', loadStaff);
    return;
  }

  const permissionMap = new Map((permissionsResponse.data || []).map(row => [String(row.profile_id), normalizePermissionRow(row)]));
  staff = (profilesResponse.data || []).map(person => ({ ...person, admin_permissions: permissionMap.get(String(person.id)) || {} }));
  render();
}
async function init() {
  const { data:{session} } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href='login.html'; return; }
  const { data: superAdmin, error } = await supabaseClient.rpc('is_super_admin');
  if (error || superAdmin !== true) { document.getElementById('accessDenied').style.display='block'; return; }
  document.getElementById('adminPage').style.display='block'; await loadStaff();
}
init();
