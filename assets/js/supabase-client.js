// =========================================================
// RAIZEY STORE — Supabase Client
// =========================================================

// =========================================================
// Rate Limiter — منع الإرسال المتكرر
// =========================================================
const rateLimiter = (() => {
  const store = {};
  return {
    check(key, maxAttempts, windowMs) {
      const now = Date.now();
      if (!store[key]) store[key] = [];
      store[key] = store[key].filter(t => now - t < windowMs);
      if (store[key].length >= maxAttempts) return false;
      store[key].push(now);
      return true;
    },
    reset(key) {
      delete store[key];
    }
  };
})();

// =========================================================
// Dev Logging Helpers — آمن في الإنتاج
// =========================================================
// ملاحظة: نطاقات المعاينة (vercel.app) تُعتبر إنتاجاً — لا تُطبع فيها أي لوقات.
const _isDev = (
  window.location.hostname === 'localhost' ||
  window.location.hostname === '127.0.0.1' ||
  window.location.hostname.endsWith('.local') ||
  window.location.hostname.includes('.repl.co') ||
  window.location.hostname.includes('.replit.dev')
);

function devLog(...args) {
  if (_isDev) console.log(...args);
}

function devWarn(...args) {
  if (_isDev) console.warn(...args);
}

// =========================================================
// رسائل خطأ مناسبة للمستخدم
// =========================================================
function getFriendlyError(errMsg) {
  if (!errMsg) return 'حصل خطأ غير متوقع. يرجى المحاولة مجدداً.';
  const msg = String(errMsg).toLowerCase();
  if (msg.includes('insufficient_balance'))
    return 'رصيدك في المحفظة غير كافٍ لإتمام الطلب.';
  if (msg.includes('wallet_missing') || msg.includes('wallet_not_found'))
    return 'لا توجد محفظة مرتبطة بحسابك، يرجى التواصل مع الدعم.';
  if (msg.includes('product_not_found') || msg.includes('option_not_found') || msg.includes('option_required'))
    return 'أحد المنتجات في سلتك لم يعد متاحاً أو يحتاج اختيار الخيار المطلوب.';
  if (msg.includes('price_calculation') || msg.includes('price_tampered'))
    return 'خطأ في حساب السعر، يرجى تحديث الصفحة والمحاولة مجدداً.';
  if (msg.includes('maintenance_mode'))
    return 'المتجر متوقف مؤقتاً للصيانة، حاول لاحقاً.';
  if (msg.includes('access_denied'))
    return 'حسابك موقوف عن إتمام عمليات الشراء. تواصل مع الدعم.';
  if (msg.includes('receipt_required') || msg.includes('receipt_not_owned'))
    return 'لم يتم العثور على إيصال صالح لهذا الطلب، ابدأ من رفع الإيصال مجدداً.';
  if (msg.includes('receipt_rejected') || msg.includes('invalid_receipt_input'))
    return 'تعذّر قبول بيانات الإيصال، تأكد من رقم العملية والصورة وأعد المحاولة.';
  if (msg.includes('coupon_already_used'))
    return 'لقد استخدمت هذا الكود من قبل.';
  if (msg.includes('coupon_min_order'))
    return 'إجمالي طلبك أقل من الحد الأدنى المطلوب لهذا الكود.';
  if (msg.includes('coupon') || msg.includes('discount'))
    return 'كود الخصم غير صالح أو منتهي الصلاحية أو نفدت كميته.';
  if (msg.includes('duplicate_transaction_ref'))
    return 'رقم العملية هذا تم استخدامه من قبل في طلب آخر.';
  if (msg.includes('duplicate_receipt_image'))
    return 'صورة هذا الإيصال تم استخدامها من قبل في طلب آخر.';
  if (msg.includes('duplicate') || msg.includes('unique') || msg.includes('violates'))
    return 'تم استخدام هذا الإيصال أو رقم العملية من قبل في طلب آخر.';
  if (msg.includes('network') || msg.includes('fetch') || msg.includes('failed to fetch'))
    return 'فشل الاتصال بالخادم. تحقق من الإنترنت وأعد المحاولة.';
  if (msg.includes('permission') || msg.includes('unauthorized') || msg.includes('403'))
    return 'غير مصرح بهذا الإجراء. يرجى تسجيل الدخول مجدداً.';
  if (msg.includes('timeout') || msg.includes('timed out'))
    return 'انتهت مهلة الاتصال. يرجى المحاولة مجدداً.';
  return 'حصل خطأ أثناء إتمام الطلب. يرجى المحاولة مجدداً أو التواصل مع الدعم.';
}
const runtimeSupabaseConfig = window.__SUPABASE_CONFIG__ || {};
const SUPABASE_URL = runtimeSupabaseConfig.url || "https://rglbfizqolrenwfsndyv.supabase.co";
const SUPABASE_ANON_KEY = runtimeSupabaseConfig.anonKey || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJnbGJmaXpxb2xyZW53ZnNuZHl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNDY4NzMsImV4cCI6MjA5ODcyMjg3M30.bJywsPvgXPdsNOZlVTIwYHz3Z2zcobwinGuUXAb5ev4";
// القراءة العامة المطلوبة للوصول إلى Edge Function؛ لا تُعرّف هنا أي خدمة سرية.
window.SUPABASE_URL = SUPABASE_URL;
window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;

