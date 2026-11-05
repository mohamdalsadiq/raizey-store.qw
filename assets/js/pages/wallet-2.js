let currentUser = null;
let paymentMethods = [];
let receiptFile = null;
let receiptAnalysis = null;
let receiptScanContext = null;
let walletScanRevision = 0;
let savedWalletTxRef = null; // رقم العملية بعد التحقق المبكر (قبل رفع الإيصال)

const statusLabels = { pending: 'قيد المراجعة', confirmed: 'مؤكد', rejected: 'مرفوض' };

const ocrStatusLabels = {
  passed: 'فحص آلي ناجح',
  needs_admin_check: 'مقبول ويحتاج مراجعة الإدارة',
  needs_review: 'قيد المراجعة اليدوية',
  rejected: 'مرفوض'
};

const txSourceLabels = {
  topup_confirmed: 'شحن رصيد مؤكد',
  gift_card:       'استبدال كود هدية',
  order_payment:   'دفع طلب',
  order_refund:    'استرجاع مبلغ طلب',
  admin_refund:    'استرجاع من الإدارة',
  referral_commission: 'عمولة إحالة',
  loyalty_redeem:  'استبدال نقاط الولاء'
};

async function init() {
  try {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) {
      window.location.href = 'login.html';
      return;
    }
    currentUser = session.user;
  } catch (e) {
    alert('خطأ في التحقق من الجلسة، يرجى تحديث الصفحة.');
    return;
  }

  await Promise.all([loadBalance(), loadPaymentMethods(), loadTopups(), loadTransactions()]);

  document.getElementById('toggleFormBtn').addEventListener('click', () => {
    document.getElementById('topupForm').classList.toggle('show');
  });

  document.getElementById('methodSelect').addEventListener('change', (e) => {
    const method = paymentMethods.find(m => m.id === e.target.value);
    const box = document.getElementById('methodDetails');
    if (!method) { box.innerHTML = ''; return; }
    box.innerHTML = `
      <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 6px;">
        <span>اسم الحساب: ${escapeHtml(method.account_name || '')}</span>
        <button type="button" class="copy-account-btn" data-copy="${escapeHtml(method.account_name || '')}">نسخ</button>
      </div>
      <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px;">
        <span>رقم الحساب: ${escapeHtml(method.account_number || '')}</span>
        <button type="button" class="copy-account-btn" data-copy="${escapeHtml(method.account_number || '')}">نسخ</button>
      </div>
      ${method.instructions ? `<div style="margin-top: 6px;">${escapeHtml(method.instructions)}</div>` : ''}
    `;
    box.querySelectorAll('.copy-account-btn').forEach(btn => {
      btn.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(btn.dataset.copy);
          const original = btn.textContent;
          btn.textContent = 'تم النسخ'; btn.classList.add('copied');
          setTimeout(() => { btn.textContent = original; btn.classList.remove('copied'); }, 1800);
        } catch (err) {}
      });
    });
  });

  // ── الخطوة 1: التحقق المبكر من رقم العملية قبل رفع الإيصال ──
  document.getElementById('saveTxRefBtn').addEventListener('click', verifyWalletTxRef);

  // ── فحص الملف فور الاختيار (MIME + حجم + صورة صحيحة) ──
  const fileBox = document.getElementById('fileUploadBox');
  const fileInput = document.getElementById('receiptInput');
  const fileError = document.getElementById('fileError');

  fileBox.addEventListener('click', () => {
    if (!savedWalletTxRef) {
      document.getElementById('formError').textContent = 'تحقّق من رقم العملية أولاً قبل رفع صورة الإيصال.';
      return;
    }
    fileInput.click();
  });
  fileInput.addEventListener('change', async () => {
    fileError.textContent = '';
    resetReceiptScan();
    if (fileInput.files.length === 0) return;
    if (!savedWalletTxRef) {
      fileInput.value = '';
      document.getElementById('formError').textContent = 'تحقّق من رقم العملية أولاً قبل رفع صورة الإيصال.';
      return;
    }
    const file = fileInput.files[0];
    const validation = await validateReceiptImage(file);
    if (!validation.valid) {
      fileInput.value = '';
      receiptFile = null;
      document.getElementById('receiptFileLabel').innerHTML = '<svg class="mm-i" style="margin-left: 6px;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-cloud-upload"></use></svg> اضغط لرفع صورة الإيصال (JPG / PNG / WEBP — حتى 5MB)';
      fileBox.classList.remove('has-file');
      fileError.textContent = validation.message;
      return;
    }
    receiptFile = file;
    document.getElementById('receiptFileLabel').textContent = receiptFile.name;
    fileBox.classList.add('has-file');
    await runWalletReceiptScan();
  });

  // تعديل المبلغ يبطل الفحص فقط (لا يبطل التحقق من رقم العملية)
  document.getElementById('amountInput').addEventListener('input', () => {
    resetReceiptScan('غيّرت المبلغ؛ ارفع الإيصال من جديد للفحص.');
  });
  // تعديل رقم العملية يبطل التحقق المبكر ويخفي خطوة رفع الإيصال
  document.getElementById('transactionRefInput').addEventListener('input', () => {
    if (savedWalletTxRef) resetWalletTxRef('عدّلت رقم العملية؛ اضغط "تحقق" من جديد قبل رفع الإيصال.');
  });
  document.getElementById('methodSelect').addEventListener('change', () => {
    resetReceiptScan('غيّرت وسيلة التحويل؛ ارفع الإيصال من جديد للفحص.');
  });

  document.getElementById('geminiConsentWallet').addEventListener('change', () => {
    resetReceiptScan('تغير اختيار الفحص. اضغط إعادة تجهيز الإيصال.');
  });
  document.getElementById('retryWalletReceiptBtn').addEventListener('click', runWalletReceiptScan);
  document.getElementById('submitTopupBtn').addEventListener('click', submitTopup);
  document.getElementById('redeemGiftBtn').addEventListener('click', redeemGiftCard);
}

