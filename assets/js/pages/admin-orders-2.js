let allOrders = [];
let currentFilter = 'all';
let currentSearch = '';
let rejectingOrderId = null;
let selectedReason = null;
let currentAdminId = null;

const statusLabels = {
  pending_review: 'قيد المراجعة',
  in_progress: 'قيد التنفيذ',
  completed: 'مكتمل',
  cancelled: 'ملغي',
  rejected: 'مرفوض',
  needs_admin_check: 'يحتاج تدقيق'
};

const rejectModal = document.getElementById('rejectModal');
const customReasonInput = document.getElementById('customReasonInput');
const modalConfirmBtn = document.getElementById('modalConfirmBtn');

function showToast(message, tone = 'default') {
  let box = document.getElementById('adminToast');
  if (!box) {
    box = document.createElement('div');
    box.id = 'adminToast';
    box.setAttribute('role', 'alert');
    box.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:9999;max-width:92vw;padding:12px 16px;border-radius:12px;font-size:13px;text-align:center;box-shadow:0 8px 24px rgba(0,0,0,.16);';
    document.body.appendChild(box);
  }
  box.style.background = tone === 'error' ? 'var(--danger)' : 'var(--bg-card)';
  box.style.color = tone === 'error' ? '#fff' : 'var(--ink)';
  box.style.border = tone === 'error' ? '1px solid var(--danger)' : '1px solid var(--border)';
  box.textContent = message;
  box.style.display = 'block';
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => { box.style.display = 'none'; }, 4200);
}

function mapOrderError(message) {
  const value = String(message || '').toLowerCase();
  if (value.includes('pgrst202') || value.includes('does not exist') || value.includes('admin_update_order_status') || value.includes('admin_reject_order')) return 'شغّل ملف SQL الخاص بالتوسعة في Supabase أولاً لتفعيل إجراءات الإدارة الآمنة.';
  if (value.includes('manage_orders')) return 'ليست لديك صلاحية إدارة الطلبات.';
  if (value.includes('invalid_status_transition')) return 'لا يمكن نقل الطلب من حالته الحالية إلى هذه الحالة.';
  if (value.includes('order_not_found')) return 'الطلب غير موجود أو تم حذفه.';
  if (value.includes('reason_required')) return 'اكتب سبب الرفض أولاً.';
  return 'تعذر تنفيذ العملية. حدّث الصفحة وحاول مرة أخرى.';
}

document.querySelectorAll('.reason-option').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.reason-option').forEach(b => b.classList.remove('selected'));
    btn.classList.add('selected');

    if (btn.dataset.reason === 'custom') {
      customReasonInput.classList.add('show');
      selectedReason = customReasonInput.value.trim() || null;
    } else {
      customReasonInput.classList.remove('show');
      selectedReason = btn.dataset.reason;
    }
    modalConfirmBtn.disabled = !selectedReason;
  });
});

customReasonInput.addEventListener('input', () => {
  selectedReason = customReasonInput.value.trim() || null;
  modalConfirmBtn.disabled = !selectedReason;
});

document.getElementById('modalCancelBtn').addEventListener('click', closeRejectModal);

modalConfirmBtn.addEventListener('click', async () => {
  if (!selectedReason || !rejectingOrderId) return;
  modalConfirmBtn.disabled = true;
  const order = allOrders.find(o => o.id === rejectingOrderId);

  const { error } = await supabaseClient.rpc('admin_reject_order', {
    p_order_id: rejectingOrderId,
    p_reason: selectedReason
  });

  if (error) {
    showToast(mapOrderError(error.message), 'error');
    modalConfirmBtn.disabled = false;
    return;
  }

  closeRejectModal();
  await loadOrders();
});

function openRejectModal(orderId) {
  rejectingOrderId = orderId;
  selectedReason = null;
  customReasonInput.value = '';
  customReasonInput.classList.remove('show');
  document.querySelectorAll('.reason-option').forEach(b => b.classList.remove('selected'));
  modalConfirmBtn.disabled = true;
  rejectModal.classList.add('show');
}