// حماية: لو لم تُحمَّل مكتبة Supabase من الـ CDN لا نرمي TypeError يوقف الصفحة كلها
let supabaseClient = null;
if (window.supabase && typeof window.supabase.createClient === 'function') {
  supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: 'pkce',
      storageKey: 'raizey-auth'
    },
    global: {
      headers: { 'x-client-info': 'raizey-store' }
    }
  });
  window.supabaseClient = supabaseClient;
} else {
  devWarn('[RAIZEY] Supabase SDK not loaded');
  document.addEventListener('DOMContentLoaded', () => {
    if (document.querySelector('.raizey-offline-banner')) return;
    const banner = document.createElement('div');
    banner.className = 'raizey-offline-banner';
    banner.setAttribute('role', 'alert');
    banner.textContent = 'تعذّر الاتصال بالخادم. تحقّق من الإنترنت ثم أعد تحميل الصفحة.';
    document.body.prepend(banner);
  });
}

// حماية موحّدة: كل دالة تستدعي القاعدة تتأكد أن العميل جاهز
function requireClient() {
  if (!supabaseClient) throw new Error('failed to fetch — supabase client unavailable');
  return supabaseClient;
}

// =========================================================
// Sentry: سياق الصفحة والمستخدم (بدون بيانات حساسة زي الإيميل)
// =========================================================
if (window.Sentry && typeof window.Sentry.onLoad === 'function') {
  window.Sentry.onLoad(function () {
    try {
      window.Sentry.setTag('page', (location.pathname.split('/').pop() || 'index.html'));
    } catch (_) {}
  });
}
if (supabaseClient) {
  supabaseClient.auth.getSession().then(({ data }) => {
    const uid = data && data.session && data.session.user ? data.session.user.id : null;
    if (window.Sentry && uid) window.Sentry.setUser({ id: uid });
  }).catch(() => {});
  supabaseClient.auth.onAuthStateChange((_event, session) => {
    if (!window.Sentry) return;
    if (session && session.user) {
      window.Sentry.setUser({ id: session.user.id });
    } else {
      window.Sentry.setUser(null);
    }
  });
}

