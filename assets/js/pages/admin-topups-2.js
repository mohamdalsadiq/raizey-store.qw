let allTopups = [];
let currentFilter = 'all';
let rejectingTopupId = null;
let selectedReason = null;
let currentAdminId = null;

const statusLabels = { pending: 'قيد المراجعة', confirmed: 'مؤكد', rejected: 'مرفوض' };

// رسائل مفهومة لأخطاء دوال المحفظة في القاعدة
function mapTopupError(msg) {
  const m = String(msg || '').toLowerCase();
  if (m.includes('already_processed')) return 'هذا الطلب تمت معالجته بالفعل. تم تحديث القائمة.';
  if (m.includes('topup_not_found'))   return 'الطلب غير موجود.';
  if (m.includes('reason_required'))   return 'يجب كتابة سبب الرفض.';
  if (m.includes('invalid_amount'))    return 'مبلغ الطلب غير صالح.';
  if (m.includes('topup_amount_mismatch')) return 'المبلغ غير مطابق للإيصال — اكتب سبب التجاوز للمتابعة.';
  if (m.includes('manage_wallets'))    return 'ليست لديك صلاحية إدارة المحافظ.';
  if (m.includes('access_denied'))     return 'غير مصرح بهذا الإجراء.';
  return 'تعذّر تنفيذ العملية. حاول مجدداً.';
}

// استخراج مسار الملف داخل bucket "receipts" من رابط Storage المحفوظ
function extractReceiptPath(url) {
  const clean = sanitizeUrl(url);
  if (!clean) return '';
  try {
    const { pathname } = new URL(clean);
    const marker = '/receipts/';
    const idx = pathname.indexOf(marker);
    if (idx === -1) return '';
    const path = decodeURIComponent(pathname.slice(idx + marker.length));
    return path.includes('..') ? '' : path;
  } catch (e) {
    return '';
  }
}

// تنبيه بسيط بدل تجاهل الأخطاء بصمت
function showToast(message) {
  let box = document.getElementById('adminToast');
  if (!box) {
    box = document.createElement('div');
    box.id = 'adminToast';
    box.setAttribute('role', 'alert');
    box.style.cssText = 'position:fixed; bottom:20px; left:50%; transform:translateX(-50%); background:var(--bg-card); color:var(--ink); border:1px solid var(--border); border-radius:12px; padding:12px 16px; font-size:13px; z-index:9999; max-width:90vw; text-align:center; box-shadow:0 8px 24px rgba(0,0,0,.35);';
    document.body.appendChild(box);
  }
  box.textContent = message;
  box.style.display = 'block';
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => { box.style.display = 'none'; }, 4000);
}

const rejectModal = document.getElementById('rejectModal');
const customReasonInput = document.getElementById('customReasonInput');
const modalConfirmBtn = document.getElementById('modalConfirmBtn');

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
  if (!selectedReason || !rejectingTopupId) return;

  const topupId = rejectingTopupId;
  modalConfirmBtn.disabled = true;
  const originalLabel = modalConfirmBtn.textContent;
  modalConfirmBtn.textContent = 'جارِ التنفيذ...';

  // RPC ذرّية: تقفل الصف، تتأكد أنه لا يزال pending (فلا يمكن رفض طلب
  // تم تأكيده وأُضيف رصيده)، وتسجّل الإشعار وسجل النشاط في السيرفر
  const { error } = await supabaseClient.rpc('admin_reject_topup', {
    p_topup_id: topupId,
    p_reason: selectedReason
  });

  modalConfirmBtn.textContent = originalLabel;

  if (error) {
    showToast(mapTopupError(error.message));
    modalConfirmBtn.disabled = false;
    closeRejectModal();
    await loadTopups();
    return;
  }

  closeRejectModal();
  await loadTopups();
});

function openRejectModal(topupId) {
  rejectingTopupId = topupId;
  selectedReason = null;
  customReasonInput.value = '';
  customReasonInput.classList.remove('show');
  document.querySelectorAll('.reason-option').forEach(b => b.classList.remove('selected'));
  modalConfirmBtn.disabled = true;
  rejectModal.classList.add('show');
}

function closeRejectModal() {
  rejectModal.classList.remove('show');
  rejectingTopupId = null;
}