function resetReceiptScan(message) {
  walletScanRevision++;
  receiptAnalysis = null;
  receiptScanContext = null;
  const status = document.getElementById('receiptScanStatus');
  const report = document.getElementById('receiptScanReport');
  if (status) status.textContent = message || '';
  if (report) { report.hidden = true; report.style.display = 'none'; report.className = 'receipt-scan-report'; report.innerHTML = ''; }
}

// إبطال التحقق المبكر من رقم العملية وإخفاء خطوة رفع الإيصال، وإعادة زر "تحقق" لحالته
function resetWalletTxRef(message) {
  savedWalletTxRef = null;
  const btn = document.getElementById('saveTxRefBtn');
  const refInput = document.getElementById('transactionRefInput');
  const refMsg = document.getElementById('txRefMessage');
  const receiptStep = document.getElementById('receiptStep');
  if (refInput) refInput.disabled = false;
  if (btn) { btn.textContent = 'تحقق'; btn.dataset.mode = 'save'; btn.disabled = false; }
  if (receiptStep) receiptStep.style.display = 'none';
  // تنظيف أي ملف/فحص سابق حتى لا يُرسل بإيصال قديم
  receiptFile = null;
  const fileInput = document.getElementById('receiptInput');
  if (fileInput) fileInput.value = '';
  const fileBox = document.getElementById('fileUploadBox');
  if (fileBox) {
    fileBox.classList.remove('has-file');
    const lbl = document.getElementById('receiptFileLabel');
    if (lbl) lbl.innerHTML = '<svg class="mm-i" style="margin-left: 6px;" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-cloud-upload"></use></svg> اضغط لرفع صورة الإيصال (JPG / PNG / WEBP — حتى 5MB)';
  }
  resetReceiptScan('');
  if (refMsg) { refMsg.style.color = 'var(--text-muted)'; refMsg.textContent = message || ''; }
}