function closeRejectModal() {
  rejectModal.classList.remove('show');
  rejectingOrderId = null;
}

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).single();

  if (!profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  const { data: canManageOrders, error: permissionError } = await supabaseClient
    .rpc('has_admin_permission', { permission_key: 'manage_orders' });
  if (permissionError || canManageOrders !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  currentAdminId = session.user.id;
  document.getElementById('adminPage').style.display = 'block';

  document.querySelectorAll('#filterRow .chip').forEach((button) => {
    button.addEventListener('click', () => {
      document.querySelectorAll('#filterRow .chip').forEach((chip) => chip.classList.remove('active'));
      button.classList.add('active');
      currentFilter = button.dataset.filter || 'all';
      render();
    });
  });

  document.getElementById('orderSearchInput').addEventListener('input', (e) => {
    currentSearch = e.target.value.trim().toLowerCase();
    render();
  });

  await loadOrders();
}

async function loadOrders() {
  const SELECT_WITH_RECEIPT =
    '*, profiles(full_name, whatsapp_number), ' +
    'payment_receipts(tx_ref_raw, amount_expected, amount_detected, tx_ref_ocr, ocr_status, risk_flags, ocr_data)';

  let { data, error } = await supabaseClient
    .from('orders')
    .select(SELECT_WITH_RECEIPT)
    .order('created_at', { ascending: false });

  // بعض القواعد لم تُربط فيها العلاقة بعد — نرجع للاستعلام البسيط بدل تعطيل الصفحة
  if (error) {
    const fallback = await supabaseClient
      .from('orders')
      .select('*, profiles(full_name, whatsapp_number)')
      .order('created_at', { ascending: false });
    data = fallback.data;
  }

  allOrders = data || [];
  render();
}

function render() {
  const container = document.getElementById('ordersList');
  let filtered =
    currentFilter === 'all' ? allOrders :
    currentFilter === 'needs_admin_check'
      ? allOrders.filter(o => o.ocr_status === 'needs_admin_check' || o.review_reason)
      : allOrders.filter(o => o.status === currentFilter);

  if (currentSearch) {
    filtered = filtered.filter(o => {
      const haystack = [
        o.order_code, o.id, o.transaction_reference,
        o.profiles?.full_name, o.profiles?.whatsapp_number, o.product_name_snapshot
      ].filter(Boolean).join(' ').toLowerCase();
      return haystack.includes(currentSearch);
    });
  }

  if (filtered.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد طلبات مطابقة</div>`;
    return;
  }

  container.innerHTML = filtered.map(o => renderOrderCard(o)).join('');

  container.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', () => handleAction(btn.dataset.action, btn.dataset.orderId));
  });

  container.querySelectorAll('.mini-copy-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(btn.dataset.copy);
        const original = btn.textContent;
        btn.textContent = 'تم'; btn.classList.add('copied');
        setTimeout(() => { btn.textContent = original; btn.classList.remove('copied'); }, 1500);
      } catch (e) {}
    });
  });
}

function renderOrderCard(o) {
  const date = new Date(o.created_at).toLocaleDateString('ar-EG', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
  });

  // يجب التصريح بها هنا قبل استخدامها في refHtml بالأسفل — كانت مُصرَّحة
  // بعد استخدامها بالخطأ (Temporal Dead Zone) فتكسر عرض أي طلب بتحويل بنكي
  const safeTransactionReference = safeDataAttr(o.transaction_reference || '');

  const fieldsHtml = o.field_values && Object.keys(o.field_values).length > 0
    ? Object.entries(o.field_values).map(([k, v]) => {
        const label = (o.field_labels && o.field_labels[k]) ? o.field_labels[k] : k;
        return `
        <div class="copyable-row">
          <span><strong>${escapeHtml(label)}:</strong> ${escapeHtml(v)}</span>
          <button type="button" class="mini-copy-btn" data-copy="${safeDataAttr(v)}">نسخ</button>
        </div>
      `;
      }).join('')
    : '';

  const optionHtml = (o.selected_option && o.selected_option.label) ? `
    <div style="display: flex; align-items: center; gap: 6px; color: var(--mm-accent-text); font-weight: 700;">
      <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-list-checks"></use></svg> الخيار المختار: ${escapeHtml(o.selected_option.label)}
    </div>
  ` : '';

  const refHtml = o.transaction_reference ? `
    <div class="copyable-row">
      <span>رقم العملية: ${escapeHtml(o.transaction_reference)}</span>
      <button type="button" class="mini-copy-btn" data-copy="${safeTransactionReference}">نسخ</button>
    </div>
  ` : '';

  const customerName = escapeHtml(o.profiles?.full_name || 'بدون اسم');
  const customerWhatsapp = escapeHtml(o.profiles?.whatsapp_number || '—');
  const safeOrderId = safeDataAttr(o.id || '');
  const safeStatus = safeDataAttr(o.status || '');
  const receiptUrl = sanitizeUrl(o.receipt_url);
  const safeWhatsappCopy = safeDataAttr(o.profiles?.whatsapp_number || '');

  let actions = '';
  if (o.status === 'pending_review') {
    actions = `
      <div class="admin-order-actions">
        <button class="admin-btn btn-confirm" data-action="confirm" data-order-id="${safeOrderId}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-play"></use></svg> بدء التنفيذ</button>
        <button class="admin-btn btn-reject" data-action="reject" data-order-id="${safeOrderId}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-x"></use></svg> رفض</button>
        <button class="admin-btn" data-action="cancel" data-order-id="${safeOrderId}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-ban"></use></svg> إلغاء</button>
      </div>`;
  } else if (o.status === 'in_progress') {
    actions = `
      <div class="admin-order-actions">
        <button class="admin-btn btn-complete" data-action="complete" data-order-id="${safeOrderId}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-check"></use></svg> تم التنفيذ</button>
        <button class="admin-btn" data-action="cancel" data-order-id="${safeOrderId}"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-ban"></use></svg> إلغاء</button>
      </div>`;
  }

  // ── بطاقة التدقيق الإداري: السبب + كل البيانات المقروءة من الفحص ──
  const rec = o.payment_receipts || null;
  const severity = o.review_severity || (rec && rec.ocr_data && rec.ocr_data.review_severity) || 'normal';
  const reviewReason = o.review_reason || (rec && rec.ocr_data && rec.ocr_data.review_reason) || null;
  const needsAdmin = o.ocr_status === 'needs_admin_check' || !!reviewReason;

  const flags = (rec && Array.isArray(rec.risk_flags)) ? rec.risk_flags : [];
  const scanRows = [];
  if (rec) {
    if (rec.tx_ref_ocr)      scanRows.push(`رقم العملية المقروء: ${rec.tx_ref_ocr}`);
    if (rec.amount_detected) scanRows.push(`المبلغ المقروء: ${formatSDG(rec.amount_detected)} ج.س`);
    if (rec.amount_expected) scanRows.push(`المبلغ المطلوب: ${formatSDG(rec.amount_expected)} ج.س`);
    if (rec.ocr_data && rec.ocr_data.dateTime) scanRows.push(`تاريخ الإشعار: ${rec.ocr_data.dateTime}`);
    if (rec.ocr_data && rec.ocr_data.split_payment) {
      const sp = rec.ocr_data.split_payment;
      scanRows.push(`دفع مجزّأ: ${formatSDG(sp.first_amount)} + ${formatSDG(sp.second_amount)} ج.س (رقم ثانٍ: ${sp.second_tx_ref})`);
    }
    if (flags.length) scanRows.push(`الرايات: ${flags.join('، ')}`);
    if (rec.ocr_status) scanRows.push(`حالة الفحص: ${rec.ocr_status}`);
  } else if (o.ocr_status) {
    scanRows.push(`حالة الفحص: ${o.ocr_status}`);
  }

  // ── إبراز الرايات الحرجة (المهمة 3): تنبيه أحمر صريح لا يمكن تفويته ──
  const CRITICAL_FLAG_LABELS = {
    destination_account_unverified: 'المبلغ قد لا يكون وصل حساب المتجر — تحقق يدوياً قبل التنفيذ!',
    ref_conflict: 'تعارض في رقم العملية — تحقق يدوياً قبل التنفيذ!',
    editor_signature: 'بصمة محرر صور في الإشعار — تحقق يدوياً قبل التنفيذ!',
    amount_mismatch: 'المبلغ غير مطابق — تحقق يدوياً قبل التنفيذ!'
  };
  const criticalHits = flags.filter((f) => CRITICAL_FLAG_LABELS[f]);
  const criticalFlagsHtml = criticalHits.length
    ? `<div style="margin: 6px 0 2px;display: flex;flex-direction: column;gap: 4px;">` +
      criticalHits.map((f) =>
        `<span style="background: rgba(255, 107, 107,.12);color: var(--danger);border: 1px solid var(--danger);` +
        `border-radius: 8px;padding: 4px 10px;font-weight: 800;font-size: 12.5px;">` +
        `⚠ ${escapeHtml(CRITICAL_FLAG_LABELS[f])} <span style="font-weight: 400;opacity: .75;">(${escapeHtml(f)})</span></span>`
      ).join('') + `</div>`
    : '';

  const reviewHtml = needsAdmin ? `
    <div style="margin-top: 10px; border-radius: 10px; padding: 10px 12px; font-size: 12.5px; line-height: 1.7;
                border:1px solid ${severity === 'high' ? 'var(--danger)' : 'var(--mm-warning)'};
                background:${severity === 'high' ? 'rgba(179,38,30,.08)' : 'rgba(201,138,31,.10)'};">
      <strong style="color:${severity === 'high' ? 'var(--danger)' : 'var(--mm-warning)'};">
        <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-shield-user"></use></svg> يحتاج تدقيق${severity === 'high' ? ' — تنبيه مشدّد' : ''}
      </strong>
      ${reviewReason ? `<div style="margin-top: 4px;">${escapeHtml(reviewReason)}</div>` : ''}
      ${criticalFlagsHtml}
      ${scanRows.length ? `<div style="margin-top: 6px; color: var(--text-muted);">${scanRows.map(escapeHtml).join('<br>')}</div>` : ''}
    </div>` : (scanRows.length || criticalFlagsHtml ? `
    <div style="margin-top: 10px; font-size: 12px; color: var(--text-muted); line-height: 1.7;">
      ${criticalFlagsHtml}
      ${scanRows.map(escapeHtml).join('<br>')}
    </div>` : '');

  return `
    <div class="order-card">
      <div class="order-top">
        <div>
          <div class="order-product">${escapeHtml(o.product_name_snapshot)}</div>
          <div style="font-size: 12px; color: var(--mm-accent-text); font-weight: 700; margin-top: 2px;">طلب #${escapeHtml(o.order_code || o.id.slice(0, 8))}</div>
          <div class="order-date">${date}</div>
        </div>
        <span class="status-badge status-${safeStatus}">${statusLabels[o.status] || safeStatus}</span>
      </div>

      <div class="customer-info">
        <span>${customerName} — ${customerWhatsapp}</span>
        <button type="button" class="mini-copy-btn" data-copy="${safeWhatsappCopy}">نسخ الرقم</button>
      </div>

      <div class="order-details">
        <div><strong>السعر:</strong> ${formatSDG(o.price_sdg_snapshot)} ج.س</div>
        <div><strong>الدفع:</strong> ${o.payment_type === 'wallet' ? 'من المحفظة' : 'تحويل بنكك'}</div>
        ${optionHtml}
        ${fieldsHtml}
        ${refHtml}
        ${receiptUrl ? `<div><a href="${escapeAttribute(receiptUrl)}" target="_blank" rel="noopener" style="color: var(--mm-accent-text);">عرض الإيصال</a></div>` : ''}
      </div>

      ${reviewHtml}

      ${o.status === 'rejected' && o.rejection_reason ? `
        <div class="order-rejection">سبب الرفض: ${escapeHtml(o.rejection_reason)}</div>
      ` : ''}

      ${actions}
    </div>
  `;
}

async function handleAction(action, orderId) {
  const order = allOrders.find(o => o.id === orderId);
  if (!order) return;

  if (action === 'reject') {
    openRejectModal(orderId);
    return;
  }

  const nextStatus = action === 'confirm' ? 'in_progress' : action === 'complete' ? 'completed' : action === 'cancel' ? 'cancelled' : null;
  if (!nextStatus) return;

  const button = document.querySelector(`[data-action="${CSS.escape(action)}"][data-order-id="${CSS.escape(orderId)}"]`);
  if (button) { button.disabled = true; button.dataset.originalLabel = button.innerHTML; button.innerHTML = '<svg class="mm-i mm-spin" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-loader"></use></svg> جارٍ التنفيذ'; }

  let overrideReason = null;
  let { error } = await supabaseClient.rpc('admin_update_order_status', { p_order_id: orderId, p_status: nextStatus });
  if (error && /unverified_payment_evidence/i.test(error.message || '')) {
    const input = window.prompt(
      'تنبيه: لا يوجد دليل دفع موثّق خادمياً لهذا الطلب\n(لا إيصال مُتحقق، ولا خصم محفظة مطابق، ولا رمز دفع مستخدم).\n\nلا يكفي تأكيد الطلب بدون تجاوز موثّق. اكتب سبب التجاوز (سيُسجَّل في سجل التدقيق)، أو اضغط إلغاء للرجوع.'
    );
    if (input !== null) {
      overrideReason = (input || '').trim();
      if (overrideReason) {
        ({ error } = await supabaseClient.rpc('admin_update_order_status', {
          p_order_id: orderId, p_status: nextStatus, p_override_reason: overrideReason
        }));
      } else {
        showToast('يجب كتابة سبب التجاوز للمتابعة.', 'error');
        if (button) { button.disabled = false; button.innerHTML = button.dataset.originalLabel || 'تنفيذ'; }
        return;
      }
    } else {
      if (button) { button.disabled = false; button.innerHTML = button.dataset.originalLabel || 'تنفيذ'; }
      return;
    }
  }
  if (error) {
    if (button) { button.disabled = false; button.innerHTML = button.dataset.originalLabel || 'تنفيذ'; }
    showToast(mapOrderError(error.message), 'error');
    await loadOrders();
    return;
  }

  const labels = { in_progress: 'تم تأكيد طلبك', completed: 'تم تنفيذ طلبك', cancelled: 'تم إلغاء طلبك' };
  const messages = {
    in_progress: `طلبك #${order.order_code} (${order.product_name_snapshot}) قيد التنفيذ الآن.`,
    completed: `طلبك #${order.order_code} (${order.product_name_snapshot}) اكتمل بنجاح.`,
    cancelled: `طلبك #${order.order_code} (${order.product_name_snapshot}) تم إلغاؤه من الإدارة.`
  };
  await notifyCustomer(order.user_id, labels[nextStatus], messages[nextStatus]);
  await logAudit(labels[nextStatus], { order_id: orderId, product: order.product_name_snapshot, override_reason: overrideReason });
  if (nextStatus === 'in_progress') {
    await supabaseClient.rpc('process_referral_commission', { p_user_id: order.user_id, p_order_id: orderId });
  }
  await loadOrders();
}

async function notifyCustomer(userId, title, message) {
  await supabaseClient.from('notifications').insert({ user_id: userId, title, message, type: 'order' });
}

async function logAudit(action, details) {
  await supabaseClient.from('audit_logs').insert({ admin_id: currentAdminId, action, details });
}

init();