async function init() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) { window.location.href = 'login.html'; return; }

  const { data: profile, error: profileError } = await supabaseClient
    .from('profiles').select('role, is_banned').eq('id', session.user.id).maybeSingle();

  if (profileError || !profile || profile.role !== 'admin' || profile.is_banned === true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  // التحقق من صلاحية إدارة المحافظ في السيرفر (نفس الشرط المفروض داخل
  // دوال admin_confirm_topup / admin_reject_topup)
  const { data: canManageWallets, error: permError } = await supabaseClient
    .rpc('has_admin_permission', { permission_key: 'manage_wallets' });

  if (permError || canManageWallets !== true) {
    document.getElementById('accessDenied').style.display = 'block';
    return;
  }

  currentAdminId = session.user.id;

  document.getElementById('adminPage').style.display = 'block';

  document.querySelectorAll('#filterRow .chip').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#filterRow .chip').forEach(c => c.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.dataset.filter;
      render();
    });
  });

  await loadTopups();
}

async function loadTopups() {
  const { data, error } = await supabaseClient
    .from('wallet_topups')
    .select('*, profiles(full_name, whatsapp_number), payment_receipts!wallet_topups_receipt_id_fkey(amount_detected, ocr_status)')
    .order('created_at', { ascending: false });

  if (error) {
    document.getElementById('topupsList').innerHTML =
      `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">تعذّر تحميل طلبات الشحن. حدّث الصفحة وحاول مجدداً.</div>`;
    return;
  }

  allTopups = data || [];
  render();
}