// =========================================================
// Cache بسيط في sessionStorage لتفادي الاستعلامات المتكررة
// =========================================================
async function getCachedData(key, fetchFn, ttlSeconds = 300) {
  const cacheKey = `raizey_cache_${key}`;
  try {
    const cached = sessionStorage.getItem(cacheKey);
    if (cached) {
      const { data, expires } = JSON.parse(cached);
      if (Date.now() < expires) return data;
      sessionStorage.removeItem(cacheKey);
    }
  } catch (e) {
    devWarn('[RAIZEY] cache read error');
  }

  const data = await fetchFn();

  try {
    sessionStorage.setItem(cacheKey, JSON.stringify({
      data,
      expires: Date.now() + ttlSeconds * 1000
    }));
  } catch (e) {
    devWarn('[RAIZEY] cache write error');
  }

  return data;
}

// دالة مساعدة: جلب سعر الصرف مع هامش الربح مطبق تلقائياً
async function getExchangeRate() {
  try {
    const { data, error } = await requireClient()
      .from('settings')
      .select('key, value')
      .in('key', ['usd_to_sdg_rate', 'profit_margin_percent']);

    if (error || !data) return 0;

    const map = {};
    data.forEach(row => { map[row.key] = parseFloat(row.value) || 0; });

    const rate   = map.usd_to_sdg_rate      || 0;
    const margin = map.profit_margin_percent || 0;

    return rate * (1 + margin / 100);
  } catch (e) {
    devWarn('[RAIZEY] getExchangeRate error:', e);
    return 0;
  }
}

// دالة مساعدة: تنسيق السعر بالجنيه (أرقام إنجليزية لتطابق خط الأسعار الرقمي)
function formatSDG(amount) {
  return new Intl.NumberFormat('en-US').format(Math.round(amount));
}

// فحص إذا كانت بصمة الإيصال أو رقم العملية مستخدمة من قبل في نفس الجدول (orders أو wallet_topups)
async function checkDuplicateReceipt(table, hashOrRef) {
  if (!hashOrRef) return false;
  const ALLOWED_DUPLICATE_TABLES = new Set(['orders', 'wallet_topups']);
  if (!ALLOWED_DUPLICATE_TABLES.has(table)) return false;
  const cleanVal = String(hashOrRef).trim();

  try {
    // 1. فحص بعمود receipt_hash
    const { data: dataHash } = await requireClient()
      .from(table)
      .select('id')
      .eq('receipt_hash', cleanVal)
      .limit(1)
      .maybeSingle();

    if (dataHash) return true;
  } catch (e) {
    devWarn('[RAIZEY] checkDuplicateReceipt (hash) error:', e);
  }

  // 2. فحص بعمود transaction_reference احتياطياً إن وجد
  try {
    const { data: dataRef } = await requireClient()
      .from(table)
      .select('id')
      .eq('transaction_reference', cleanVal)
      .limit(1)
      .maybeSingle();

    if (dataRef) return true;
  } catch (e) {
    // تتجاهل الخطأ في حال عدم وجود العمود
  }

  return false;
}

// فحص منفصل لتكرار رقم العملية (transaction_reference) فقط
async function checkDuplicateTransactionRef(table, transactionRef) {
  if (!transactionRef) return false;
  const ALLOWED_DUPLICATE_TABLES = new Set(['orders', 'wallet_topups']);
  if (!ALLOWED_DUPLICATE_TABLES.has(table)) return false;
  const cleanRef = String(transactionRef).replace(/[\r\n\s\-_]+/g, '');
  if (!cleanRef) return false;

  try {
    const { data } = await requireClient()
      .from(table)
      .select('id')
      .eq('transaction_reference', cleanRef)
      .limit(1)
      .maybeSingle();
    return !!data;
  } catch (e) {
    return false;
  }
}

