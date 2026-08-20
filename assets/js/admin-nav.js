// RAIZEY STORE — canonical admin navigation and alert counts
(function () {
  'use strict';

  const NAV_ITEMS = [
    ['admin.html', 'الرئيسية'],
    ['admin-orders.html', 'الطلبات'],
    ['admin-topups.html', 'شحن المحافظ'],
    ['admin-products.html', 'المنتجات والباقات'],
    ['admin-categories.html', 'الأقسام'],
    ['admin-customers.html', 'العملاء'],
    ['admin-payment-methods.html', 'وسائل الدفع'],
    ['admin-settings.html', 'الإعدادات'],
    ['admin-audit-log.html', 'سجل النشاطات'],
    ['admin-coupons.html', 'الكوبونات'],
    ['admin-giftcards.html', 'كروت الهدايا'],
    ['admin-payment-codes.html', 'رموز الدفع'],
    ['admin-referral-milestones.html', 'مستويات الإحالة'],
    ['admin-staff.html', 'المشرفون']
  ];

  function setBadge(href, count, label) {
    const link = document.querySelector(`.admin-nav a[href="${href}"]`);
    if (!link) return;
    let badge = link.querySelector('.admin-nav-alert');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'admin-nav-alert';
      badge.setAttribute('role', 'status');
      link.appendChild(badge);
    }
    const safeCount = Math.max(0, Number(count) || 0);
    badge.textContent = safeCount > 99 ? '99+' : String(safeCount);
    badge.setAttribute('aria-label', `${label}: ${safeCount}`);
    badge.hidden = safeCount === 0;
  }

  function ensureCanonicalNavigation() {
    document.querySelectorAll('.admin-nav').forEach((nav) => {
      const current = (window.location.pathname.split('/').pop() || 'admin.html').split('?')[0];
      nav.innerHTML = NAV_ITEMS.map(([href, label]) => {
        const active = href === current;
        return `<a href="${href}"${active ? ' class="active" aria-current="page"' : ''}>${label}</a>`;
      }).join('');
    });
  }

  async function countFallback(table, column, value) {
    try {
      const { count, error } = await window.supabaseClient
        .from(table)
        .select('id', { count: 'exact', head: true })
        .eq(column, value);
      return error ? 0 : (count || 0);
    } catch (_) {
      return 0;
    }
  }

  async function loadAdminAlerts() {
    ensureCanonicalNavigation();
    if (!window.supabaseClient) return;
    try {
      const { data: sessionData } = await window.supabaseClient.auth.getSession();
      if (!sessionData?.session) return;

      const { data, error } = await window.supabaseClient.rpc('get_admin_notification_counts');
      if (!error && data) {
        const row = Array.isArray(data) ? data[0] : data;
        setBadge('admin-orders.html', Number(row?.pending_orders || 0) + Number(row?.needs_admin_check || 0), 'طلبات تحتاج مراجعة');
        setBadge('admin-topups.html', row?.pending_topups, 'شحن محافظ معلّق');
        return;
      }

      // Fallback is intentionally limited to the unambiguous pending states.
      const [pendingOrders, pendingTopups] = await Promise.all([
        countFallback('orders', 'status', 'pending_review'),
        countFallback('wallet_topups', 'status', 'pending')
      ]);
      setBadge('admin-orders.html', pendingOrders, 'طلبات تحتاج مراجعة');
      setBadge('admin-topups.html', pendingTopups, 'شحن محافظ معلّق');
    } catch (_) {
      // Do not break an admin page when the alert RPC is unavailable.
    }
  }

  function boot() {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', loadAdminAlerts, { once: true });
    } else {
      loadAdminAlerts();
    }
  }

  boot();
})();
