let cart = [];
let currentUser = null;
let walletBalance = 0;
let paymentMethods = [];
let selectedPayment = null;
let selectedMethodId = null;
let receiptFile = null;
let appliedCoupon = null;
let savedTxRef = null;      // رقم العملية بعد الحفظ
let checkoutScanRevision = 0;
let checkoutScanBusy = false;
let checkoutScanContext = null;
let scanResult = null;      // نتيجة الفحص الذكي للصورة الحالية
let isDirectBuy = false;    // شراء مباشر (زر "اشترِ الآن") — لا علاقة له بالسلة
let selectedMethodAccount = null;  // رقم حساب الوسيلة المختارة (للتحقق من جهة الإيداع)
let verifiedPaymentCode = null;    // رمز الدفع بعد التحقق منه من الإدارة
let splitPayment = null;           // دفع مجزّأ: {firstFile, firstScan, secondFile, secondScan, secondRef, remaining}

function checkoutReceiptContext() {
  return JSON.stringify({ total: currentTotal(), method: selectedMethodId, ref: savedTxRef,
    coupon: appliedCoupon?.code || null, consent: window.MeemReceiptConsent.context() });
}
function invalidateCheckoutReceipt() {
  checkoutScanRevision++; scanResult = null; checkoutScanContext = null; splitPayment = null;
  const report = document.getElementById('scanReport'); if (report) report.style.display = 'none';
  const status = document.getElementById('scanStatus');
  if (status && receiptFile) status.textContent = 'تغيرت بيانات الدفع؛ اضغط إعادة تجهيز الإيصال.';
}

function safeFormatSDG(val) {
  if (typeof formatSDG === 'function') return formatSDG(val);
  return Math.round(val).toLocaleString('ar-EG');
}

// ── حرس زمني على كل استدعاء شبكة ──
// سبب وجوده: أي await على الشبكة بدون مهلة قد ينتظر للأبد (شبكة معلّقة،
// استجابة لا تصل) فيبقى الزر عالقاً على "جارِ تسجيل الإيصال..." بلا نهاية.
// الآن كل خطوة (رفع الصورة، الرابط الموقّع، إنشاء الطلب) لها سقف زمني
// ينتهي بخطأ واضح يُرجع الزر لحالته الطبيعية.
const NET_TIMEOUT_MS = {
  upload:  45000,   // رفع صورة قد يكون بطيئاً على شبكة الجوال
  signUrl: 20000,
  rpc:     25000
};

function withNetTimeout(promise, ms, tag) {
  let timer = null;
  const guard = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error('network_timeout:' + tag);
      err.isTimeout = true;
      reject(err);
    }, ms);
  });
  return Promise.race([Promise.resolve(promise), guard])
    .finally(() => { if (timer) clearTimeout(timer); });
}

// ── تشخيص الأخطاء الصامتة ──
// لوقات التطوير مُعطّلة على نطاق الإنتاج (vercel.app)، فكان أي خطأ غير
// معروف يظهر كرسالة عامة بلا أي دليل يمكن تتبّعه. هذه الدوال تُخرج رمزاً
// تقنياً قصيراً وآمناً (لا يكشف بيانات) يُلحق بالرسالة ليُمكن تشخيصه.
function errRaw(err) {
  if (!err) return '';
  return String((err && (err.message || err.hint || err.details)) || err);
}

function errIsMissingFunction(err) {
  const msg  = errRaw(err).toLowerCase();
  const code = (err && err.code) || '';
  return code === 'PGRST202' || code === '42883' ||
         (msg.includes('function') &&
          (msg.includes('does not exist') || msg.includes('could not find') || msg.includes('schema cache')));
}

// خطأ تعارض متغيّرات PL/pgSQL: عمود RETURNS TABLE يحمل نفس اسم عمود الجدول
function errIsAmbiguous(err) {
  const msg = errRaw(err).toLowerCase();
  return (err && err.code === '42702') || msg.includes('is ambiguous');
}

function errTechCode(err) {
  const code = (err && err.code) ? String(err.code) : '';
  const raw  = errRaw(err).replace(/\s+/g, ' ').slice(0, 90);
  if (code && raw) return `${code}: ${raw}`;
  return code || raw || 'unknown';
}

// رسالة موحّدة للأخطاء التقنية التي تعني "قاعدة البيانات تحتاج تحديثاً"
const DB_UPDATE_HINT = 'يحتاج تحديث قاعدة البيانات (شغّل ملف supabase-critical-fixes-8.sql في Supabase → SQL Editor).';



async function init() {
  // ── وضع الشراء المباشر: منفصل تماماً عن سلة المشتريات ولا يُدمج معها ──
  try {
    const raw = sessionStorage.getItem('meem_direct_buy');
    if (raw) {
      const d = JSON.parse(raw);
      const fresh = d && d.created_at && (Date.now() - d.created_at) < 30 * 60 * 1000;
      if (fresh && Array.isArray(d.items) && d.items.length) {
        cart = d.items;
        isDirectBuy = true;
      } else {
        sessionStorage.removeItem('meem_direct_buy');
      }
    }
  } catch (e) { sessionStorage.removeItem('meem_direct_buy'); }

  if (!isDirectBuy) {
    try {
      cart = JSON.parse(localStorage.getItem('meem_store_cart')) || [];
    } catch (e) {
      cart = [];
    }
  }

  if (!Array.isArray(cart)) cart = [];
  if (cart.length && MeemStoreRules.cartError(cart)) {
    document.getElementById('loadingBox').textContent = MeemStoreRules.cartError(cart) + ' ارجع إلى السلة لتعديل الكمية قبل الدفع.'; return;
  }
  if (cart.length === 0) {
    document.getElementById('loadingBox').innerHTML = `
      <div style="text-align: center; padding: 40px 0;">
        <p style="color: var(--text-muted); margin-bottom: 15px;">سلة المشتريات فارغة حالياً</p>
        <a href="index.html" class="auth-btn" style="text-decoration: none; display: inline-block; padding: 10px 20px;">تصفح المنتجات</a>
      </div>
    `;
    return;
  }

  try {
    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) {
      sessionStorage.setItem('redirect_after_login', window.location.href);
      window.location.href = 'login.html';
      return;
    }
    currentUser = session.user;
  } catch (e) {
    document.getElementById('loadingBox').textContent = 'خطأ في التحقق من الجلسة، يرجى تحديث الصفحة.';
    return;
  }

  try {
    const [{ data: wallet, error: walletErr }, { data: methods, error: methodsErr }] = await Promise.all([
      supabaseClient.from('wallets').select('balance').eq('user_id', currentUser.id).single(),
      supabaseClient.from('payment_methods').select('*').eq('is_active', true)
    ]);
    if (walletErr) console.warn('[MEEM] Wallet fetch error:', walletErr.message);
    if (methodsErr) console.warn('[MEEM] Methods fetch error:', methodsErr.message);
    walletBalance = wallet ? wallet.balance : 0;
    paymentMethods = methods || [];
  } catch (e) {
    console.error('[MEEM] init data fetch error:', e);
  }

  renderCheckout();
}

function currentTotal() {
  const raw = cart.reduce((sum, item) => {
    const qty = (item.quantity && item.quantity > 0) ? item.quantity : 1;
    const price = parseFloat(item.price_sdg) || 0;
    return sum + (price * qty);
  }, 0);

  if (appliedCoupon) {
    return Math.round(raw - (raw * appliedCoupon.discount_percent / 100));
  }
  return Math.round(raw);
}