// التحقق المبكر (قراءة فقط، بلا حجز) — يمنع استهلاك الفحص على رقم عملية مستخدم مسبقاً
// في الدفع المباشر أو شحن سابق. الحجز النهائي الذرّي يبقى داخل create_wallet_topup_from_receipt.
async function verifyWalletTxRef() {
  const btn = document.getElementById('saveTxRefBtn');
  const refInput = document.getElementById('transactionRefInput');
  const refMsg = document.getElementById('txRefMessage');
  const receiptStep = document.getElementById('receiptStep');

  // وضع التعديل: فتح القفل لتعديل رقم العملية
  if (btn.dataset.mode === 'edit') {
    resetWalletTxRef('عدّل رقم العملية ثم اضغط "تحقق" لتأكيده مجدداً.');
    refInput.focus();
    return;
  }

  const raw = refInput.value.trim();
  const norm = window.MeemReceiptPipeline
    ? MeemReceiptPipeline.normalizeRef(raw)
    : raw.replace(/[^A-Za-z0-9]/g, '').toUpperCase();

  if (norm.length < 6) {
    refMsg.style.color = 'var(--danger)';
    refMsg.textContent = 'رقم العملية قصير جداً. انسخه كما ورد في رسالة التحويل (6 خانات على الأقل).';
    savedWalletTxRef = null;
    receiptStep.style.display = 'none';
    return;
  }

  // حد للمحاولات لمنع التخمين المتكرر
  if (typeof rateLimiter !== 'undefined' &&
      !rateLimiter.check('wallet_check_tx_ref', 8, 60 * 1000)) {
    refMsg.style.color = 'var(--danger)';
    refMsg.textContent = 'محاولات كثيرة. انتظر دقيقة ثم حاول مجدداً.';
    return;
  }

  btn.disabled = true;
  const prevText = btn.textContent;
  btn.textContent = 'جارِ التحقق...';
  refMsg.style.color = 'var(--text-muted)';
  refMsg.textContent = 'جارِ التحقق من رقم العملية...';

  try {
    const { data, error } = await supabaseClient.rpc('check_tx_ref_available', { p_tx_ref: raw });
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    if (!row) throw new Error('check_tx_ref_empty');
    if (row.available === false) {
      btn.disabled = false;
      btn.textContent = prevText;
      refMsg.style.color = 'var(--danger)';
      refMsg.textContent = row.reason === 'invalid_tx_ref'
        ? 'رقم العملية غير صحيح. انسخه كما ورد في رسالة التحويل.'
        : 'رقم العملية هذا مستخدم من قبل في شحن محفظة أو دفع طلب. اكتب رقم العملية الصحيح لتحويلك.';
      savedWalletTxRef = null;
      receiptStep.style.display = 'none';
      return;
    }
  } catch (e) {
    btn.disabled = false;
    btn.textContent = prevText;
    refMsg.style.color = 'var(--danger)';
    refMsg.textContent = walletTxRefCheckError(e);
    savedWalletTxRef = null;
    receiptStep.style.display = 'none';
    console.warn('[MEEM] wallet check_tx_ref_available failed:', e?.message || e);
    return;
  }

  // نجح التحقق: أقفل الحقل وأظهر خطوة رفع الإيصال
  savedWalletTxRef = raw;
  refInput.disabled = true;
  btn.disabled = false;
  btn.textContent = 'تعديل';
  btn.dataset.mode = 'edit';
  refMsg.style.color = 'var(--primary)';
  refMsg.textContent = 'تم التحقق من رقم العملية (غير مستخدم من قبل). ارفع الآن صورة إشعار التحويل لمطابقتها.';
  receiptStep.style.display = 'block';
  document.getElementById('formError').textContent = '';
}

function walletTxRefCheckError(error) {
  const raw = String(error?.message || error?.hint || error?.details || error || '');
  if (raw.includes('auth_required')) return 'انتهت جلسة الدخول؛ سجّل الدخول من جديد ثم أعد المحاولة.';
  if (raw.includes('check_tx_ref_available') || raw.includes('PGRST202') || raw.includes('42883')) {
    return 'خدمة التحقق من رقم العملية غير مُفعّلة على قاعدة البيانات بعد. طبّق ملف الإصلاح ثم أعد المحاولة.';
  }
  return 'تعذّر التحقق من رقم العملية (اتصال ضعيف). حاول مرة أخرى قبل رفع الإيصال.';
}

function receiptAnalysisAllowed(analysis) {
  return !!analysis && analysis.submissionAllowed === true && analysis.receiptPolicy === 'mandatory-visual-v1' &&
    analysis.automaticCheckComplete === true && analysis.decision === 'accept' && !!analysis.scanId &&
    !!analysis.receiptPath && !!analysis.attachmentId && !!analysis.receiptHash &&
    analysis.refVerified === true && analysis.amountVerified === true;
}