function render() {
  const container = document.getElementById('topupsList');
  const filtered = currentFilter === 'all'
    ? allTopups
    : allTopups.filter(t => t.status === currentFilter);

  if (filtered.length === 0) {
    container.innerHTML = `<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 30px 0;">لا توجد طلبات في هذا التصنيف</div>`;
    return;
  }

  container.innerHTML = filtered.map(t => renderTopupCard(t)).join('');

  container.querySelectorAll('[data-action]').forEach(btn => {
    btn.addEventListener('click', () => handleAction(btn.dataset.action, btn.dataset.topupId));
  });

  // روابط الإيصالات محفوظة كـ Signed URL بمدة محدودة — نولّد رابطاً جديداً
  // عند الفتح حتى لا يختفي الإيصال بعد انتهاء صلاحية الرابط القديم
  container.querySelectorAll('.receipt-link').forEach(link => {
    link.addEventListener('click', async (e) => {
      const path = extractReceiptPath(link.dataset.receiptUrl);
      if (!path) return; // اترك الرابط الأصلي يعمل
      e.preventDefault();
      const { data, error } = await supabaseClient.storage
        .from('receipts')
        .createSignedUrl(path, 60 * 10);
      const fresh = (!error && data) ? sanitizeUrl(data.signedUrl) : '';
      window.open(fresh || link.dataset.receiptUrl, '_blank', 'noopener');
    });
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

function renderTopupCard(t) {
  const date = new Date(t.created_at).toLocaleDateString('ar-EG', {
    year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
  });

  const customerName = escapeHtml(t.profiles?.full_name || 'بدون اسم');
  const customerWhatsapp = escapeHtml(t.profiles?.whatsapp_number || '—');
  const customerWhatsappCopy = safeDataAttr(t.profiles?.whatsapp_number || '');
  const transactionReference = escapeHtml(t.transaction_reference || '');
  const transactionReferenceCopy = safeDataAttr(t.transaction_reference || '');
  const receiptUrl = sanitizeUrl(t.receipt_url);
  const safeTopupId = safeDataAttr(t.id || '');
  const rejectionReason = escapeHtml(t.rejection_reason || '');
  const statusLabel = escapeHtml(statusLabels[t.status] || t.status || '');

  // P1-FIN-001: show server-verified receipt amount next to the requested amount
  const detected = t.payment_receipts ? t.payment_receipts.amount_detected : null;
  const mismatch = detected !== null && detected !== undefined &&
    Math.abs(Number(detected) - Number(t.amount)) > Math.max(Number(detected) * 0.01, 2);
  const verifyBadge = (detected === null || detected === undefined)
    ? `<div class="order-date">المبلغ المكتشف: غير متوفر (مسار قديم)</div>`
    : `<div class="order-date">المبلغ المكتشف: ${formatSDG(detected)} ج.س ` +
      (mismatch
        ? '<span class="inactive-badge" style="color: var(--danger); background: rgba(255, 107, 107,0.15);">غير متطابق</span>'
        : '<span class="inactive-badge" style="color: var(--mm-success); background: rgba(43,237,51,0.15);">متطابق</span>') +
      `</div>`;

  const actions = t.status === 'pending' ? `
    <div class="admin-order-actions">
      <button class="admin-btn btn-confirm" data-action="confirm" data-topup-id="${safeTopupId}">تأكيد</button>
      <button class="admin-btn btn-reject" data-action="reject" data-topup-id="${safeTopupId}">رفض</button>
    </div>` : '';

  return `
    <div class="order-card">
      <div class="order-top">
        <div>
          <div class="order-product">${formatSDG(t.amount)} ج.س</div>
          <div class="order-date">${date}</div>
        </div>
        <span class="status-badge status-${safeDataAttr(t.status || '')}">${statusLabel}</span>
      </div>
      <div class="customer-info">
        <span>${customerName} — ${customerWhatsapp}</span>
        <button type="button" class="mini-copy-btn" data-copy="${customerWhatsappCopy}">نسخ الرقم</button>
      </div>
      <div class="order-details">
        ${verifyBadge}
        ${t.transaction_reference ? `
          <div class="copyable-row">
            <span>رقم العملية: ${transactionReference}</span>
            <button type="button" class="mini-copy-btn" data-copy="${transactionReferenceCopy}">نسخ</button>
          </div>
        ` : ''}
        ${receiptUrl ? `<div><a href="${escapeAttribute(receiptUrl)}" target="_blank" rel="noopener" class="receipt-link" data-receipt-url="${escapeAttribute(receiptUrl)}" style="color: var(--mm-accent-text);">عرض الإيصال</a></div>` : ''}
      </div>
      ${t.status === 'rejected' && t.rejection_reason ? `<div class="order-rejection">سبب الرفض: ${rejectionReason}</div>` : ''}
      ${actions}
    </div>
  `;
}

let actionInFlight = false;

async function handleAction(action, topupId) {
  if (action === 'confirm') {
    const topup = allTopups.find(t => t.id === topupId);
    if (!topup) return;
    if (actionInFlight) return; // منع النقر المزدوج

    actionInFlight = true;
    const btn = document.querySelector(`[data-action="confirm"][data-topup-id="${CSS.escape(topupId)}"]`);
    if (btn) { btn.disabled = true; btn.textContent = '...'; }

    // RPC ذرّية وآمنة: تقفل صف الشحنة، تتأكد إنها لسه pending، تتحقق خادمياً
    // من مطابقة المبلغ مع الإيصال (P1-FIN-001)، تضيف الرصيد، وتكتب سجل
    // الحركة والإشعار — كل ذلك في السيرفر بمعاملة واحدة
    const detectedAmt = topup.payment_receipts ? topup.payment_receipts.amount_detected : null;
    const isMismatch = detectedAmt !== null && detectedAmt !== undefined &&
      Math.abs(Number(detectedAmt) - Number(topup.amount)) > Math.max(Number(detectedAmt) * 0.01, 2);
    let overrideReason = null;
    if (isMismatch) {
      const input = window.prompt(
        `تنبيه: المبلغ المطلوب (${formatSDG(topup.amount)} ج.س) لا يطابق المبلغ المكتشف في الإيصال (${formatSDG(detectedAmt)} ج.س).\n\nللمتابعة اكتب سبب التجاوز (سيُسجَّل في سجل التدقيق)، أو اضغط إلغاء للرجوع.`
      );
      if (input === null) {
        actionInFlight = false;
        if (btn) { btn.disabled = false; btn.textContent = 'تأكيد'; }
        return;
      }
      overrideReason = input.trim();
      if (!overrideReason) {
        showToast('يجب كتابة سبب التجاوز للمتابعة.');
        actionInFlight = false;
        if (btn) { btn.disabled = false; btn.textContent = 'تأكيد'; }
        return;
      }
    }
    if (!topup.receipt_id) {
      const input = window.prompt(
        'تنبيه: طلب الشحن هذا بلا إيصال مرتبط، ولا يوجد أي دليل دفع خادمي للمبلغ.\n\nلا يمكن شحن الرصيد إلا بسبب تجاوز مكتوب يُسجَّل في سجل التدقيق. اكتب السبب للمتابعة، أو اضغط إلغاء.'
      );
      if (input === null) {
        actionInFlight = false;
        if (btn) { btn.disabled = false; btn.textContent = 'تأكيد'; }
        return;
      }
      overrideReason = (input || '').trim();
      if (!overrideReason) {
        showToast('يجب كتابة سبب التجاوز للمتابعة.', 'error');
        actionInFlight = false;
        if (btn) { btn.disabled = false; btn.textContent = 'تأكيد'; }
        return;
      }
    }
    const { error } = await supabaseClient.rpc('admin_confirm_topup', { p_topup_id: topupId, p_override_reason: overrideReason });

    actionInFlight = false;
    if (error) {
      showToast(mapTopupError(error.message));
      await loadTopups();
      return;
    }

    showToast(`تم شحن ${formatSDG(topup.amount)} ج.س لمحفظة العميل.`);
    await loadTopups();
  } else if (action === 'reject') {
    openRejectModal(topupId);
  }
}

init();