function renderCheckout() {
  document.getElementById('loadingBox').style.display = 'none';
  document.getElementById('checkoutContent').style.display = 'block';

  document.getElementById('checkoutTotal').textContent = safeFormatSDG(currentTotal()) + ' ج.س';

  const listContainer = document.getElementById('checkoutItemsList');
  listContainer.innerHTML = cart.map(item => {
    const qty = (item.quantity && item.quantity > 0) ? item.quantity : 1;
    const unitPrice = parseFloat(item.price_sdg) || 0;
    const lineSubtotal = unitPrice * qty;

    let optionHtml = '';
    if (item.selected_option && item.selected_option.label) {
      optionHtml = `<div class="checkout-item-fields"><svg class="mm-i" style="color: var(--accent-gold, var(--mm-accent-text));" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-list-checks"></use></svg> <strong>الخيار المختار:</strong> ${escapeHtml(item.selected_option.label)}</div>`;
    }

    let fieldsHtml = '';
    if (item.field_values && Object.keys(item.field_values).length > 0) {
      fieldsHtml = `<div class="checkout-item-fields">`;
      for (const [key, value] of Object.entries(item.field_values)) {
        // عرض الاسم الحقيقي للحقل بدلاً من المعرّف الخام
        const label = (item.field_labels && item.field_labels[key]) ? item.field_labels[key] : key;
        fieldsHtml += `<div>• <strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</div>`;
      }
      fieldsHtml += `</div>`;
    }

    const itemKey = item.cart_item_id || item.product_id;

    return `
      <div class="checkout-item" id="item_${escapeHtml(itemKey)}">
        <button class="remove-item-btn" data-remove-checkout="${escapeAttribute(itemKey)}">
          <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-trash-2"></use></svg>
        </button>
        <div class="checkout-item-thumb">
          ${item.image_url ? `<img src="${escapeAttribute(sanitizeUrl(item.image_url))}" alt="${escapeAttribute(item.name)}">` : '<svg class="mm-i" style="font-size: 22px; color: var(--text-muted);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-package"></use></svg>'}
        </div>
        <div class="checkout-item-info">
          <div class="checkout-item-name">${escapeHtml(item.name)}</div>
          <div class="checkout-item-price">${safeFormatSDG(unitPrice)} ج.س &times; ${qty} = <strong>${safeFormatSDG(lineSubtotal)} ج.س</strong></div>
          ${optionHtml}
          ${fieldsHtml}
        </div>
      </div>
    `;
  }).join('');

  listContainer.querySelectorAll('[data-remove-checkout]').forEach(button => {
    button.addEventListener('click', () => removeItemFromCheckout(button.dataset.removeCheckout));
  });
  const walletOption = document.getElementById('walletOption');
  const walletText = document.getElementById('walletBalanceText');
  const canUseWallet = walletBalance >= currentTotal();
  walletText.onclick = event => { if (event.target.closest('[data-recharge-link]')) event.stopPropagation(); };

  if (canUseWallet) {
    walletOption.classList.remove('disabled');
    walletText.innerHTML = `رصيدك الحالي: ${safeFormatSDG(walletBalance)} ج.س (يكفي للدفع)`;
  } else {
    walletOption.classList.add('disabled');
    walletText.innerHTML = `رصيدك غير كافٍ (${safeFormatSDG(walletBalance)} ج.س) — <a href="wallet.html" class="recharge-highlight-link" data-recharge-link="true">اشحن محفظتك الآن</a>`;
  }

  const methodPickerGrid = document.getElementById('methodPickerGrid');
  methodPickerGrid.innerHTML = paymentMethods.map(m => {
    const iconUrl = typeof sanitizeUrl === 'function' ? sanitizeUrl(m.icon_url) : '';
    const icon = iconUrl
      ? `<img src="${escapeAttribute(iconUrl)}" alt="" width="48" height="48" decoding="async" loading="lazy" data-payment-icon>`
      : `<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-landmark"></use></svg>`;
    return `<button type="button" class="method-card" data-method-id="${escapeAttribute(m.id || '')}" aria-pressed="false">
      <span class="method-card-icon" aria-hidden="true">${icon}</span>
      <span class="method-card-name">${escapeHtml(m.name || '')}</span>
    </button>`;
  }).join('');
  methodPickerGrid.querySelectorAll('.method-card').forEach(card => {
    card.addEventListener('click', () => {
      methodPickerGrid.querySelectorAll('.method-card').forEach(c => { c.classList.remove('active'); c.setAttribute('aria-pressed', 'false'); });
      card.classList.add('active');
      card.setAttribute('aria-pressed', 'true');
      invalidateCheckoutReceipt();
      selectedMethodId = card.dataset.methodId;
      const m = paymentMethods.find(x => x.id === selectedMethodId);
      selectedMethodAccount = m ? (m.account_number || null) : null;
      const box = document.getElementById('selectedMethodDetails');
      const selIconUrl = m && typeof sanitizeUrl === 'function' ? sanitizeUrl(m.icon_url) : '';
      const selIcon = selIconUrl
        ? `<img src="${escapeAttribute(selIconUrl)}" alt="" width="48" height="48" decoding="async" loading="lazy" data-payment-icon>`
        : `<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-landmark"></use></svg>`;
      box.innerHTML = `
        <div class="selected-method-box">
          <div class="selected-method-head">
            <span class="method-card-icon" aria-hidden="true">${selIcon}</span>
            <span class="method-card-name">${escapeHtml(m.name || '')}</span>
          </div>
          <div class="bank-account-row">
            <span>اسم الحساب: ${escapeHtml(m.account_name || '')}</span>
            <button type="button" class="copy-account-btn" data-copy="${safeDataAttr(m.account_name || '')}">نسخ</button>
          </div>
          <div class="bank-account-row" style="margin-bottom: 0;">
            <span>رقم الحساب: <bdi class="mm-number" dir="ltr">${escapeHtml(m.account_number || '')}</bdi></span>
            <button type="button" class="copy-account-btn" data-copy="${safeDataAttr(m.account_number || '')}">نسخ</button>
          </div>
          ${m.instructions ? `<div style="color: var(--text-muted); font-size: 14px; margin-top: 8px;">${escapeHtml(m.instructions)}</div>` : ''}
        </div>
      `;
      box.querySelectorAll('.copy-account-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(btn.dataset.copy);
            const original = btn.textContent;
            btn.textContent = 'تم النسخ'; btn.classList.add('copied');
            setTimeout(() => { btn.textContent = original; btn.classList.remove('copied'); }, 1800);
          } catch (e) {}
        });
      });
    });
  });

  attachCheckoutEvents(canUseWallet);
}

async function applyCoupon() {
  invalidateCheckoutReceipt();
  appliedCoupon = null;
  const code = document.getElementById('couponInput').value.trim().toUpperCase();
  const msgBox = document.getElementById('couponMessage');
  msgBox.style.color = '';
  if (!code) { msgBox.style.color = 'var(--danger)'; msgBox.textContent = 'يرجى إدخال كود الخصم أولاً'; return; }
  try {
    const { data, error } = await supabaseClient.rpc('validate_coupon', { p_code: code, p_order_total: currentTotal() });
    if (error || !data || data.length === 0) {
      appliedCoupon = null;
      msgBox.style.color = 'var(--danger)'; msgBox.textContent = 'الكود غير صالح أو منتهي الصلاحية';
      document.getElementById('checkoutTotal').textContent = safeFormatSDG(currentTotal()) + ' ج.س';
      return;
    }
    appliedCoupon = { code, coupon_id: data[0].coupon_id, discount_percent: data[0].discount_percent };
    msgBox.style.color = 'var(--primary)'; msgBox.textContent = `تم تطبيق خصم ${appliedCoupon.discount_percent}% بنجاح!`;
    document.getElementById('checkoutTotal').textContent = safeFormatSDG(currentTotal()) + ' ج.س';
  } catch (e) {
    msgBox.style.color = 'var(--danger)';
    msgBox.textContent = 'حصل خطأ أثناء التحقق من الكود، حاول مرة أخرى.';
  }
}

