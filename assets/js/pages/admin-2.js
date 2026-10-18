async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles')
    .select('role')
    .eq('id', session.user.id)
    .single();

  if (!profile || profile.role !== 'admin') {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  document.getElementById('adminPage').style.display = 'block';
  await loadStats();
  await loadSalesChart();
  await loadRecentOrders();
  await loadRecentCustomers();
}

async function loadSalesChart() {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 6);
  sevenDaysAgo.setHours(0, 0, 0, 0);

  const { data: orders } = await supabaseClient
    .from('orders')
    .select('price_sdg_snapshot, created_at')
    .in('status', ['in_progress', 'completed'])
    .gte('created_at', sevenDaysAgo.toISOString());

  const labels = [];
  const totals = [];

  for (let i = 6; i >= 0; i--) {
    const day = new Date();
    day.setDate(day.getDate() - i);
    const dayKey = day.toISOString().slice(0, 10);
    labels.push(day.toLocaleDateString('ar-EG', { weekday: 'short', day: 'numeric' }));

    const dayTotal = (orders || [])
      .filter(o => o.created_at.slice(0, 10) === dayKey)
      .reduce((sum, o) => sum + Number(o.price_sdg_snapshot), 0);

    totals.push(dayTotal);
  }

  new Chart(document.getElementById('salesChart'), {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'المبيعات (ج.س)',
        data: totals,
        borderColor: '#FFD400',
        backgroundColor: 'rgba(8,123,255,0.12)',
        tension: 0.3,
        fill: true
      }]
    },
    options: {
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: '#C9D4F0' }, grid: { color: '#1B3AA0' } },
        y: { ticks: { color: '#C9D4F0' }, grid: { color: '#1B3AA0' } }
      }
    }
  });
}

async function loadStats() {
  const { count: ordersCount } = await supabaseClient
    .from('orders').select('*', { count: 'exact', head: true });

  const { count: customersCount } = await supabaseClient
    .from('profiles').select('*', { count: 'exact', head: true }).eq('role', 'customer');

  const { count: productsCount } = await supabaseClient
    .from('products').select('*', { count: 'exact', head: true });

  // استخدم نفس مصدر الحقيقة المحمي الذي يغذي شريط التنقل.
  const { data: alertCounts } = await supabaseClient.rpc('get_admin_notification_counts');
  const alertRow = Array.isArray(alertCounts) ? alertCounts[0] : alertCounts;
  const pendingOrders = alertRow
    ? Number(alertRow.pending_orders || 0) + Number(alertRow.needs_admin_check || 0)
    : (await supabaseClient.from('orders').select('id', { count: 'exact', head: true }).eq('status', 'pending_review')).count || 0;

  const { count: pendingTopups } = await supabaseClient
    .from('wallet_topups').select('id', { count: 'exact', head: true }).eq('status', 'pending');

  const { data: revenueRows } = await supabaseClient
    .from('orders').select('price_sdg_snapshot').in('status', ['in_progress', 'completed']);

  const revenue = (revenueRows || []).reduce((sum, o) => sum + Number(o.price_sdg_snapshot), 0);

  document.getElementById('statOrders').textContent = ordersCount ?? 0;
  document.getElementById('statCustomers').textContent = customersCount ?? 0;
  document.getElementById('statProducts').textContent = productsCount ?? 0;
  document.getElementById('statPending').textContent = pendingOrders ?? 0;
  document.getElementById('statPendingTopups').textContent = pendingTopups ?? 0;
  document.getElementById('statRevenue').textContent = formatSDG(revenue) + ' ج.س';
}

async function loadRecentOrders() {
  const { data: orders } = await supabaseClient
    .from('orders')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(5);

  const container = document.getElementById('recentOrders');
  if (!orders || orders.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px;">لا توجد طلبات بعد</div>`;
    return;
  }

  container.innerHTML = orders.map(o => `
    <div class="mini-list-item">
      <div>
        <div class="name">${escapeHtml(o.product_name_snapshot)}</div>
        <div class="sub">${formatSDG(o.price_sdg_snapshot)} ج.س — ${o.payment_type === 'wallet' ? 'محفظة' : 'تحويل'}</div>
      </div>
      <span class="status-badge status-${escapeHtml(o.status)}">${{'pending_review':'قيد المراجعة','in_progress':'قيد التنفيذ','completed':'مكتمل','cancelled':'ملغي','rejected':'مرفوض'}[o.status] || escapeHtml(o.status)}</span>
    </div>
  `).join('');
}

async function loadRecentCustomers() {
  const { data: customers } = await supabaseClient
    .from('profiles')
    .select('*')
    .eq('role', 'customer')
    .order('created_at', { ascending: false })
    .limit(5);

  const container = document.getElementById('recentCustomers');
  if (!customers || customers.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px;">لا يوجد عملاء بعد</div>`;
    return;
  }

  container.innerHTML = customers.map(c => `
    <div class="mini-list-item">
      <div>
        <div class="name">${escapeHtml(c.full_name || 'بدون اسم')}</div>
        <div class="sub">${escapeHtml(c.whatsapp_number || '—')}</div>
      </div>
    </div>
  `).join('');
}

init();