function renderWalletScanReport(analysis, amount, manualRef) {
  const report = document.getElementById('receiptScanReport');
  if (!report) return;
  const extracted = analysis.extracted || {};
  const rows = [
    `المبلغ المطلوب: ${formatSDG(amount)} ج.س`,
    `رقم العملية المدخل: ${manualRef}`,
    `رقم العملية المقروء: ${extracted.txRef || 'لم يُقرأ'}`,
    `المبلغ المقروء: ${extracted.amount ? formatSDG(extracted.amount) + ' ج.س' : 'لم يُقرأ'}`,
    `مطابقة رقم العملية: ${analysis.refVerified ? 'مطابق ✓' : 'غير مطابق ✗'}`,
    `مطابقة المبلغ: ${analysis.amountVerified ? 'مطابق ✓' : 'غير مطابق ✗'}`
  ];
  const technicalReview = !receiptAnalysisAllowed(analysis) && analysis.decision === 'review';
  report.className = 'receipt-scan-report ' + (technicalReview ? 'is-review' : receiptAnalysisAllowed(analysis) ? 'is-success' : 'is-error');
  report.style.display = 'block';
  report.hidden = false;
  report.innerHTML = `<strong>${window.rzIconMarkup(technicalReview ? 'clock' : receiptAnalysisAllowed(analysis) ? 'circle-check' : 'circle-x')} ${escapeHtml(analysis.message || 'تم فحص الإيصال')}</strong><div style="margin-top: 7px;">${rows.map(escapeHtml).join('<br>')}</div>`;
}

function walletReceiptContext() {
  return JSON.stringify({ amount: Number(document.getElementById('amountInput').value),
    manualRef: savedWalletTxRef, methodId: document.getElementById('methodSelect').value,
    consent: document.getElementById('geminiConsentWallet').checked });
}
async function runWalletReceiptScan() {
  const status = document.getElementById('receiptScanStatus'), errorBox = document.getElementById('formError');
  resetReceiptScan();
  const revision = walletScanRevision, context = walletReceiptContext(), file = receiptFile;
  const amount = Number(document.getElementById('amountInput').value), manualRef = savedWalletTxRef;
  const methodId = document.getElementById('methodSelect').value;
  errorBox.textContent = '';
  if (!file || !manualRef || !methodId || !Number.isFinite(amount) || amount <= 0 || amount > 10000000) {
    errorBox.textContent = 'اختر صورة ووسيلة تحويل ومبلغاً صحيحاً، وتحقق من رقم العملية أولاً.'; return;
  }
  if (!document.getElementById('geminiConsentWallet').checked) { status.textContent = 'وافق على الفحص الآلي ثم أعد فحص الصورة؛ لا يمكن الإرسال دون فحص.'; return; }
  status.textContent = 'جارِ الفحص الآلي...';
  const analysis = await MeemReceiptPipeline.analyze(file, { expectedAmount: amount, manualRef,
    expectedMethodId: methodId, onStatus: message => { status.textContent=message; } });
  if (revision !== walletScanRevision || context !== walletReceiptContext() || file !== receiptFile) return;
  renderWalletScanReport(analysis, amount, manualRef);
  if (!receiptAnalysisAllowed(analysis)) {
    status.textContent = analysis.message || 'لم يكتمل الفحص الآلي؛ لا يمكن إرسال الطلب. أعد المحاولة لاحقاً.';
    return;
  }
  receiptAnalysis = analysis; receiptScanContext = context;
  status.textContent = 'اجتاز الإشعار الفحص الآلي. اعتماد التحويل يتطلب مراجعة سجل الحساب من الإدارة.';
}

async function checkUnifiedTransactionRef(transactionRef) {
  const normalized = MeemReceiptPipeline.normalizeRef(transactionRef);
  if (normalized.length < 6) return { available: false, reason: 'invalid_tx_ref' };
  const { data, error } = await supabaseClient.rpc('check_tx_ref_available', { p_tx_ref: transactionRef });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return row || { available: false, reason: 'invalid_tx_ref' };
}

