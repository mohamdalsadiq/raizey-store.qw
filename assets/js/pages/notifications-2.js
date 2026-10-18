async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: notifications } = await supabaseClient
    .from('notifications')
    .select('*')
    .eq('user_id', session.user.id)
    .order('created_at', { ascending: false });

  render(notifications || []);

  const unreadIds = (notifications || []).filter(n => !n.is_read).map(n => n.id);
  if (unreadIds.length > 0) {
    await supabaseClient.from('notifications').update({ is_read: true }).in('id', unreadIds);
  }
}

/* أيقونات SVG احترافية لحالات الإشعار — ممنوع الإيموجي */
const NOTIF_ICONS = {
  success: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M8 12.5l2.7 2.7L16 9.5"/></svg>',
  failed: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9.5 9.5l5 5M14.5 9.5l-5 5"/></svg>',
  pending: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 7v5l3.5 2"/></svg>',
  info: '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9a6 6 0 0 1 12 0c0 6 2.5 8 2.5 8h-17S6 15 6 9"/><path d="M10 20a2.2 2.2 0 0 0 4 0"/></svg>'
};

function notifStatus(n) {
  const t = (n.title || '') + ' ' + (n.message || '');
  if (/إلغاء|ملغ|فشل|مرفوض|رفض/.test(t)) return 'failed';
  if (/اكتمل بنجاح|تم تنفيذ/.test(t)) return 'success';
  if (/قيد التنفيذ|تم تأكيد|بانتظار|قيد المراجعة|تدقيق/.test(t)) return 'pending';
  return 'info';
}

function render(notifications) {
  const container = document.getElementById('notifList');
  if (notifications.length === 0) {
    container.innerHTML = `<div style="text-align: center; padding: 40px 20px; color: var(--text-muted);"><h3 style="color: var(--ink); margin-bottom: 8px;">لا توجد إشعارات بعد</h3></div>`;
    return;
  }

  container.innerHTML = notifications.map(n => {
    const st = notifStatus(n);
    const date = new Date(n.created_at).toLocaleDateString('ar-EG', {
      year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
    });
    const orderMatch = (n.message || '').match(/#(\d+)/);
    const orderNo = orderMatch ? orderMatch[1] : null;
    const cleanMsg = (n.message || '').replace(/#\d+\s*/, '');
    return `
      <div class="notif-card${!n.is_read ? ' unread' : ''}">
        <div class="notif-icon ${st}">${NOTIF_ICONS[st]}</div>
        <div class="notif-body">
          <div class="notif-title">${escapeHtml(n.title)}</div>
          <div class="notif-meta">
            ${orderNo ? `<span class="notif-order">#${escapeHtml(orderNo)}</span>` : ''}
            <span class="notif-date">${escapeHtml(date)}</span>
          </div>
          <div class="notif-msg">${escapeHtml(cleanMsg)}</div>
        </div>
      </div>
    `;
  }).join('');
}

init();
