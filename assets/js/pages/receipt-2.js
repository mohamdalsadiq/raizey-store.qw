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

async function init() {
  const params = new URLSearchParams(window.location.search);
  const orderId = params.get('order_id') || params.get('id');

  if (!orderId || !/^[0-9a-f-]{36}$/i.test(orderId)) {
    showError();
    return;
  }

  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    sessionStorage.setItem('redirect_after_login', window.location.href);
    window.location.href = 'login.html';
    return;
  }

  const { data: order, error } = await supabaseClient
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .eq('user_id', session.user.id)
    .single();

  if (error || !order) {
    showError();
    return;
  }

  renderReceipt(order);
}

function showError() {
  document.getElementById('loadingBox').style.display = 'none';
  document.getElementById('errorBox').style.display = 'block';
}

function renderReceipt(o) {
  document.getElementById('loadingBox').style.display = 'none';

  const date = new Date(o.created_at).toLocaleDateString('ar-EG', {
    year: 'numeric', month: 'long', day: 'numeric',
    hour: '2-digit', minute: '2-digit'
  });

  let iconClass = 'pending';
  let iconName  = 'clock';
  let titleText = 'تم إرسال طلبك بنجاح!';
  let subText   = 'طلبك قيد المراجعة، سيتم تنفيذه في أقرب وقت.';

  if (o.status === 'completed') {
    iconClass = ''; iconName = 'circle-check';
    titleText = 'تم تنفيذ طلبك!';
    subText = 'طلبك اكتمل بنجاح. شكراً لثقتك بـ MEEM STORE.';
  } else if (o.status === 'in_progress') {
    iconClass = ''; iconName = 'circle-check';
    titleText = 'جارِ تنفيذ طلبك';
    subText = 'فريقنا يعمل على طلبك الآن.';
  } else if (o.status === 'rejected') {
    iconClass = 'rejected'; iconName = 'circle-x';
    titleText = 'تم رفض الطلب';
    subText = o.rejection_reason ? `السبب: ${escapeHtml(o.rejection_reason)}` : 'تواصل مع الدعم لمزيد من التفاصيل.';
  } else if (o.status === 'cancelled') {
    iconClass = 'rejected'; iconName = 'ban';
    titleText = 'تم إلغاء الطلب';
    subText = 'قمت بإلغاء هذا الطلب.';
  }

  let fieldsHtml = '';
  if (o.field_values && Object.keys(o.field_values).length > 0) {
    fieldsHtml = `
      <div class="receipt-row">
        <span class="label">بيانات الطلب</span>
        <div class="receipt-fields-list">
          ${Object.entries(o.field_values).map(([k, v]) => {
            const label = (o.field_labels && o.field_labels[k]) ? o.field_labels[k] : k;
            return `<div><span class="fkey">${escapeHtml(label)}:</span> ${escapeHtml(v)}</div>`;
          }).join('')}
        </div>
      </div>
    `;
  }

  // إضافة عرض الخيار المختار في الإيصال
  let optionHtml = '';
  if (o.selected_option && o.selected_option.label) {
    optionHtml = `
      <div class="receipt-row">
        <span class="label">الخيار المختار</span>
        <span class="value" style="color: var(--mm-accent-text); font-weight: 700;">${escapeHtml(o.selected_option.label)}</span>
      </div>
    `;
  }

  const receiptLinkHtml = o.receipt_url ? `
    <div class="receipt-row">
      <span class="label">صورة الإيصال</span>
      <a href="${escapeHtml(o.receipt_url)}" target="_blank" rel="noopener" class="receipt-receipt-img-link">
        <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-image"></use></svg> عرض الإيصال
      </a>
    </div>
  ` : '';

  const transactionHtml = o.transaction_reference ? `
    <div class="receipt-row">
      <span class="label">رقم العملية</span>
      <span class="value">${escapeHtml(o.transaction_reference)}</span>
    </div>
  ` : '';

  const rejectionHtml = (o.status === 'rejected' && o.rejection_reason) ? `
    <div style="background: rgba(255, 107, 107,0.08); border: 1px solid rgba(255, 107, 107,0.2); border-radius: 10px; padding: 12px; margin-top: 14px; font-size: 13px; color: var(--mm-danger);">
      <strong>سبب الرفض:</strong> ${escapeHtml(o.rejection_reason)}
    </div>
  ` : '';

  document.getElementById('receiptContent').innerHTML = `
    <div class="receipt-success-icon ${iconClass}">
      <div class="icon-circle">${window.rzIconMarkup(iconName)}</div>
      <p class="receipt-title">${titleText}</p>
      <p class="receipt-sub">${subText}</p>
    </div>

    <div class="receipt-card">
      <div class="receipt-card-title"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package"></use></svg> تفاصيل المنتج</div>

      <div class="receipt-row">
        <span class="label">المنتج</span>
        <span class="value">${escapeHtml(o.product_name_snapshot)}</span>
      </div>

      ${optionHtml} <!-- عرض الخيار المختار هنا -->

      <div class="receipt-row">
        <span class="label">المبلغ</span>
        <span class="value price">${formatSDG(o.price_sdg_snapshot)} ج.س</span>
      </div>

      <div class="receipt-row">
        <span class="label">طريقة الدفع</span>
        <span class="value">${paymentLabels[o.payment_type] || escapeHtml(o.payment_type)}</span>
      </div>

      <div class="receipt-row">
        <span class="label">الحالة</span>
        <span class="receipt-status-badge ${o.status}">
          ${statusLabels[o.status] || escapeHtml(o.status)}
        </span>
      </div>

      ${fieldsHtml}
      ${transactionHtml}
      ${receiptLinkHtml}

      <div class="receipt-row" style="margin-top: 14px; padding-top: 10px; border-top: 1px dashed var(--border);">
        <span class="label">رقم الطلب</span>
        <span class="receipt-id">${escapeHtml(o.order_code || o.id)}</span>
      </div>

      <div class="receipt-row">
        <span class="label">التاريخ</span>
        <span class="value" style="font-size: 12px;">${date}</span>
      </div>
    </div>

    ${rejectionHtml}

    <div class="receipt-actions">
      <a href="my-orders.html" class="receipt-btn-primary">
        <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package-open"></use></svg> عرض جميع طلباتي
      </a>
      <a href="index.html" class="receipt-btn-secondary">
        <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-store"></use></svg> متابعة التسوق
      </a>
    </div>
  `;

  document.getElementById('receiptContent').style.display = 'block';
}

init();