function walletReceiptErrorMessage(error) {
  const raw = String(error?.message || error?.hint || error?.details || error || '');
  if (raw.includes('duplicate_transaction_ref')) return 'رقم العملية هذا مستخدم في طلب شحن أو طلب شراء سابق.';
  if (raw.includes('duplicate_receipt_image')) return 'صورة الإيصال هذه مستخدمة في طلب سابق.';
  if (raw.includes('receipt_rejected')) return 'تم رفض الإيصال من الفحص الذكي. ارفع صورة إشعار صحيحة.';
  if (raw.includes('create_wallet_topup_from_receipt') || raw.includes('PGRST202') || raw.includes('42883')) return 'تحتاج قاعدة البيانات لتطبيق ملف supabase-SQL-المهمة-3.sql.';
  if (raw.includes('auth_required')) return 'انتهت جلسة الدخول؛ سجّل الدخول من جديد ثم أعد المحاولة.';
  return getFriendlyError(raw);
}

async function redeemGiftCard() {
  const code = document.getElementById('giftCodeInput').value.trim().toUpperCase();
  const msgBox = document.getElementById('giftMessage');
  msgBox.style.color = '';

  if (!code) {
    msgBox.style.color = 'var(--danger)';
    msgBox.textContent = 'اكتب الكود الأول';
    return;
  }

  // حد للمحاولات (5 محاولات كل دقيقة) لمنع تخمين أكواد الهدايا
  if (typeof rateLimiter !== 'undefined' &&
      !rateLimiter.check('redeem_gift', 5, 60 * 1000)) {
    msgBox.style.color = 'var(--danger)';
    msgBox.textContent = 'محاولات كثيرة. انتظر دقيقة ثم حاول مجدداً.';
    return;
  }

  const btn = document.getElementById('redeemGiftBtn');
  btn.disabled = true;
  const originalLabel = btn.textContent;
  btn.textContent = '...';

  try {
    const { data, error } = await supabaseClient.rpc('redeem_gift_card', { p_code: code });

    if (error) {
      const raw = (error.message || '');
      msgBox.style.color = 'var(--danger)';
      msgBox.textContent = raw.includes('access_denied')
        ? 'حسابك غير مسموح له بهذه العملية.'
        : (raw.includes('مستهلك') || raw.includes('already_redeemed'))
          ? 'الكود ده مستخدم بالفعل أو غير صحيح'
          : 'الكود غير صحيح';
      return;
    }

    // الـ RPC يرجع صفوفاً: [{ amount }] — لا يصح تمريره مباشرة لـ formatSDG
    const rows = Array.isArray(data) ? data : (data ? [data] : []);
    const creditedAmount = Number(
      rows.length ? (rows[0] && typeof rows[0] === 'object' ? rows[0].amount : rows[0]) : 0
    );

    msgBox.style.color = 'var(--primary)';
    msgBox.textContent = Number.isFinite(creditedAmount) && creditedAmount > 0
      ? `تم إضافة ${formatSDG(creditedAmount)} ج.س لرصيدك`
      : 'تم استبدال الكود بنجاح';
    document.getElementById('giftCodeInput').value = '';
    await Promise.all([loadBalance(), loadTransactions()]);
  } catch (e) {
    msgBox.style.color = 'var(--danger)';
    msgBox.textContent = 'حصل خطأ أثناء استبدال الكود، حاول مرة أخرى.';
  } finally {
    btn.disabled = false;
    btn.textContent = originalLabel;
  }
}

async function loadBalance() {
  try {
    const { data } = await supabaseClient
      .from('wallets')
      .select('balance')
      .eq('user_id', currentUser.id)
      .single();
    document.getElementById('balanceAmount').innerHTML = `${formatSDG(data ? data.balance : 0)} <small>ج.س</small>`;
  } catch (e) {
    document.getElementById('balanceAmount').textContent = '—';
  }
}