function attachCheckoutEvents(canUseWallet) {
  const walletOption = document.getElementById('walletOption');
  const bankOption = document.getElementById('bankOption');
  const bankDetails = document.getElementById('bankDetails');
  const fileBox = document.getElementById('fileUploadBox');
  const fileInput = document.getElementById('receiptInput');
  const placeOrderBtn = document.getElementById('placeOrderBtn');
  document.getElementById('couponInput').oninput = () => { appliedCoupon = null; invalidateCheckoutReceipt(); document.getElementById('checkoutTotal').textContent = safeFormatSDG(currentTotal()) + ' ج.س'; };
  window.MeemReceiptConsent.bindChange(invalidateCheckoutReceipt);
  document.getElementById('retryCheckoutReceiptBtn').onclick = () => runScan(receiptFile || fileInput.files[0], null);
  const errorBox = document.getElementById('formError');

  if (canUseWallet) {
    walletOption.onclick = () => {
      selectedPayment = 'wallet';
      walletOption.classList.add('selected');
      bankOption.classList.remove('selected');
      bankDetails.classList.remove('show');
    };
  } else {
    // الصندوق نفسه معطّل الضغط (pointer-events:none في CSS)؛ الوحيد
    // القابل للضغط هو رابط "اشحن محفظتك الآن" (له href مباشر + pointer-events:auto).
    walletOption.onclick = null;
  }

  const codeOption  = document.getElementById('codeOption');
  const codeDetails = document.getElementById('codeDetails');

  if (canUseWallet) {
    const prevWalletClick = walletOption.onclick;
    walletOption.onclick = () => {
      if (prevWalletClick) prevWalletClick();
      codeOption.classList.remove('selected');
      codeDetails.classList.remove('show');
    };
  }

  bankOption.onclick = () => {
    selectedPayment = 'bank';
    bankOption.classList.add('selected');
    walletOption.classList.remove('selected');
    codeOption.classList.remove('selected');
    codeDetails.classList.remove('show');
    bankDetails.classList.add('show');
  };

  codeOption.onclick = () => {
    selectedPayment = 'code';
    codeOption.classList.add('selected');
    walletOption.classList.remove('selected');
    bankOption.classList.remove('selected');
    bankDetails.classList.remove('show');
    codeDetails.classList.add('show');
  };

  // ── التحقق من رمز الدفع الصادر من الإدارة ──
  const codeInput = document.getElementById('paymentCodeInput');
  const codeMsg   = document.getElementById('paymentCodeMessage');
  const codeBtn   = document.getElementById('verifyCodeBtn');

  const CODE_REASONS = {
    not_found:      'الرمز غير موجود. تأكد من كتابته كما أرسلته الإدارة.',
    already_used:   'هذا الرمز مستخدم من قبل.',
    expired:        'انتهت صلاحية هذا الرمز. اطلب رمزاً جديداً من الإدارة.',
    not_your_code:  'هذا الرمز مخصص لعميل آخر.',
    amount_too_low: 'قيمة الرمز أقل من إجمالي طلبك.',
    cancelled:      'تم إلغاء هذا الرمز من الإدارة.'
  };

  codeInput.addEventListener('input', () => {
    verifiedPaymentCode = null;
    codeMsg.textContent = '';
  });

  codeBtn.onclick = async () => {
    const raw = codeInput.value.trim().toUpperCase();
    verifiedPaymentCode = null;
    if (raw.length < 4) {
      codeMsg.style.color = 'var(--danger)';
      codeMsg.textContent = 'اكتب رمز الدفع كاملاً.';
      return;
    }
    codeBtn.disabled = true;
    codeMsg.style.color = 'var(--text-muted)';
    codeMsg.textContent = 'جارِ التحقق من الرمز...';
    try {
      const { data, error } = await withNetTimeout(
        supabaseClient.rpc('validate_payment_code', { p_code: raw }),
        NET_TIMEOUT_MS.rpc, 'validate_payment_code'
      );
      if (error) throw error;
      const row = Array.isArray(data) ? data[0] : data;
      if (!row || row.valid !== true) {
        codeMsg.style.color = 'var(--danger)';
        codeMsg.textContent = CODE_REASONS[row && row.reason] || 'الرمز غير صالح للاستخدام.';
        return;
      }
      if (Number(row.amount) < currentTotal()) {
        codeMsg.style.color = 'var(--danger)';
        codeMsg.textContent = `قيمة الرمز (${safeFormatSDG(row.amount)} ج.س) أقل من إجمالي الطلب (${safeFormatSDG(currentTotal())} ج.س).`;
        return;
      }
      verifiedPaymentCode = raw;
      codeMsg.style.color = 'var(--primary)';
      codeMsg.textContent = `الرمز صالح ✓ — قيمته ${safeFormatSDG(row.amount)} ج.س. اضغط "تأكيد الدفع" لإتمام الطلب.`;
    } catch (e) {
      devWarn('[MEEM] validate_payment_code failed:', errRaw(e));
      codeMsg.style.color = 'var(--danger)';
      if (e && e.isTimeout) {
        codeMsg.textContent = 'انتهت مهلة الاتصال أثناء التحقق من الرمز. تحقق من الشبكة وحاول مجدداً.';
      } else if (errIsMissingFunction(e)) {
        // خدمة الرمز غير منشورة على القاعدة — ليست مشكلة اتصال
        codeMsg.textContent = 'خدمة رمز الدفع غير مُنشأة على قاعدة البيانات بعد. ' + DB_UPDATE_HINT;
      } else if (errIsAmbiguous(e)) {
        codeMsg.textContent = 'خطأ في دالة التحقق من الرمز على قاعدة البيانات. ' + DB_UPDATE_HINT;
      } else {
        codeMsg.textContent = `تعذّر التحقق من الرمز حالياً. تحقق من الاتصال وحاول مجدداً. [${errTechCode(e)}]`;
      }
    } finally {
      codeBtn.disabled = false;
    }
  };

  // ── دعم العملاء عبر واتساب — الرقم يُقرأ من settings (whatsapp_number) ──
  let ADMIN_WHATSAPP = '249901815039'; // قيمة احتياطية حتى يصل الرقم من القاعدة
  if (window.MeemStore && typeof window.MeemStore.getWhatsapp === 'function') {
    window.MeemStore.getWhatsapp().then(function (n) { if (n) ADMIN_WHATSAPP = n; });
  }

  const supportBox = document.getElementById('supportBox');
  function showSupportButton(reasonLabel) {
    if (!ADMIN_WHATSAPP || ADMIN_WHATSAPP.indexOf('YOUR_') === 0) { supportBox.style.display = 'none'; return; }
    const ref = (typeof savedTxRef !== 'undefined' && savedTxRef) ? savedTxRef : '—';
    const amount = (typeof currentTotal === 'function') ? currentTotal() : '';
    const msg = `مرحباً، واجهت مشكلة في الدفع بمتجر MEEM STORE.\nالسبب: ${reasonLabel}\nرقم العملية المُدخل: ${ref}\nالمبلغ: ${amount} ج.س`;
    supportBox.innerHTML = `<a href="https://wa.me/${ADMIN_WHATSAPP}?text=${encodeURIComponent(msg)}" target="_blank" rel="noopener"
      style="display: inline-flex; align-items: center; gap: 8px; background: #25D366; color: var(--mm-silver); padding: 10px 18px; border-radius: 12px; font-weight: 800; font-size: 14px; text-decoration: none;">
      <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-whatsapp"></use></svg> تواصل مع خدمة العملاء
    </a>`;
    supportBox.style.display = 'block';
  }
  function hideSupportButton() { supportBox.style.display = 'none'; }

  // تسجيل محاولة مشبوهة (تكرار/رفض) في قاعدة البيانات — ثانوي، لا يُوقف تدفق الصفحة أبداً
  async function logFraudAttempt(reason, extra) {
    try {
      await supabaseClient.rpc('log_receipt_fraud_attempt', {
        p_entered_reference: (typeof savedTxRef !== 'undefined' ? savedTxRef : null),
        p_reason:            reason,
        p_provider:          (scanResult && scanResult.provider) || null,
        p_ocr_excerpt:       (scanResult && scanResult.rawExcerpt) ? String(scanResult.rawExcerpt).slice(0, 300) : null,
        p_order_amount:      (typeof currentTotal === 'function') ? currentTotal() : null,
        p_metadata:          extra || {}
      });
    } catch (e) { /* التسجيل ثانوي، لا نعطّل العميل بسببه */ }
  }

  // 🔴 إصلاح جذري لتعليق الزر:
  // handlePlaceOrder دالة خارج نطاق attachCheckoutEvents، وكانت تنادي
  // showSupportButton / logFraudAttempt وهما محليتان هنا ⇒ ReferenceError
  // داخل بلوك catch يقطع التنفيذ قبل السطرين اللذين يُرجعان الزر لحالته،
  // فيبقى الزر عالقاً على "جارِ تسجيل الإيصال..." للأبد. نُصدّرهما الآن.
  window.__meemShowSupport = showSupportButton;
  window.__meemHideSupport = hideSupportButton;
  window.__meemLogFraud    = logFraudAttempt;


  const refInput   = document.getElementById('transactionRefInput');
  const refMsg     = document.getElementById('txRefMessage');
  const saveRefBtn = document.getElementById('saveTxRefBtn');
  const receiptStep = document.getElementById('receiptStep');

  function resetReceiptSelection() {
    invalidateCheckoutReceipt();
    receiptFile = null;
    scanResult  = null;
    fileInput.value = '';
    fileBox.innerHTML = `<svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-paperclip"></use></svg> اضغط هنا لرفع صورة إيصال التحويل`;
    fileBox.classList.remove('has-file');
    splitPayment = null;
    try { hideShortfall(); } catch (e) {}
    hideSupportButton();
    document.getElementById('scanStatus').textContent = '';
    const rep = document.getElementById('scanReport');
    rep.style.display = 'none';
    rep.innerHTML = '';
  }

  saveRefBtn.onclick = async () => {
    const isEditMode = saveRefBtn.dataset.mode === 'edit';

    if (isEditMode) {
      // فتح القفل للتعديل: يمسح أي فحص سابق ويطلب حفظاً جديداً قبل رفع صورة تانية
      refInput.disabled = false;
      refInput.focus();
      savedTxRef = null;
      receiptStep.style.display = 'none';
      resetReceiptSelection();
      saveRefBtn.textContent = 'تحقق';
      saveRefBtn.dataset.mode = 'save';
      refMsg.style.color = 'var(--text-muted)';
      refMsg.textContent = 'عدّل رقم العملية ثم اضغط "تحقق" لتأكيده مجدداً.';
      document.getElementById('formError').textContent = '';
      return;
    }

    const raw  = refInput.value.trim();
    const norm = window.MeemReceiptPipeline
      ? MeemReceiptPipeline.normalizeRef(raw)
      : raw.replace(/[^A-Za-z0-9]/g, '').toUpperCase();

    if (norm.length < 6) {
      refMsg.style.color = 'var(--danger)';
      refMsg.textContent = 'رقم العملية قصير جداً. انسخه كما هو من إشعار التحويل (6 خانات على الأقل).';
      savedTxRef = null;
      receiptStep.style.display = 'none';
      resetReceiptSelection();
      return;
    }

    // ── تحقق مبكر (قراءة فقط، بلا حجز): هل الرقم مستخدم من قبل؟ ──
    // الحجز الحقيقي يبقى ذرّياً لحظة إنشاء الطلب (create_bank_orders_bulk)،
    // فهذا الفحص لتجربة الاستخدام فقط ولا يمكن التلاعب به لتجاوز الحماية.
    saveRefBtn.disabled = true;
    const prevBtnText = saveRefBtn.textContent;
    saveRefBtn.textContent = 'جارِ التحقق...';
    refMsg.style.color = 'var(--text-muted)';
    refMsg.textContent = 'جارِ التحقق من رقم العملية...';
    try {
      const { data: availData, error: availErr } = await withNetTimeout(
        supabaseClient.rpc('check_tx_ref_available', { p_tx_ref: raw }),
        NET_TIMEOUT_MS.rpc, 'check_tx_ref'
      );
      if (availErr) throw availErr;
      if (!availData || !availData.length) throw new Error('check_tx_ref_empty');
      if (availData[0].available === false) {
        saveRefBtn.disabled = false;
        saveRefBtn.textContent = prevBtnText;
        refMsg.style.color = 'var(--danger)';
        refMsg.textContent = availData[0].reason === 'invalid_tx_ref'
          ? 'رقم العملية غير صحيح. انسخه كما هو من إشعار التحويل.'
          : 'رقم العملية هذا مستخدم من قبل في طلب آخر. اكتب رقم العملية الصحيح لتحويلك.';
        savedTxRef = null;
        receiptStep.style.display = 'none';
        resetReceiptSelection();
        return;
      }
    } catch (e) {
      devWarn('[MEEM] check_tx_ref_available failed:', (e && e.message) || e);
      saveRefBtn.disabled = false;
      saveRefBtn.textContent = prevBtnText;
      refMsg.style.color = 'var(--danger)';
      refMsg.textContent = 'تعذّر التحقق من رقم العملية (اتصال ضعيف). حاول مرة أخرى قبل رفع الصورة.';
      savedTxRef = null;
      receiptStep.style.display = 'none';
      resetReceiptSelection();
      return;
    }
    saveRefBtn.disabled = false;
    saveRefBtn.textContent = prevBtnText;

    savedTxRef = raw;
    refInput.disabled = true;
    saveRefBtn.textContent = 'تعديل';
    saveRefBtn.dataset.mode = 'edit';
    refMsg.style.color = 'var(--primary)';
    refMsg.textContent = 'تم التحقق من رقم العملية (غير مستخدم من قبل). ارفع الآن صورة إشعار التحويل لمطابقتها.';
    receiptStep.style.display = 'block';
    document.getElementById('formError').textContent = '';
  };

  // ── الخطوة 2: رفع الصورة + الفحص الذكي ──
  // مسار الفحص الموحد المشترك مع wallet.html.
  async function serverVerify(file, opts, extraFile) {
    if (!window.MeemReceiptPipeline) throw new Error('receipt_pipeline_missing');
    const revision=checkoutScanRevision, context=checkoutReceiptContext();
    if(!(await window.MeemReceiptConsent.require()) || (MeemReceiptConsent.userId() && MeemReceiptConsent.userId()!==currentUser?.id)) throw new Error('receipt_consent_required');
    if(revision!==checkoutScanRevision || context!==checkoutReceiptContext()) throw new Error('receipt_context_changed');
    return window.MeemReceiptPipeline.serverVerify(file, opts, extraFile);
  }

  fileBox.onclick = () => { if (!checkoutScanBusy && savedTxRef) fileInput.click(); };
  fileInput.onchange = async () => {
    if (checkoutScanBusy || !fileInput.files.length) return;
    if (!savedTxRef) {
      document.getElementById('formError').textContent = 'تحقّق من رقم العملية أولاً قبل رفع الصورة.';
      fileInput.value = '';
      return;
    }
    await runScan(fileInput.files[0], null);
  };

  async function runScan(file, secondFile) {
    if (checkoutScanBusy || !file) return;
    invalidateCheckoutReceipt();
    receiptFile = file;
    const revision = checkoutScanRevision;
    const before = JSON.stringify({total:currentTotal(),method:selectedMethodId,ref:savedTxRef});
    const statusEl = document.getElementById('scanStatus');
    const reportEl = document.getElementById('scanReport');

    document.getElementById('formError').textContent = '';

    checkoutScanBusy=true;
    let consentAllowed=false;
    try {consentAllowed=await window.MeemReceiptConsent.require();} finally {checkoutScanBusy=false;}
    if (!consentAllowed) {
      receiptFile = null;
      statusEl.textContent = window.MeemReceiptConsent.message();
      return;
    }
    if(revision!==checkoutScanRevision || before!==JSON.stringify({total:currentTotal(),method:selectedMethodId,ref:savedTxRef}) || (MeemReceiptConsent.userId() && MeemReceiptConsent.userId()!==currentUser?.id)) return;
    const context=checkoutReceiptContext();
    reportEl.style.display = 'none';
    reportEl.innerHTML = '';
    splitPayment = null;
    hideShortfall();
    fileBox.innerHTML = `<svg class="mm-i mm-spin" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-loader"></use></svg> جارِ فحص الصورة...`;
    fileBox.classList.remove('has-file');
    checkoutScanBusy = true;
    const activity = window.MeemReceiptPipeline.beginScanActivity(statusEl, [fileInput, fileBox, placeOrderBtn,
      document.getElementById('retryCheckoutReceiptBtn'), document.getElementById('receiptInput3'),
      document.getElementById('fileUploadBox3'), document.getElementById('remainderRefBtn')]);
    try {

    // A technical failure cannot be presented as an image mismatch.
    const softReview = (flag) => ({
      decision: 'review', ocrStatus: 'needs_review',
      message: 'تعذّر الفحص الآلي؛ لم يُنشأ طلب. أعد المحاولة عند عودة الخدمة.',
      riskFlags: [flag], confidence: null, provider: null, providerName: null, language: null,
      passes: 0, textLength: 0, version: 3,
      extracted: { txRef: null, amount: null, dateTime: null },
      refVerified: false, amountVerified: false
    });

    // حرس زمني على مستوى الواجهة (حزام أمان ثانٍ فوق حرس المحرك نفسه):
    // مهلة تشمل انتظار الدور والفحص، مع نتيجة واضحة عند تعذر الإكمال.
    const UI_SCAN_DEADLINE_MS = 180000;
    let uiWatchdog = null;
    const uiGuard = new Promise(resolve => {
      uiWatchdog = setTimeout(() => resolve(softReview('ui_scan_timeout')), UI_SCAN_DEADLINE_MS);
    });

    let analysis;
    try {
      const scanOpts = {
        onStatus: message => activity.update(message),
        expectedAmount: currentTotal(),
        manualRef: savedTxRef,
        expectedAccount: selectedMethodAccount,
        expectedMethodId: selectedMethodId
      };

      // الفحص الوحيد هو Edge Function الموثّق؛ لا يوجد OCR أو قرار مالي داخل المتصفح.
      const scan = (async () => {
        statusEl.style.color = 'var(--text-muted)';
        activity.update('جارٍ إرسال الصورة للفحص الآمن…');
        try {
          return await serverVerify(file, scanOpts, secondFile);
        } catch (serverErr) {
          console.warn('[MEEM] secure receipt verification failed:', serverErr && serverErr.message);
          const errMsg = String(serverErr && serverErr.message || '');
          // انتهاء الجلسة سبب شائع للفشل الفوري — وجّه المستخدم لتسجيل الدخول بدل رسالة مبهمة
          if (errMsg === 'auth_required' || errMsg === 'supabase_client_missing') {
            const r = softReview('auth_required');
            r.message = 'انتهت جلسة تسجيل الدخول. سجّل الدخول مرة أخرى ثم أعد رفع الإيصال.';
            return r;
          }
          if (['receipt_consent_required','receipt_provider_review_pending'].includes(errMsg)) {
            const result=softReview(errMsg);result.message=serverErr.serverMessage || window.MeemReceiptConsent.message();return result;
          }
          return softReview('server_ocr_failed');
        }
      })();

      analysis = await Promise.race([scan, uiGuard]);
      if (revision !== checkoutScanRevision || context !== checkoutReceiptContext()) return;
      checkoutScanContext = context;
      if (!analysis || typeof analysis !== 'object') analysis = softReview('scan_error');
    } catch (err) {
      // خطأ غير متوقع في محرك الفحص لا يجوز أن يوقف عميلاً حقيقياً
      console.warn('[MEEM] receipt scan error:', err);
      analysis = softReview('scan_error');
    } finally {
      if (uiWatchdog) clearTimeout(uiWatchdog);
    }

    // ضمان إضافي: أي حقل ناقص في النتيجة لا يكسر عرض التقرير
    analysis.extracted = analysis.extracted || { txRef: null, amount: null, dateTime: null };
    analysis.riskFlags = analysis.riskFlags || [];
    if (!analysis.message) analysis.message = 'لم يكتمل الفحص الآلي؛ أعد المحاولة.';

    statusEl.textContent = '';

    // المبلغ المقروء أقل من الإجمالي؛ إثبات الوصول يتم من سجل الحساب.
    if (analysis.decision === 'reject' && analysis.shortfall &&
        analysis.shortfall.remaining > 0 && analysis.shortfall.refMatched) {
      showShortfallCard(file, analysis);
      return;
    }

    if (analysis.decision === 'reject') {
      resetReceiptSelection();
      reportEl.style.display = 'block';
      reportEl.style.borderColor = 'var(--danger)';
      reportEl.innerHTML =
        `<strong style="color: var(--danger);"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-x"></use></svg> تم رفض الصورة</strong><br>` +
        `${escapeHtml(analysis.message)}` +
        `<div style="margin-top: 8px; color: var(--text-muted); font-size: 14px;">` +
        `المبلغ المطلوب تحويله: <strong>${safeFormatSDG(currentTotal())} ج.س</strong> — ` +
        `ارفع لقطة شاشة لإشعار التحويل كما هي من التطبيق (بالعربية أو الإنجليزية، كلاهما مدعوم).` +
        `</div>`;
      scanResult = analysis;
      logFraudAttempt('reject_' + (analysis.riskFlags[0] || 'unknown'), {
        scan_message: analysis.message, risk_flags: analysis.riskFlags
      });
      showSupportButton('تم رفض صورة الإيصال من الفحص الذكي');
      scanResult = null;
      return;
    }

    receiptFile = file;
    scanResult  = analysis;
    fileBox.innerHTML = `<svg class="mm-i" style="color: var(--mm-accent-text);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-check"></use></svg> تم اختيار: ${escapeHtml(file.name)}`;
    fileBox.classList.add('has-file');

    const rows = [];
    if (analysis.providerName)       rows.push(`الجهة: ${analysis.providerName}`);
    if (analysis.language === 'en')  rows.push('لغة الإشعار: إنجليزية');
    if (analysis.language === 'ar')  rows.push('لغة الإشعار: عربية');
    if (analysis.extracted.txRef)    rows.push(`رقم العملية المقروء: ${analysis.extracted.txRef}`);
    if (analysis.extracted.amount)   rows.push(`المبلغ المقروء: ${safeFormatSDG(analysis.extracted.amount)} ج.س`);
    if (analysis.extracted.dateTime) rows.push(`التاريخ والوقت: ${analysis.extracted.dateTime}`);
    rows.push(`المبلغ المطلوب: ${safeFormatSDG(currentTotal())} ج.س`);
    const incomplete = analysis.decision === 'review';
    rows.push(`مطابقة رقم العملية: ${incomplete ? 'لم تكتمل عملية الفحص' : analysis.refVerified ? 'مطابق ✓' : 'غير مطابق ✗'}`);
    rows.push(`مطابقة المبلغ: ${incomplete ? 'لم تكتمل عملية الفحص' : analysis.amountVerified ? 'مطابق ✓' : 'غير مطابق ✗'}`);

    // review_admin = مقبول للعميل، مع تدقيق إداري لاحق (لا يُحجب الطلب)
    const ok = analysis.submissionAllowed === true && analysis.receiptPolicy === 'mandatory-visual-v1' && analysis.automaticCheckComplete === true && analysis.scanId && (analysis.decision === 'accept') &&
               analysis.refVerified === true && analysis.amountVerified === true;
    const needsAdmin = ok && analysis.decision === 'review_admin';
    if (needsAdmin && analysis.reviewReason) rows.push(`سبب التدقيق: ${analysis.reviewReason}`);

    hideSupportButton();

    reportEl.style.display = 'block';
    reportEl.style.borderColor = needsAdmin ? 'var(--mm-warning)' : (ok ? 'var(--primary)' : 'var(--border)');
    reportEl.innerHTML =
      `<strong style="color:${needsAdmin ? 'var(--mm-warning)' : (ok ? 'var(--primary)' : 'var(--ink)')};">` +
      `${window.rzIconMarkup(needsAdmin ? 'shield-user' : (ok ? 'circle-check' : 'info'))} ${escapeHtml(analysis.message)}</strong>` +
      `<div style="margin-top: 8px; color: var(--text-muted);">${rows.map(escapeHtml).join('<br>')}</div>` +
      (ok ? '' : `<div style="margin-top: 8px; color: var(--danger); font-size: 14px; font-weight: 600;">${escapeHtml(blockHint(analysis))}</div>`);

    // لا إرسال دون اجتياز الفحص الآلي بكل شروطه.
    if (!ok) {
      scanResult = null;
      receiptFile = null;

      if (!incomplete && !analysis.refVerified) {
        logFraudAttempt('ref_mismatch_blocked', { risk_flags: analysis.riskFlags, read_ref: analysis.extracted.txRef });
      } else if (!incomplete && !analysis.amountVerified) {
        logFraudAttempt('amount_mismatch_blocked', { risk_flags: analysis.riskFlags, read_amount: analysis.extracted.amount });
      }
    } else {

    }
    } finally {
      activity.finish(); checkoutScanBusy = false;
    }
  }

  // رسالة إرشادية دقيقة حسب سبب المنع
  function blockHint(a) {
    if (a.decision === 'review')
      return 'تعذّر إكمال الفحص بسبب مشكلة تقنية. أعد المحاولة بنفس الإشعار.';
    if (!a.extracted.txRef && !a.extracted.amount)
      return 'لم نتمكن من قراءة رقم العملية ولا المبلغ من الصورة. ارفع لقطة شاشة كاملة للإشعار (أو الإشعار الأبيض من تطبيق بنكك) يظهر فيها رقم العملية والمبلغ معاً.';
    if (!a.refVerified && a.extracted.txRef)
      return `رقم العملية في الصورة (${a.extracted.txRef}) لا يطابق الرقم الذي أدخلته (${savedTxRef}). اضغط "تعديل" وأدخل الرقم الصحيح تماماً كما في الإشعار.`;
    if (!a.refVerified)
      return 'لم يظهر رقم العملية في الصورة. ارفع صورة كاملة للإشعار يظهر فيها رقم العملية بوضوح.';
    if (!a.amountVerified && a.extracted.amount)
      return `المبلغ في الإشعار (${safeFormatSDG(a.extracted.amount)} ج.س) لا يطابق المبلغ المطلوب (${safeFormatSDG(currentTotal())} ج.س). حوّل المبلغ الصحيح ثم ارفع الإشعار الجديد.`;
    if (!a.amountVerified)
      return 'لم يظهر المبلغ في الصورة. ارفع لقطة شاشة كاملة يظهر فيها المبلغ بوضوح.';
    if (!a.refVerified && !a.extracted.txRef)
      return 'لم يظهر رقم العملية في الصورة. ارفع صورة كاملة يظهر فيها رقم العملية كاملاً.';
    return 'الإشعار غير مكتمل: يلزم ظهور رقم العملية والمبلغ معاً. ارفع صورة كاملة أوضح للإشعار، أو تواصل مع الدعم.';
  }

  // ═══════ مسار المبلغ الناقص: بطاقة واضحة + واتساب جاهز + إشعار ثانٍ ═══════
  const shortfallBox   = document.getElementById('shortfallBox');
  const remainderStep  = document.getElementById('remainderStep');
  const remainderInput = document.getElementById('remainderRefInput');
  const remainderBtn   = document.getElementById('remainderRefBtn');
  const remainderMsg   = document.getElementById('remainderRefMsg');
  const fileBox3       = document.getElementById('fileUploadBox3');
  const fileInput3     = document.getElementById('receiptInput3');

  function hideShortfall() {
    shortfallBox.style.display = 'none';
    shortfallBox.innerHTML = '';
    remainderStep.style.display = 'none';
    remainderMsg.textContent = '';
    fileBox3.style.display = 'none';
    fileInput3.value = '';
  }

  function showShortfallCard(file, analysis) {
    invalidateCheckoutReceipt();
    splitPayment = {
      firstFile: file,
      firstScan: analysis,
      remaining: analysis.shortfall.remaining,
      paid: analysis.shortfall.paid,
      secondFile: null, secondScan: null, secondRef: null
    };
    receiptFile = null;
    scanResult  = null;
    fileBox.innerHTML = `<svg class="mm-i" style="color: var(--danger);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-triangle-alert"></use></svg> المبلغ في الإشعار ناقص`;
    fileBox.classList.remove('has-file');
    document.getElementById('scanReport').style.display = 'none';

    const productNames = cart.map(i => i.product_name || i.name || '').filter(Boolean).join(' + ');
    const waMsg =
      `مرحباً، حوّلت مبلغاً ناقصاً في متجر MEEM STORE وأحتاج إكمال الطلب.\n` +
      `رقم العملية: ${savedTxRef}\n` +
      `المبلغ المحوَّل: ${analysis.shortfall.paid} ج.س\n` +
      `المتبقي: ${analysis.shortfall.remaining} ج.س\n` +
      `إجمالي الطلب: ${analysis.shortfall.target} ج.س\n` +
      `المنتج: ${productNames || '—'}\n` +
      `معرّف الحساب: ${currentUser ? currentUser.id : '—'}`;

    shortfallBox.style.display = 'block';
    shortfallBox.innerHTML =
      `<strong style="color: var(--danger);"><svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-alert"></use></svg> المبلغ المحوَّل أقل من المطلوب</strong><br>` +
      `المبلغ الظاهر <strong>${safeFormatSDG(analysis.shortfall.paid)} ج.س</strong>، ` +
      `والمتبقي <strong>${safeFormatSDG(analysis.shortfall.remaining)} ج.س</strong> ` +
      `من إجمالي ${safeFormatSDG(analysis.shortfall.target)} ج.س.` +
      `<div style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 10px;">` +
        (ADMIN_WHATSAPP && ADMIN_WHATSAPP.indexOf('YOUR_') !== 0
          ? `<a href="https://wa.me/${ADMIN_WHATSAPP}?text=${encodeURIComponent(waMsg)}" target="_blank" rel="noopener"
               style="display: inline-flex; align-items: center; gap: 8px; background: #25D366; color: var(--mm-silver); padding: 10px 16px; border-radius: 12px; font-weight: 800; text-decoration: none;">
               <svg class="mm-i" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-whatsapp"></use></svg> تواصل مع الدعم</a>` : '') +
        `<button type="button" id="paidRestBtn"
           style="background: var(--primary); color: var(--mm-on-primary); border: none; padding: 10px 16px; border-radius: 12px; font-weight: 800; cursor: pointer;">
           حوّلت الباقي</button>` +
      `</div>`;

    document.getElementById('paidRestBtn').onclick = () => {
      remainderStep.style.display = 'block';
      remainderMsg.style.color = 'var(--text-muted)';
      remainderMsg.textContent = `أدخل رقم عملية تحويل المبلغ المتبقي (${safeFormatSDG(splitPayment.remaining)} ج.س) ثم ارفع إشعاره.`;
      remainderInput.focus();
    };

    logFraudAttempt('amount_shortfall', {
      risk_flags: analysis.riskFlags,
      paid: analysis.shortfall.paid,
      remaining: analysis.shortfall.remaining
    });
  }

  remainderBtn.onclick = async () => {
    if (checkoutScanBusy || remainderBtn.disabled) return;
    const raw = remainderInput.value.trim();
    const norm = window.MeemReceiptPipeline
      ? MeemReceiptPipeline.normalizeRef(raw)
      : raw.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    fileBox3.style.display = 'none';
    if (!splitPayment) return;
    if (norm.length < 6) {
      remainderMsg.style.color = 'var(--danger)';
      remainderMsg.textContent = 'رقم العملية قصير جداً. انسخه كما هو من الإشعار الثاني.';
      return;
    }
    if (norm === (window.MeemReceiptPipeline ? MeemReceiptPipeline.normalizeRef(savedTxRef) : savedTxRef)) {
      remainderMsg.style.color = 'var(--danger)';
      remainderMsg.textContent = 'رقم العملية الثاني لا يصح أن يطابق الأول.';
      return;
    }
    scanResult = null; checkoutScanContext = null; splitPayment.secondScan = null; splitPayment.secondFile = null;
    remainderBtn.disabled = true;
    remainderMsg.style.color = 'var(--text-muted)';
    remainderMsg.textContent = 'جارِ التحقق...';
    try {
      const { data, error } = await withNetTimeout(
        supabaseClient.rpc('check_tx_ref_available', { p_tx_ref: raw }),
        NET_TIMEOUT_MS.rpc, 'check_tx_ref_2'
      );
      if (error) throw error;
      if (!data || !data.length || data[0].available === false) {
        remainderMsg.style.color = 'var(--danger)';
        remainderMsg.textContent = 'رقم العملية الثاني مستخدم من قبل أو غير صحيح.';
        return;
      }
      splitPayment.secondRef = raw;
      remainderMsg.style.color = 'var(--primary)';
      remainderMsg.textContent = 'تم التحقق ✓ — ارفع الآن صورة إشعار المبلغ المتبقي.';
      fileBox3.style.display = 'block';
    } catch (e) {
      remainderMsg.style.color = 'var(--danger)';
      remainderMsg.textContent = 'تعذّر التحقق (اتصال ضعيف). حاول مجدداً.';
    } finally {
      remainderBtn.disabled = false;
    }
  };

  fileBox3.onclick = () => { if (!checkoutScanBusy && splitPayment && splitPayment.secondRef) fileInput3.click(); };
  fileInput3.onchange = async () => {
    if (checkoutScanBusy || !fileInput3.files.length || !splitPayment || !splitPayment.secondRef) return;
    const f = fileInput3.files[0];
    scanResult = null; checkoutScanContext = null; splitPayment.secondScan = null;
    const splitAtStart = splitPayment, revisionAtStart = ++checkoutScanRevision, contextAtStart = checkoutReceiptContext(), refAtStart = splitPayment.secondRef;
    const statusEl = document.getElementById('remainderStatus');
    statusEl.style.color = 'var(--text-muted)';
    checkoutScanBusy = true;
    const activity = window.MeemReceiptPipeline.beginScanActivity(statusEl, [fileInput, fileInput3, fileBox, fileBox3,
      remainderBtn, placeOrderBtn, document.getElementById('retryCheckoutReceiptBtn')]);
    try {
    let res = null;
    const opts = {
      onStatus: message => activity.update(message),
      expectedAmount: splitPayment.remaining,
      manualRef: splitPayment.secondRef,
      expectedAccount: selectedMethodAccount,
      expectedMethodId: selectedMethodId
    };
    try {
      res = await serverVerify(f, opts, null);
    } catch (e) {
      res = null;
    }
    if (splitPayment !== splitAtStart || checkoutScanRevision !== revisionAtStart || contextAtStart !== checkoutReceiptContext() || splitPayment.secondRef !== refAtStart) return;
    if (!res || res.submissionAllowed !== true || res.automaticCheckComplete !== true || res.refVerified !== true || res.amountVerified !== true) {
      statusEl.style.color = 'var(--danger)';
      statusEl.textContent = (res && res.message)
        ? res.message
        : `لم نتمكن من تأكيد إشعار المبلغ المتبقي (${safeFormatSDG(splitPayment.remaining)} ج.س). ارفع لقطة شاشة كاملة للإشعار.`;
      return;
    }

    const activeSplit = splitPayment;
    const revision = checkoutScanRevision, context = checkoutReceiptContext();
    activity.update('جارٍ إكمال التحقق من الإشعارين…');
    let first;
    try {
      first = await serverVerify(activeSplit.firstFile, {onStatus:message=>activity.update(message),expectedAmount:activeSplit.paid,manualRef:savedTxRef,expectedMethodId:selectedMethodId}, null);
    } catch (_) { first = null; }
    if (revision !== checkoutScanRevision || context !== checkoutReceiptContext() || splitPayment !== activeSplit) return;
    if (!first?.submissionAllowed || !first.automaticCheckComplete || !first.scanId) {
      statusEl.style.color = 'var(--danger)';
      statusEl.textContent = 'لم يكتمل فحص الدفعة الأولى؛ أعد رفع الإشعارين. لم يُنشأ طلب.';
      return;
    }
    activeSplit.firstScan = first;
    activeSplit.secondFile = f; activeSplit.secondScan = res;
    receiptFile = activeSplit.firstFile;
    scanResult = first;
    checkoutScanContext = context;

    statusEl.style.color = 'var(--primary)';
    statusEl.textContent = 'تم تأكيد الإشعار الثاني ✓ — اضغط "تأكيد الدفع وإرسال الطلبات".';
    shortfallBox.style.borderColor = 'var(--primary)';
    fileBox.innerHTML = `<svg class="mm-i" style="color: var(--mm-accent-text);" aria-hidden="true"><use href="assets/icons/lucide-sprite.svg#i-circle-check"></use></svg> تم قبول الإشعارين (دفع مجزّأ)`;
    fileBox.classList.add('has-file');
    } finally {
      activity.finish(); checkoutScanBusy = false;
    }
  };

  placeOrderBtn.onclick = () => handlePlaceOrder(errorBox, placeOrderBtn);
  document.getElementById('applyCouponBtn').onclick = applyCoupon;
}

