const statusLabels = {
  pending_review: 'قيد المراجعة',
  in_progress: 'قيد التنفيذ',
  completed: 'مكتمل',
  cancelled: 'ملغي',
  rejected: 'مرفوض'
};

const paymentLabels = {
  wallet: 'من المحفظة',
  bank: 'تحويل بنكك'
};

let currentUser = null;

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    sessionStorage.setItem('redirect_after_login', window.location.href);
    window.location.href = 'login.html';
    return;
  }
  currentUser = session.user;
  await loadOrders();
}

async function loadOrders() {
  const { data: orders, error } = await supabaseClient
    .from('orders')
    .select('*')
    .eq('user_id', currentUser.id)
    .order('created_at', { ascending: false });

  const container = document.getElementById('ordersList');

  if (error || !orders || orders.length === 0) {
    container.innerHTML = `
      <div style="text-align: center; padding: 60px 20px; color: var(--text-muted);">
        <svg class="mm-i" style="font-size: 42px; color: var(--border); margin-bottom: 12px; display: block;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package-open"></use></svg>
        <h3 style="color: var(--ink); margin-bottom: 8px; font-size: 16px;">لا توجد طلبات بعد</h3>
        <p style="font-size: 13px;">ابدأ التسوق من الصفحة الرئيسية وستظهر طلباتك هنا</p>
        <a href="index.html" class="auth-btn" style="display: inline-block; text-decoration: none; margin-top: 14px; width: auto; padding: 10px 20px;">تصفح المتجر</a>
      </div>`;
    return;
  }

  container.innerHTML = orders.map(o => renderOrderCard(o)).join('');

  document.querySelectorAll('.cancel-order-btn').forEach(btn => {
    btn.addEventListener('click', () => cancelOrder(btn.dataset.orderId));
  });
}

function renderOrderCard(o) {
  const date = new Date(o.created_at).toLocaleDateString('ar-EG', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
  });

  let fieldsHtml = '';
  if (o.field_values && Object.keys(o.field_values).length > 0) {
    fieldsHtml = `
      <div class="order-fields-list">
        ${Object.entries(o.field_values).map(([k, v]) => {
          const label = (o.field_labels && o.field_labels[k]) ? o.field_labels[k] : k;
          return `<div><strong style="color: var(--text-muted);">${escapeHtml(label)}:</strong> ${escapeHtml(v)}</div>`;
        }).join('')}
      </div>
    `;
  }

  // إضافة عرض الخيار المختار
  let optionHtml = '';
  if (o.selected_option && o.selected_option.label) {
    optionHtml = `
      <div style="background: rgba(255, 212, 0, 0.05); border: 1px solid var(--primary); border-radius: 8px; padding: 8px; margin-top: 6px;">
        <strong>الخيار المختار:</strong> <span style="color: var(--mm-accent-text);">${escapeHtml(o.selected_option.label)}</span>
      </div>
    `;
  }

  return `
    <div class="order-card">
      <div class="order-top">
        <div>
          <div class="order-product">${escapeHtml(o.product_name_snapshot)}</div>
          <div class="order-date"><svg class="mm-i" style="margin-left: 4px;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-clock"></use></svg>${date}</div>
          <div style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">طلب #${escapeHtml(o.order_code || o.id.slice(0, 8))}</div>
        </div>
        <span class="status-badge status-${escapeHtml(o.status)}">${statusLabels[o.status] || escapeHtml(o.status)}</span>
      </div>

      <div class="order-details">
        <div><strong>السعر:</strong> <span style="color: var(--mm-accent-text); font-family: 'JetBrains Mono', monospace; font-weight: 700;">${formatSDG(o.price_sdg_snapshot)} ج.س</span></div>
        <div><strong>طريقة الدفع:</strong> ${paymentLabels[o.payment_type] || escapeHtml(o.payment_type)}</div>
        ${optionHtml} <!-- عرض الخيار المختار هنا -->
        ${fieldsHtml}
        ${o.receipt_url ? `<div><a href="${escapeHtml(o.receipt_url)}" target="_blank" rel="noopener" style="color: var(--mm-accent-text); font-weight: 700; text-decoration: none;"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-image"></use></svg> عرض صورة الإيصال</a></div>` : ''}
      </div>

      <div style="margin-top: 12px; display: flex; justify-content: space-between; align-items: center;">
        <a href="receipt.html?order_id=${escapeHtml(o.id)}" style="color: var(--mm-accent-text); font-size: 13px; font-weight: 700; text-decoration: none;">
          <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-receipt-text"></use></svg> عرض الإيصال والتفاصيل
        </a>
      </div>

      ${o.status === 'rejected' && o.rejection_reason ? `
        <div class="order-rejection"><strong>سبب الرفض:</strong> ${escapeHtml(o.rejection_reason)}</div>
      ` : ''}

      ${o.status === 'pending_review' ? `
        <button class="cancel-order-btn" data-order-id="${escapeHtml(o.id)}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-x"></use></svg> إلغاء الطلب</button>
      ` : ''}
    </div>
  `;
}

async function cancelOrder(orderId) {
  if (!confirm('هل أنت تأكد من رغبتك في إلغاء هذا الطلب؟')) return;

  // الإلغاء يتم عبر RPC خادمي (cancel_my_order) وليس بتحديث مباشر على الجدول:
  // الصلاحيات المباشرة على orders مسحوبة، والـ RPC تتحقق من المالك والحالة خادمياً.
  const { error } = await supabaseClient.rpc('cancel_my_order', { p_order_id: orderId });

  if (!error) {
    await loadOrders();
  } else {
    const msg = (error && error.message) || '';
    if (msg.includes('wallet_order_requires_support')) {
      alert('لا يمكن إلغاء هذا الطلب تلقائياً لأنه مدفوع من المحفظة — تواصل مع الدعم ليتم رد المبلغ.');
    } else if (msg.includes('invalid_status_transition')) {
      alert('لا يمكن إلغاء الطلب في حالته الحالية، حدّث الصفحة.');
    } else {
      alert('حدث خطأ أثناء إلغاء الطلب، يرجى المحاولة لاحقاً.');
    }
  }
}

init();