// =========================================================
// تنظيف HTML لمنع هجمات XSS
// =========================================================
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g,  '&amp;')
    .replace(/</g,  '&lt;')
    .replace(/>/g,  '&gt;')
    .replace(/"/g,  '&quot;')
    .replace(/'/g,  '&#x27;');
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/`/g, '&#x60;');
}

function safeDataAttr(value) {
  return escapeAttribute(value).replace(/\n/g, ' ').replace(/\r/g, ' ');
}

function sanitizeUrl(value) {
  if (!value) return '';
  try {
    const url = new URL(String(value), window.location.origin);
    if (!['http:', 'https:'].includes(url.protocol)) return '';
    return url.href;
  } catch (error) {
    return '';
  }
}

function safeText(value, fallback = '') {
  if (value === null || value === undefined || value === '') return fallback;
  return escapeHtml(value);
}

// =========================================================
// التحقق من صلاحية صورة الإيصال (نوع + حجم + صحة الملف)
// =========================================================
async function validateReceiptImage(file) {
  if (!file) {
    return { valid: false, message: 'لم يتم اختيار أي ملف.' };
  }

  // 1. فحص نوع MIME + الامتداد
  // ملاحظة: بعض هواتف أندرويد/آيفون ترسل الصورة بامتداد .jpg ونوع فارغ أو
  // image/heic. لذلك نقبل امتداداً معروفاً مع نوع فارغ، ونقبل HEIC/HEIF
  // (الخادم يقرأها بلا مشكلة) — بدل رفض العميل كلياً.
  const allowedMime = [
    'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
    'image/heic', 'image/heif', 'image/heic-sequence'
  ];
  const allowedExts = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];
  const fileExt     = (file.name.split('.').pop() || '').toLowerCase();
  const mime        = String(file.type || '').toLowerCase().split(';')[0].trim();

  const mimeOk = mime ? allowedMime.includes(mime) : false;
  const extOk  = allowedExts.includes(fileExt);

  // نرفض فقط إذا فشل الاثنان (لا نوع معروف ولا امتداد معروف)
  if (!mimeOk && !extOk) {
    return { valid: false, message: 'نوع الملف غير مدعوم. استخدم JPG أو PNG أو WEBP فقط.' };
  }
  // نوع صريح غير صورة (PDF مثلاً) يُرفض حتى لو الامتداد مضلِّل
  if (mime && !mime.startsWith('image/')) {
    return { valid: false, message: 'نوع الملف غير مدعوم. استخدم JPG أو PNG أو WEBP فقط.' };
  }

  // 2. فحص الحجم (أقل من 5 ميجابايت)
  if (file.size > 5 * 1024 * 1024) {
    return { valid: false, message: 'حجم الصورة كبير جداً. الحد الأقصى المسموح 5 ميجابايت.' };
  }

  // 3. الحجم الأدنى (أكبر من 10 كيلوبايت — لمنع الصور الفارغة)
  if (file.size < 10 * 1024) {
    return { valid: false, message: 'الصورة صغيرة جداً. تأكد من رفع صورة واضحة للإيصال.' };
  }

  // 4. محاولة فك ترميز الصورة في المتصفح — تشخيصية فقط (Fail-Open)
  //    فشل هذه الخطوة لا يعني أن الملف مزيّف: قد يكون HEIC غير مدعوم في هذا
  //    المتصفح، أو صورة ضخمة الأبعاد على جهاز ضعيف، أو خطأ فك ترميز عابر.
  //    قواعد المشروع: خطأ تقني ⇒ مراجعة يدوية، لا منع العميل من إكمال الطلب.
  const decode = await new Promise(resolve => {
    let done = false;
    const img = new Image();
    const url = URL.createObjectURL(file);
    const finish = (value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      URL.revokeObjectURL(url);
      resolve(value);
    };
    const timer = setTimeout(() => finish({ ok: false, reason: 'decode_timeout' }), 7000);
    img.onload  = () => finish({ ok: true, width: img.naturalWidth, height: img.naturalHeight });
    img.onerror = () => finish({ ok: false, reason: 'decode_error' });
    img.src = url;
  });

  if (!decode.ok) {
    // لا نُرجع valid:false — نُرجع صلاحية مع علامة تستدعي مراجعة يدوية
    return {
      valid: true,
      needsManualReview: true,
      reason: decode.reason,
      message: 'تعذّر معاينة الصورة في هذا المتصفح. تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب.'
    };
  }

  // أبعاد صغيرة جداً: تحذير يستدعي مراجعة يدوية، وليس رفضاً
  if (decode.width < 200 || decode.height < 200) {
    return {
      valid: true,
      needsManualReview: true,
      reason: 'dimensions_too_small',
      width: decode.width,
      height: decode.height,
      message: 'أبعاد الصورة صغيرة وقد تكون غير واضحة. تم استلام إيصالك وسيُراجع يدوياً من الإدارة.'
    };
  }

  return { valid: true, width: decode.width, height: decode.height };
}

// =========================================================
// تسجيل محاولة إيصال مشبوهة (تكرار/رفض/فشل تقني) في القاعدة
// عبر RPC آمنة (SECURITY DEFINER). التسجيل ثانوي: لا يرمي خطأً
// ولا يعطّل تدفق الدفع مهما فشل.
// =========================================================
async function logReceiptFraudAttempt({ reference, reason, provider, ocrExcerpt, orderAmount, metadata } = {}) {
  try {
    if (!supabaseClient) return null;
    const { data } = await supabaseClient.rpc('log_receipt_fraud_attempt', {
      p_entered_reference: reference || null,
      p_reason:            reason || 'unknown',
      p_provider:          provider || null,
      p_ocr_excerpt:       ocrExcerpt ? String(ocrExcerpt).slice(0, 300) : null,
      p_order_amount:      (typeof orderAmount === 'number') ? orderAmount : null,
      p_metadata:          metadata || {}
    });
    return data || null;
  } catch (e) {
    // التسجيل ثانوي — لا نعطّل العميل بسببه
    return null;
  }
}

// =========================================================
// ⚠️ توافق قديم: التفويض الوحيد المسموح هو Supabase Edge Function.
// لا يوجد OCR أو قرار مالي داخل المتصفح حتى لو استدعى كود قديم هذه الدالة.
// =========================================================
async function verifyReceiptContent(fileOrUrl, statusCallback, transactionRef, expectedAmountSDG) {
  // Fail-Closed افتراضياً: تعليق للمراجعة اليدوية، لا قبول.
  const NEEDS_REVIEW = { passed: false, ocr_status: 'needs_review', amount_verified: false };

  const canDelegate =
    typeof window !== 'undefined' &&
    window.RaizeyReceiptPipeline &&
    typeof window.RaizeyReceiptPipeline.analyze === 'function' &&
    (typeof File !== 'undefined' && fileOrUrl instanceof Blob);

  if (!canDelegate) {
    devWarn('[RAIZEY receipt] verifyReceiptContent: Edge Function غير متاحة — مراجعة يدوية (fail-closed)');
    return NEEDS_REVIEW;
  }

  try {
    if (statusCallback) statusCallback('جارِ فحص صورة الإيصال على الخادم...');
    const analysis = await window.RaizeyReceiptPipeline.analyze(fileOrUrl, {
      manualRef: transactionRef || '',
      expectedAmount: Number(expectedAmountSDG) || 0,
      onStatus: statusCallback || undefined
    });

    if (!analysis || typeof analysis !== 'object') return NEEDS_REVIEW;
    return {
      passed:          analysis.decision === 'accept' && !!analysis.scanId,
      ocr_status:      analysis.ocrStatus || (analysis.decision === 'reject' ? 'rejected' : 'needs_review'),
      amount_verified: !!analysis.amountVerified,
      ref_verified:    !!analysis.refVerified,
      decision:        analysis.decision || 'review',
      scan_id:         analysis.scanId || null,
      receipt_hash:    analysis.receiptHash || null,
      message:         analysis.message || ''
    };
  } catch (e) {
    devWarn('[RAIZEY receipt] Edge Function delegate error — مراجعة يدوية:', e && e.message);
    return NEEDS_REVIEW;
  }
}