// سجل حركات الرصيد — يُكتب في القاعدة فقط عبر دوال SECURITY DEFINER،
// والعميل يقرأه للقراءة فقط (لا يمكن تعديله أو حذفه من المتصفح)
async function loadTransactions() {
  const container = document.getElementById('transactionsList');
  try {
    const { data, error } = await supabaseClient
      .from('wallet_transactions')
      .select('amount, direction, balance_after, source, created_at')
      .eq('user_id', currentUser.id)
      .order('created_at', { ascending: false })
      .limit(50);

    if (error) throw error;

    if (!data || data.length === 0) {
      container.innerHTML = `<div style="text-align: center; padding: 20px; color: var(--text-muted);">لا توجد حركات على رصيدك بعد</div>`;
      return;
    }

    container.innerHTML = data.map(tx => {
      const date = new Date(tx.created_at).toLocaleDateString('ar-EG', {
        year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
      });
      const isCredit = tx.direction === 'credit';
      const sign = isCredit ? '+' : '−';
      const color = isCredit ? 'var(--primary)' : 'var(--danger)';
      const label = txSourceLabels[tx.source] || 'حركة رصيد';
      const balanceAfter = (tx.balance_after === null || tx.balance_after === undefined)
        ? '' : `<div class="order-date">الرصيد بعدها: ${formatSDG(tx.balance_after)} ج.س</div>`;
      return `
        <div class="order-card">
          <div class="order-top">
            <div>
              <div class="order-product">${escapeHtml(label)}</div>
              <div class="order-date">${escapeHtml(date)}</div>
              ${balanceAfter}
            </div>
            <span style="font-family: var(--font-mono); font-weight: 700; color:${color};">${sign}${formatSDG(Math.abs(Number(tx.amount) || 0))}</span>
          </div>
        </div>
      `;
    }).join('');
  } catch (e) {
    container.innerHTML = `<div style="text-align: center; padding: 20px; color: var(--text-muted);">تعذّر تحميل حركات الرصيد.</div>`;
  }
}

async function loadPaymentMethods() {
  try {
    const { data } = await supabaseClient
      .from('payment_methods')
      .select('*')
      .eq('is_active', true);
    paymentMethods = data || [];

    const select = document.getElementById('methodSelect');
    paymentMethods.forEach(m => {
      const opt = document.createElement('option');
      opt.value = m.id;
      opt.textContent = m.name;
      select.appendChild(opt);
    });
  } catch (e) {
    console.error('[MEEM] loadPaymentMethods error:', e);
  }
}

async function loadTopups() {
  try {
    const { data: topups, error } = await supabaseClient
      .from('wallet_topups')
      .select('*')
      .eq('user_id', currentUser.id)
      .order('created_at', { ascending: false });

    const container = document.getElementById('topupsList');

    if (error || !topups || topups.length === 0) {
      container.innerHTML = `<div style="text-align: center; padding: 20px; color: var(--text-muted);">لا يوجد طلبات شحن بعد</div>`;
      return;
    }

    container.innerHTML = topups.map(t => {
      const date = new Date(t.created_at).toLocaleDateString('ar-EG', {
        year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
      });
      return `
        <div class="order-card">
          <div class="order-top">
            <div>
              <div class="order-product">${formatSDG(t.amount)} ج.س</div>
              <div class="order-date">${date}</div>
            </div>
            <span class="status-badge status-${escapeHtml(t.status)}">${escapeHtml(statusLabels[t.status] || t.status)}</span>
          </div>
          ${t.status === 'rejected' && t.rejection_reason ? `
            <div class="order-rejection">سبب الرفض: ${escapeHtml(t.rejection_reason)}</div>
          ` : ''}
        </div>
      `;
    }).join('');
  } catch (e) {
    document.getElementById('topupsList').innerHTML = `<div style="text-align: center; padding: 20px; color: var(--text-muted);">تعذّر تحميل سجل الشحن.</div>`;
  }
}