function clearActiveBasket() {
  if (isDirectBuy) {
    sessionStorage.removeItem('meem_direct_buy');
  } else {
    localStorage.removeItem('meem_store_cart');
  }
}

window.removeItemFromCheckout = function(cartItemId) {
  invalidateCheckoutReceipt();
  appliedCoupon = null;
  cart = cart.filter(item => (item.cart_item_id || item.product_id) !== cartItemId);
  if (isDirectBuy) {
    sessionStorage.setItem('meem_direct_buy', JSON.stringify({ created_at: Date.now(), items: cart }));
  } else {
    localStorage.setItem('meem_store_cart', JSON.stringify(cart));
  }
  if (cart.length === 0) {
    window.location.reload();
  } else {
    renderCheckout();
  }
};

async function handlePlaceOrder(errorBox, placeOrderBtn) {
  errorBox.textContent = '';
  if (placeOrderBtn.disabled) return;
  if (MeemStoreRules.cartError(cart)) { errorBox.textContent = MeemStoreRules.cartError(cart); return; }
  if (!selectedPayment) { errorBox.textContent = 'من فضلك اختر طريقة الدفع أولاً!'; return; }

  // ── تحقق اكتمال بيانات وسيلة الدفع المختارة أولاً (قبل حساب أي محاولة) ──
  // بهذا الترتيب: ضغطات الزر أثناء استكمال الخطوات (رمز غير مؤكَّد، إيصال
  // لسه ما اتفحص...) لا تُحتسب من حصة محاولات الإرسال، فمستخدم أكمل كل
  // شيء بشكل صحيح ما بيتفاجأ بحظر بسبب محاولات فاشلة ما كان يدري بيها.
  if (selectedPayment === 'code' && !verifiedPaymentCode) {
    errorBox.textContent = 'اكتب رمز الدفع واضغط "تحقق" أولاً.';
    return;
  }
  if (selectedPayment !== 'wallet' && selectedPayment !== 'code' &&
      (!selectedMethodId || !receiptFile || !savedTxRef || !scanResult)) {
    if (!selectedMethodId) errorBox.textContent = 'الرجاء اختيار وسيلة التحويل البنكي!';
    else if (!savedTxRef) errorBox.textContent = 'اكتب رقم العملية واضغط "تحقق" أولاً (الخطوة 1).';
    else errorBox.textContent = 'الرجاء رفع صورة الإيصال ليتم فحصها (الخطوة 2).';
    return;
  }

  // ── Rate Limiting: منع إرسال طلبات متكررة بشكل مفرط ──
  // يُحتسب فقط عند محاولة إرسال فعلية مكتملة البيانات (بعد التحقق أعلاه)،
  // وليس عند كل ضغطة فاشلة أثناء تعبئة الخطوات.
  const rlKey = `checkout_${currentUser?.id || 'guest'}`;
  if (!rateLimiter.check(rlKey, 3, 60000)) {
    errorBox.textContent = 'محاولات كثيرة جداً، انتظر دقيقة ثم حاول مجدداً.';
    return;
  }

  placeOrderBtn.disabled = true;
  placeOrderBtn.textContent = 'جارِ إرسال طلباتك...';

  if (selectedPayment === 'wallet') {
    try {
      // السلة كاملة في معاملة واحدة: خصم واحد، كوبون يُستهلك مرة واحدة،
      // ولا تبقى طلبات نصف منفّذة لو فشلت أي قطعة.
      const items = cart.map(item => ({
        product_id:   item.product_id,
        option_id:    item.selected_option ? item.selected_option.id : null,
        quantity:     (item.quantity && item.quantity > 0) ? item.quantity : 1,
        field_values: item.field_values || {},
        field_labels: item.field_labels || {}
      }));

      const { data: rpcData, error } = await supabaseClient.rpc('create_wallet_orders_bulk', {
        p_items: items,
        p_coupon_code: appliedCoupon
          ? appliedCoupon.code
          : null
      });
      if (error) throw error;

      const lastOrderId = (rpcData && rpcData.length) ? rpcData[rpcData.length - 1].id : null;
      clearActiveBasket();
      window.location.href = lastOrderId
        ? `receipt.html?order_id=${lastOrderId}`
        : 'my-orders.html';
    } catch (err) {
      const msg = err.message || err.hint || err.details || String(err);
      devWarn('[MEEM] wallet order error:', msg);
      errorBox.textContent = getFriendlyError(msg);
      placeOrderBtn.disabled = false;
      placeOrderBtn.textContent = 'تأكيد الدفع وإرسال الطلبات';
    }
    return;
  }

  // ── الدفع برمز من الإدارة: دالة ذرّية تستهلك الرمز وتنشئ الطلب معاً ──
  // (تم التحقق من verifiedPaymentCode في بداية الدالة قبل احتساب محاولة الإرسال)
  if (selectedPayment === 'code') {
    try {
      const items = cart.map(item => ({
        product_id:   item.product_id,
        option_id:    item.selected_option ? item.selected_option.id : null,
        quantity:     (item.quantity && item.quantity > 0) ? item.quantity : 1,
        field_values: item.field_values || {},
        field_labels: item.field_labels || {}
      }));
      const { data, error } = await withNetTimeout(
        supabaseClient.rpc('redeem_payment_code_order', {
          p_code:        verifiedPaymentCode,
          p_items:       items,
          p_coupon_code: appliedCoupon
            ? appliedCoupon.code
            : null
        }),
        NET_TIMEOUT_MS.rpc, 'redeem_payment_code'
      );
      if (error) throw error;
      const lastId = (data && data.length) ? data[data.length - 1].id : null;
      clearActiveBasket();
      window.location.href = lastId ? `receipt.html?order_id=${lastId}` : 'my-orders.html';
    } catch (err) {
      const msg = (err && (err.message || err.hint || err.details)) || String(err);
      devWarn('[MEEM] payment code order error:', msg);
      errorBox.textContent =
        /already_used/.test(msg)   ? 'هذا الرمز مستخدم من قبل.' :
        /expired/.test(msg)        ? 'انتهت صلاحية الرمز. اطلب رمزاً جديداً من الإدارة.' :
        /amount_too_low/.test(msg) ? 'قيمة الرمز أقل من إجمالي الطلب.' :
        /not_found|invalid_code/.test(msg) ? 'الرمز غير صحيح.' :
        /not_your_code/.test(msg)  ? 'هذا الرمز مخصص لعميل آخر.' :
        getFriendlyError(msg);
      verifiedPaymentCode = null;
      placeOrderBtn.disabled = false;
      placeOrderBtn.textContent = 'تأكيد الدفع وإرسال الطلبات';
    }
    return;
  }

  // (تم التحقق من selectedMethodId / receiptFile / savedTxRef / scanResult
  // في بداية الدالة قبل احتساب محاولة الإرسال — لا داعي لتكرار الفحص هنا)

  placeOrderBtn.textContent = 'جارِ التحقق من نتيجة الفحص الخادمي...';
  const receiptHash = scanResult && scanResult.receiptHash;
  const receiptScanId = scanResult && scanResult.scanId;
  if (!receiptHash || !scanResult.receiptPath || !scanResult.attachmentId || checkoutScanContext !== checkoutReceiptContext() || !receiptScanId || scanResult.submissionAllowed !== true || scanResult.receiptPolicy !== 'mandatory-visual-v1') {
    errorBox.textContent = 'لم تكتمل نتيجة الفحص الآمن. أعد رفع الإيصال وانتظر النتيجة قبل الإرسال.';
    placeOrderBtn.disabled = false;
    placeOrderBtn.textContent = 'تأكيد الدفع وإرسال الطلبات';
    return;
  }

  // ══════════════════════════════════════════════════════════════════
  // مسار التحويل البنكي — كل خطوة لها مهلة صريحة، ولا حجز بلا طلب فعلي
  // ══════════════════════════════════════════════════════════════════

  // إنهاء موحّد للفشل: يُرجع الزر لحالته دائماً (لا تعليق أبداً)
  const failOrder = (message, opts) => {
    const o = opts || {};
    errorBox.style.color = 'var(--danger)';
    errorBox.textContent = message;
    if (o.support && window.__meemShowSupport) {
      try { window.__meemShowSupport(o.support); } catch (e) {}
    }
    if (o.fraud && window.__meemLogFraud) {
      try { window.__meemLogFraud(o.fraud, o.fraudExtra || {}); } catch (e) {}
    }
    placeOrderBtn.disabled = false;
    placeOrderBtn.textContent = 'تأكيد الدفع وإرسال الطلبات';
  };

  // ترجمة أخطاء القاعدة إلى رسائل واضحة للعميل
  const failFromError = (err) => {
    const msg = (err && (err.message || err.hint || err.details)) || String(err);
    devWarn('[MEEM] bank order error:', msg);

    if (err && err.isTimeout) {
      failOrder('تعذّر إكمال الطلب — الاتصال بطيء أو متوقف. لم يُسجّل أي طلب ورقم عمليتك ما زال متاحاً؛ تحقق من الشبكة ثم أعد المحاولة.',
        { support: 'انقطاع اتصال أثناء تسجيل الطلب' });
      return;
    }
    if (msg.includes('duplicate_transaction_ref')) {
      failOrder('رقم العملية هذا تم استخدامه من قبل في طلب آخر!',
        { support: 'رقم العملية مستخدم من قبل', fraud: 'duplicate_transaction_ref' });
      return;
    }
    if (msg.includes('duplicate_receipt_image')) {
      failOrder('صورة هذا الإيصال تم استخدامها من قبل في طلب آخر!',
        { support: 'صورة الإيصال مستخدمة من قبل', fraud: 'duplicate_receipt_image' });
      return;
    }
    if (msg.includes('receipt_rejected')) {
      failOrder('تم رفض هذا الإيصال من الفحص الذكي. راجع صورة الإشعار وأعد المحاولة.',
        { support: 'تم رفض الإيصال من الفحص الذكي', fraud: 'receipt_rejected',
          fraudExtra: { scan_message: scanResult && scanResult.message } });
      return;
    }
    if (msg.includes('coupon_already_used') || msg.includes('coupon_invalid') || msg.includes('coupon_min_order')) {
      failOrder('انتهت صلاحية كود الخصم أو نفدت كميته أو استخدمته من قبل. أزل الكود وأعد المحاولة.');
      return;
    }
    if (msg.includes('receipt_claim_failed')) {
      failOrder('تعذّر حجز إيصالك في قاعدة البيانات. لم يُسجّل أي طلب — أعد المحاولة، وإن تكرر تواصل مع الدعم.',
        { support: 'فشل حجز الإيصال', fraud: 'receipt_claim_failed' });
      return;
    }
    if (msg.includes('auth_required')) {
      failOrder('انتهت جلسة دخولك. سجّل الدخول مجدداً ثم أعد المحاولة (رقم عمليتك ما زال متاحاً).');
      return;
    }
    // 🔴 السبب الجذري الذي كان يُفشل كل طلب بنكي: تعارض متغيّرات في دالة
    // القاعدة (column reference "id" is ambiguous) أو دالة غير منشورة.
    if (errIsAmbiguous(err) || errIsMissingFunction(err)) {
      failOrder('دالة إنشاء الطلبات على قاعدة البيانات تحتاج تحديثاً. ' + DB_UPDATE_HINT,
        { support: 'دوال قاعدة البيانات تحتاج تحديثاً', fraud: 'technical_failure',
          fraudExtra: { raw_error: msg } });
      return;
    }
    failOrder(`${getFriendlyError(msg)} [${errTechCode(err)}]`,
      { support: 'خطأ تقني أثناء تسجيل الطلب', fraud: 'technical_failure', fraudExtra: { raw_error: msg } });
  };

  // The Edge Function saved exactly the bytes it checked. No client re-upload.
  const filePath = scanResult.receiptPath;
  const receiptUrl = 'receipts/' + filePath;

  // ── (3) الطلب كامل في معاملة واحدة ذرّية ──
  // حجز رقم العملية + استهلاك الكوبون + إدخال صفوف الطلب تحدث كلها معاً
  // داخل القاعدة: إما تنجح جميعها أو ترجع جميعها (ROLLBACK). لذلك لم يعد
  // ممكناً أن يُقفل رقم العملية بينما لا يوجد طلب مكتمل.
  placeOrderBtn.textContent = 'جارِ تسجيل طلبك...';

  const bankItems = cart.map(item => ({
    product_id:   item.product_id,
    option_id:    item.selected_option ? item.selected_option.id : null,
    quantity:     (item.quantity && item.quantity > 0) ? item.quantity : 1,
    field_values: item.field_values || {},
    field_labels: item.field_labels || {}
  }));

  const couponCode = appliedCoupon
    ? appliedCoupon.code
    : null;

  const receiptPayload = {
    tx_ref:            savedTxRef,
    receipt_hash:      receiptHash,
    receipt_path:      filePath,
    receipt_url:       receiptUrl,
    provider:          scanResult.provider || null,
    payment_method_id: selectedMethodId,
    amount_detected:   scanResult.extracted ? scanResult.extracted.amount : null,
    tx_ref_ocr:        scanResult.extracted ? scanResult.extracted.txRef : null,
    ocr_status:        scanResult.ocrStatus || 'needs_review',
    ocr_confidence:    scanResult.confidence ?? null,
    risk_flags:        scanResult.riskFlags || [],
    review_reason:     scanResult.reviewReason || null,
    review_severity:   scanResult.reviewSeverity || null,
    ocr_data: Object.assign({}, scanResult.extracted || {}, {
      review_reason:   scanResult.reviewReason || null,
      split_payment:   splitPayment && splitPayment.secondScan ? {
        first_amount:  splitPayment.paid,
        second_amount: splitPayment.remaining,
        second_tx_ref: splitPayment.secondRef
      } : null,
      engine_version:  scanResult.version || null,
      engine_source:   scanResult.source || 'supabase_edge',
      language:        scanResult.language || null,
      provider_name:   scanResult.providerName || null,
      passes:          scanResult.passes || 0,
      text_length:     scanResult.textLength || 0,
      ref_verified:    !!scanResult.refVerified,
      amount_verified: !!scanResult.amountVerified,
      decision:        scanResult.decision || null,
      scan_message:    scanResult.message || null,
      edge_scan_id:    scanResult.scanId || null,
      edge_receipt_hash: scanResult.receiptHash || null
    })
  };

  if (splitPayment) {
    const second = splitPayment.secondScan;
    if (!second?.submissionAllowed || !second.scanId || second.receiptPolicy !== 'mandatory-visual-v1') { failOrder('أكمل فحص الإشعار الثاني أولاً.'); return; }
    receiptPayload.secondary_receipt = {
      tx_ref: splitPayment.secondRef, receipt_hash: second.receiptHash, receipt_path: second.receiptPath,
      payment_method_id: selectedMethodId, ocr_data: {edge_scan_id:second.scanId}
    };
  }
  const finishSuccess = async (rows) => {
    const list = Array.isArray(rows) ? rows : [];
    const lastId = list.length ? list[list.length - 1].id : null;
    clearActiveBasket();
    window.location.href = lastId
      ? `receipt.html?order_id=${lastId}`
      : 'my-orders.html';
  };

  try {
    const { data, error } = await withNetTimeout(
      supabaseClient.rpc('create_bank_orders_bulk', {
        p_items:       bankItems,
        p_receipt:     receiptPayload,
        p_coupon_code: couponCode
      }),
      NET_TIMEOUT_MS.rpc, 'create_bank_orders'
    );
    if (error) throw error;
    await finishSuccess(data);
    return;
  } catch (err) {
    const msg = (err && (err.message || err.hint || err.details)) || String(err);
    // نلجأ للمسار الاحتياطي في حالتين فقط، وكلتاهما عطل في القاعدة لا في الطلب:
    //   1) الدالة الذرّية غير منشورة (PGRST202 / schema cache)
    //   2) الدالة منشورة لكنها معطوبة بتعارض متغيّرات (42702 ambiguous)
    //      ← هذا هو ما كان يُفشل كل طلب بنكي. المعاملة تُرجَع بالكامل عند
    //      هذا الخطأ فلا يُحجز أي إيصال، لذا إعادة المحاولة آمنة تماماً.
    devWarn('[MEEM] create_bank_orders_bulk failed:', msg);
    failFromError(err);
    return;
  }

  // ── (4) [2026-10-08 hardening] أُزيل المسار الاحتياطي القديم نهائياً ──
  // السبب: كان يُدرج الطلبات بإدراج مباشر في جدول orders من المتصفح، وقد أُلغي
  // ذلك على مستوى القاعدة: سُحبت صلاحيات INSERT/UPDATE عن authenticated، وربط
  // التريجر أي طلب بنكي بإيصال موثّق خادمياً. المسار الآمن الوحيد الآن هو الدالة
  // الذرّية create_bank_orders_bulk (تحجز الإيصال + تُنشئ الطلبات في معاملة واحدة).
  // عند تعذّرها لا نُنشئ أي طلب صامت، بل نُبلّغ الزبون بوضوح.
  failFromError(new Error('bank_checkout_unavailable: تعذّر تثبيت الطلب البنكي (لم يُسجَّل أي طلب ولم يُحجز الإيصال). الرجاء إعادة المحاولة أو التواصل مع الدعم.'));
}

init();
