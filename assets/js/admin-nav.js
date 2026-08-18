// RAIZEY STORE — Admin navigation alerts
// عدادات الإدارة تُقرأ من RPC محمية، مع fallback محدود عند عدم تطبيق migration بعد.
(function () {
  'use strict';

  function setBadge(href, count, label) {
    const link = document.querySelector(`.admin-nav a[href="${href}"]`);
    if (!link) return;
    let badge = link.querySelector('.admin-nav-alert');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'admin-nav-alert';
      badge.setAttribute('aria-label', label);
      link.appendChild(badge);
    }
    const safeCount = Math.max(0, Number(count) || 0);
    badge.textContent = safeCount > 99 ? '99+' : String(safeCount);
    badge.hidden = safeCount === 0;
  }

  async function countFallback(table, column, value) {
    try {
      const { count, error } = await supabaseClient
        .from(table)
        .select('id', { count: 'exact', head: true })
        .eq(column, value);
      return error ? 0 : (count || 0);
    } catch (_) {
      return 0;
    }
  }

  function ensureCatalogNavigation() {
    document.querySelectorAll('.admin-nav').forEach((nav) => {
      nav.querySelectorAll('a[href="admin-catalog.html"], a[href="admin-subcategories.html"]').forEach((legacyLink) => legacyLink.remove());
      const categoriesLink = nav.querySelector('a[href="admin-categories.html"]');
      if (categoriesLink) {
        categoriesLink.innerHTML = '<i class="fas fa-layer-group" aria-hidden="true"></i> إدارة الأقسام';
        categoriesLink.setAttribute('aria-label', 'إدارة الأقسام الرئيسية');
      }
      const productsLink = nav.querySelector('a[href="admin-products.html"]');
      if (productsLink) {
        productsLink.innerHTML = '<i class="fas fa-boxes-stacked" aria-hidden="true"></i> إدارة المنتجات والباقات';
        productsLink.setAttribute('aria-label', 'إدارة المنتجات والباقات');
      }
    });
  }

  async function loadAdminAlerts() {
    ensureCatalogNavigation();
    if (!window.supabaseClient) return;
    try {
      const { data: sessionData } = await supabaseClient.auth.getSession();
      if (!sessionData?.session) return;

      const { data, error } = await supabaseClient.rpc('get_admin_notification_counts');
      if (!error && data) {
        const row = Array.isArray(data) ? data[0] : data;
        setBadge('admin-orders.html', Number(row?.pending_orders) + Number(row?.needs_admin_check), 'طلبات تحتاج مراجعة');
        setBadge('admin-topups.html', row?.pending_topups, 'شحن محافظ معلّق');
        return;
      }

      const [pendingOrders, pendingTopups] = await Promise.all([
        countFallback('orders', 'status', 'pending_review'),
        countFallback('wallet_topups', 'status', 'pending')
      ]);
      setBadge('admin-orders.html', pendingOrders, 'طلبات تحتاج مراجعة');
      setBadge('admin-topups.html', pendingTopups, 'شحن محافظ معلّق');
    } catch (_) {
      // لا نكسر لوحة الإدارة إذا لم تكن migration قد طُبقت بعد.
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', loadAdminAlerts, { once: true });
  } else {
    loadAdminAlerts();
  }
})();