async function submitTopup() {
  const errorBox = document.getElementById('formError');
  const fileError = document.getElementById('fileError');
  errorBox.textContent = '';
  errorBox.style.color = '';
  fileError.textContent = '';

  const amount = parseFloat(document.getElementById('amountInput').value);
  const methodId = document.getElementById('methodSelect').value;

  if (!Number.isFinite(amount) || amount <= 0) {
    errorBox.textContent = 'أدخل مبلغ صحيح';
    return;
  }
  // نفس الحد المفروض في سياسة قاعدة البيانات — رسالة أوضح للمستخدم
  if (amount > 10000000) {
    errorBox.textContent = 'المبلغ أكبر من الحد المسموح.';
    return;
  }
  if (!methodId) {
    errorBox.textContent = 'اختر وسيلة التحويل';
    return;
  }
  if (!receiptFile) {
    errorBox.textContent = 'ارفع صورة الإيصال';
    return;
  }
  if (!savedWalletTxRef) {
    errorBox.textContent = 'تحقّق من رقم العملية أولاً قبل إرسال طلب الشحن.';
    return;
  }
  if (!receiptAnalysis || !receiptAnalysisAllowed(receiptAnalysis)) {
    errorBox.textContent = 'انتظر اكتمال فحص الإيصال قبل إرسال طلب الشحن.';
    return;
  }
  const transactionRef = savedWalletTxRef || document.getElementById('transactionRefInput').value.trim();
  if (!transactionRef) {
    errorBox.textContent = 'اكتب رقم العملية من رسالة التحويل';
    return;
  }

  // ── فحص إضافي قبل الرفع (تأكيد نوع MIME وحجم الملف) ──
  const validation = await validateReceiptImage(receiptFile);
  if (!validation.valid) {
    fileError.textContent = validation.message;
    return;
  }

  // حد للإرسال (3 طلبات كل 5 دقائق) لمنع إغراق طاولة الشحن
  if (typeof rateLimiter !== 'undefined' &&
      !rateLimiter.check('submit_topup', 3, 5 * 60 * 1000)) {
    errorBox.textContent = 'أرسلت طلبات كثيرة. انتظر قليلاً ثم حاول مجدداً.';
    return;
  }

  const submitBtn = document.getElementById('submitTopupBtn');
  submitBtn.disabled = true;
  submitBtn.textContent = 'جارِ التحقق...';

  const receiptHash = receiptAnalysis.receiptHash;
  const filePath = receiptAnalysis.receiptPath;
  if (!filePath || receiptScanContext !== walletReceiptContext()) {
    errorBox.textContent = 'تغيرت بيانات التحويل. أعد تجهيز الإيصال قبل الإرسال.';
    submitBtn.disabled = false; submitBtn.textContent = 'إرسال طلب الشحن'; return;
  }

  // ── حجز الإيصال وإنشاء طلب الشحن في RPC موحّد ──
  try {
    const scan = receiptAnalysis || {};
    const extracted = scan.extracted || {};
    const { error } = await supabaseClient.rpc('create_wallet_topup_from_receipt', {
      p_amount: amount,
      p_payment_method_id: methodId,
      p_receipt_url: 'receipts/' + filePath,
      p_tx_ref: transactionRef,
      p_receipt_hash: receiptHash,
      p_receipt_path: filePath,
      p_provider: scan.provider || scan.providerName || null,
      p_amount_detected: extracted.amount || null,
      p_tx_ref_ocr: extracted.txRef || null,
      p_ocr_status: scan.ocrStatus || (isTechnicalReceiptReview(scan) ? 'needs_review' : 'needs_admin_check'),
      p_ocr_confidence: scan.confidence ?? null,
      p_risk_flags: scan.riskFlags || [],
      p_ocr_data: Object.assign({}, extracted, {
        engine_version: scan.version || null,
        engine_source: scan.source || 'receipt-pipeline',
        provider_name: scan.providerName || null,
        language: scan.language || null,
        passes: scan.passes || 0,
        text_length: scan.textLength || 0,
        ref_verified: !!scan.refVerified,
        amount_verified: !!scan.amountVerified,
        decision: scan.decision || null,
        scan_message: scan.message || null,
        edge_scan_id: scan.scanId || null,
        edge_receipt_hash: scan.receiptHash || null
      })
    });
    if (error) throw error;
  } catch (e) {
    const errMsg = e.message || String(e);
    devWarn('[MEEM] create_wallet_topup_from_receipt error:', errMsg);
    errorBox.textContent = walletReceiptErrorMessage(e);
    submitBtn.disabled = false;
    submitBtn.textContent = 'إرسال طلب الشحن';
    return;
  }

  // إعادة ضبط النموذج بعد النجاح
  document.getElementById('topupForm').classList.remove('show');
  document.getElementById('amountInput').value = '';
  document.getElementById('methodSelect').value = '';
  document.getElementById('transactionRefInput').value = '';
  document.getElementById('methodDetails').innerHTML = '';
  receiptAnalysis = null;
  receiptScanContext = null;
  // إعادة التحقق المبكر لحالته الأولى (زر "تحقق"، إخفاء خطوة رفع الإيصال، تنظيف الملف)
  resetWalletTxRef('');
  document.getElementById('txRefMessage').textContent = '';
  submitBtn.disabled = false;
  submitBtn.textContent = 'إرسال طلب الشحن';

  await loadTopups();
}

init();
