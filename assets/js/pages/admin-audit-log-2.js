async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }
  const { data: canViewAudit, error: permissionError } = await supabaseClient.rpc('has_admin_permission', { permission_key: 'view_audit_logs' });
  if (permissionError || canViewAudit !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  await loadLogs();
}

function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
}

function formatDetails(details) {
  if (!details || typeof details !== 'object') return '';
  return Object.entries(details).map(([k, v]) => {
    const val = (v !== null && typeof v === 'object') ? JSON.stringify(v) : String(v);
    return `${k}: ${val}`;
  }).join(' — ');
}

async function loadLogs() {
  const { data: logs } = await supabaseClient
    .from('audit_logs')
    .select('*, profiles(full_name)')
    .order('created_at', { ascending: false })
    .limit(100);

  const container = document.getElementById('logsList');
  container.textContent = '';
  if (!logs || logs.length === 0) {
    const empty = el('div', null, 'لا توجد نشاطات مسجلة بعد');
    empty.style.cssText = 'color:var(--text-muted); font-size:13px; text-align:center; padding:30px 0;';
    container.appendChild(empty);
    return;
  }

  for (const l of logs) {
    const date = new Date(l.created_at).toLocaleDateString('ar-EG', {
      year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
    });
    const adminName = l.profiles?.full_name || 'أدمن';
    const detailsText = formatDetails(l.details);

    const item = el('div', 'mini-list-item');
    item.style.cssText = 'flex-direction:column; align-items:stretch;';

    const row = el('div');
    row.style.cssText = 'display:flex; justify-content:space-between;';
    row.appendChild(el('div', 'name', l.action));
    row.appendChild(el('div', 'sub', date));
    item.appendChild(row);

    const by = el('div', 'sub', `بواسطة: ${adminName}`);
    by.style.marginTop = '4px';
    item.appendChild(by);

    if (detailsText) {
      const d = el('div', 'sub', detailsText);
      d.style.marginTop = '2px';
      item.appendChild(d);
    }
    container.appendChild(item);
  }
}

init();
