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

  const { data: settingsRows } = await supabaseClient
    .from('settings')
    .select('key, value')
    .in('key', ['usd_to_sdg_rate', 'profit_margin_percent', 'whatsapp_number']);

  const map = {};
  (settingsRows || []).forEach(r => { map[r.key] = r.value; });

  document.getElementById('rateInput').value = map.usd_to_sdg_rate || '';
  document.getElementById('marginInput').value = map.profit_margin_percent || '0';
  document.getElementById('whatsappInput').value = map.whatsapp_number || '';

  document.getElementById('saveBtn').addEventListener('click', saveRate);
}

let currentAdminId = null;

async function saveRate() {
  const errorBox = document.getElementById('formError');
  const successBox = document.getElementById('formSuccess');
  errorBox.textContent = '';
  successBox.textContent = '';

  const rate = parseFloat(document.getElementById('rateInput').value);
  const margin = parseFloat(document.getElementById('marginInput').value) || 0;

  if (!rate || rate <= 0) {
    errorBox.textContent = 'أدخل سعر صرف صحيح';
    return;
  }

  const whatsapp = (document.getElementById('whatsappInput').value || '').replace(/[^0-9]/g, '');
  if (!Number.isFinite(rate) || !Number.isFinite(margin) || margin <= -100 || (whatsapp && !/^[0-9]{8,15}$/.test(whatsapp))) {
    errorBox.textContent = 'راجع سعر الصرف والهامش ورقم واتساب قبل الحفظ.';
    return;
  }
  try {
    const { error } = await supabaseClient.rpc('save_store_settings', { p_rate: rate, p_margin: margin, p_whatsapp: whatsapp || null });
    if (error) throw error;
    successBox.textContent = 'تم حفظ الإعدادات بنجاح';
  } catch (error) {
    errorBox.textContent = getFriendlyError(error?.message);
  }

}

init();
