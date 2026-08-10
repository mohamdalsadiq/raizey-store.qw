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
  if (msg.includes('product_not_found'))
    return 'أحد المنتجات في سلتك لم يعد متاحاً.';
  if (msg.includes('price_calculation'))
    return 'خطأ في حساب السعر، يرجى تحديث الصفحة والمحاولة مجدداً.';
  if (msg.includes('coupon') || msg.includes('discount'))
    return 'انتهت صلاحية كود الخصم أو نفدت كميته.';
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

// بصمة رقمية SHA-256 لملف الإيصال — تُستخدم لكشف الإيصالات المكررة
async function hashFile(file) {
  try {
    const buffer      = await file.arrayBuffer();
    const hashBuffer  = await crypto.subtle.digest('SHA-256', buffer);
    return Array.from(new Uint8Array(hashBuffer))
      .map(b => b.toString(16).padStart(2, '0')).join('');
  } catch (e) {
    devWarn('[RAIZEY] hashFile error:', e);
    return null;
  }
}

function normalizeArabicDigits(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/[٠-٩]/g, d => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
    .replace(/[۰-۹]/g, d => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d)));
}

function normalizeWhitespace(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function normalizeTransactionReference(value) {
  const normalized = normalizeArabicDigits(value)
    .toUpperCase()
    .replace(/[\r\n\s\-_:/\\.,]+/g, '')
    .replace(/[^A-Z0-9]/g, '');
  return normalized;
}

function isMissingColumnError(error) {
  const msg = String(error?.message || error || '').toLowerCase();
  return msg.includes('column') && (msg.includes('does not exist') || msg.includes('could not find'));
}

function isRpcSignatureError(error) {
  const msg = String(error?.message || error || '').toLowerCase();
  return (
    msg.includes('could not find the function') ||
    msg.includes('function is not unique') ||
    msg.includes('no function matches') ||
    msg.includes('pgrst202')
  );
}

async function rpcWithFallback(functionName, primaryArgs, fallbackArgsList = []) {
  const client = requireClient();
  const first = await client.rpc(functionName, primaryArgs);
  if (!first.error || !isRpcSignatureError(first.error) || fallbackArgsList.length === 0) {
    return first;
  }

  for (const fallbackArgs of fallbackArgsList) {
    const fallback = await client.rpc(functionName, fallbackArgs);
    if (!fallback.error || !isRpcSignatureError(fallback.error)) {
      return fallback;
    }
  }

  return first;
}

async function validateCouponCompat(code, amountSdg = 0) {
  return rpcWithFallback(
    'validate_coupon',
    { p_code: code, p_amount_sdg: Math.round(Number(amountSdg) || 0) },
    [{ p_code: code }]
  );
}

async function useCouponAtomicCompat(code, amountSdg = 0) {
  return rpcWithFallback(
    'use_coupon_atomic',
    { p_code: code, p_amount_sdg: Math.round(Number(amountSdg) || 0) },
    [{ p_code: code }]
  );
}

async function findExistingPaymentRecord(column, rawValue) {
  const cleanValue = String(rawValue || '').trim();
  if (!cleanValue) return null;

  const lookups = ['orders', 'wallet_topups'].map(async (table) => {
    try {
      const { data, error } = await requireClient()
        .from(table)
        .select('id')
        .eq(column, cleanValue)
        .limit(1)
        .maybeSingle();
      if (error) return null;
      return data ? { table, id: data.id } : null;
    } catch (error) {
      return null;
    }
  });

  const results = await Promise.all(lookups);
  return results.find(Boolean) || null;
}

// فحص إذا كانت بصمة الإيصال أو رقم العملية مستخدمة من قبل في أي مسار دفع
async function checkDuplicateReceipt(table, hashOrRef) {
  void table;
  if (!hashOrRef) return false;
  const cleanHash = String(hashOrRef).trim();
  if (!cleanHash) return false;
  return !!(await findExistingPaymentRecord('receipt_hash', cleanHash));
}

// فحص منفصل لتكرار رقم العملية (transaction_reference) على مستوى الطلبات والشحن
async function checkDuplicateTransactionRef(table, transactionRef) {
  void table;
  const cleanRef = normalizeTransactionReference(transactionRef);
  if (!cleanRef) return false;

  const directMatch = await findExistingPaymentRecord('transaction_reference', cleanRef);
  if (directMatch) return true;

  const normalizedColumnMatch = await findExistingPaymentRecord('transaction_reference_norm', cleanRef);
  return !!normalizedColumnMatch;
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

function stripKeysFromPayload(payload, keysToStrip = []) {
  if (!keysToStrip.length) return payload;
  if (Array.isArray(payload)) {
    return payload.map(row => stripKeysFromPayload(row, keysToStrip));
  }
  if (!payload || typeof payload !== 'object') return payload;
  const cloned = { ...payload };
  keysToStrip.forEach(key => { delete cloned[key]; });
  return cloned;
}

async function insertWithOptionalColumns(table, payload, optionalKeys = [], selectClause = '*', useSingle = false) {
  const runInsert = async (body) => {
    let query = requireClient().from(table).insert(body);
    if (selectClause) query = query.select(selectClause);
    if (useSingle) query = query.single();
    return query;
  };

  let response = await runInsert(payload);
  if (!response.error || !optionalKeys.length || !isMissingColumnError(response.error)) {
    return response;
  }

  response = await runInsert(stripKeysFromPayload(payload, optionalKeys));
  return response;
}

// =========================================================
// التحقق من صلاحية صورة الإي��ال (نوع + حجم + صحة الملف)
// =========================================================
async function validateReceiptImage(file) {
  if (!file) {
    return { valid: false, message: 'لم يتم اختيار أي ملف.' };
  }

  // 1. فحص نوع MIME + الامتداد
  const allowedMime = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
  const allowedExts = ['jpg', 'jpeg', 'png', 'webp'];
  const fileExt     = (file.name.split('.').pop() || '').toLowerCase();

  if (!allowedMime.includes(file.type.toLowerCase()) || !allowedExts.includes(fileExt)) {
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

  // 4. تحقق من أن الملف صورة حقيقية قابلة للتحميل
  const isValidImage = await new Promise(resolve => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload  = () => { URL.revokeObjectURL(url); resolve(true);  };
    img.onerror = () => { URL.revokeObjectURL(url); resolve(false); };
    img.src = url;
  });

  if (!isValidImage) {
    return { valid: false, message: 'الملف المرفوع ليس صورة صالحة. يرجى التحقق من الملف وإعادة المحاولة.' };
  }

  return { valid: true };
}

const RECEIPT_PROVIDERS = [
  {
    key: 'bankak',
    label: 'بنكك',
    keywords: ['bankak', 'بنكك', 'bank of khartoum', 'بنك الخرطوم'],
  },
  {
    key: 'okash',
    label: 'أوكاش',
    keywords: ['okash', 'اوكاش', 'أوكاش', 'ok cash'],
  },
  {
    key: 'fawry',
    label: 'فوري',
    keywords: ['fawry', 'فوري', 'faury'],
  }
];

const RECEIPT_LABELS = {
  reference: ['transaction id', 'transaction no', 'transaction number', 'reference', 'reference no', 'ref no', 'txn id', 'رقم العملية', 'رقم الحركة', 'الرقم المرجعي', 'رقم المرجع'],
  amount: ['amount', 'total', 'paid', 'received', 'المبلغ', 'المبلغ المحول', 'الإجمالي', 'المبلغ المدفوع', 'المحول'],
  date: ['date', 'time', 'التاريخ', 'الوقت', 'بتاريخ'],
  success: ['successful', 'success', 'completed', 'تم بنجاح', 'تمت بنجاح', 'ناجح', 'نجحت العملية', 'successful transfer'],
  failure: ['failed', 'failure', 'rejected', 'cancelled', 'declined', 'فشل', 'فاشلة', 'مرفوض', 'ملغي', 'لم تنجح'],
  sender: ['from', 'sender', 'المرسل', 'من حساب', 'من'],
  receiver: ['to', 'receiver', 'recipient', 'المستلم', 'إلى', 'لحساب'],
  receipt: ['receipt', 'payment', 'transfer', 'transaction', 'bank', 'wallet', 'إيصال', 'اشعار', 'إشعار', 'تحويل', 'دفع', 'عملية']
};

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseReceiptLines(text) {
  return normalizeArabicDigits(text)
    .replace(/\u200f|\u200e/g, '')
    .split(/\r?\n/)
    .map(line => normalizeWhitespace(line))
    .filter(Boolean);
}

function detectReceiptProvider(text) {
  const haystack = normalizeArabicDigits(text).toLowerCase();
  let best = null;

  for (const provider of RECEIPT_PROVIDERS) {
    const score = provider.keywords.reduce((total, keyword) => {
      return total + (haystack.includes(normalizeArabicDigits(keyword).toLowerCase()) ? 1 : 0);
    }, 0);
    if (!best || score > best.score) {
      best = { provider, score };
    }
  }

  return best && best.score > 0 ? best.provider : null;
}

function lineHasAnyKeyword(line, keywords = []) {
  const normalizedLine = normalizeArabicDigits(line).toLowerCase();
  return keywords.some(keyword => normalizedLine.includes(normalizeArabicDigits(keyword).toLowerCase()));
}

function extractTextAfterLabel(line, labels = []) {
  for (const label of labels) {
    const pattern = new RegExp(`${escapeRegex(normalizeArabicDigits(label))}\\s*[:#\\-]?\s*(.+)$`, 'i');
    const match = normalizeArabicDigits(line).match(pattern);
    if (match && match[1]) return normalizeWhitespace(match[1]);
  }
  return '';
}

function collectReferenceCandidates(lines) {
  const candidates = [];

  lines.forEach((line, index) => {
    const normalizedLine = normalizeArabicDigits(line);
    if (lineHasAnyKeyword(line, RECEIPT_LABELS.reference)) {
      const direct = extractTextAfterLabel(normalizedLine, RECEIPT_LABELS.reference);
      if (direct) candidates.push(direct);
      if (lines[index + 1]) candidates.push(lines[index + 1]);
    }

    const genericMatches = normalizedLine.match(/(?:[A-Z]{1,4}\d{5,18}|\d{8,20}|[A-Z0-9]{8,24})/gi) || [];
    genericMatches.forEach(match => candidates.push(match));
  });

  const normalizedCandidates = candidates
    .map(candidate => normalizeTransactionReference(candidate))
    .filter(candidate => candidate.length >= 6)
    .filter(candidate => !/^\d{1,6}$/.test(candidate));

  const weighted = normalizedCandidates
    .map(candidate => ({
      candidate,
      score: (/^[A-Z]+\d+$/.test(candidate) ? 4 : 0) + (/\d{8,}/.test(candidate) ? 3 : 0) + Math.min(candidate.length, 12)
    }))
    .sort((a, b) => b.score - a.score);

  return weighted.map(item => item.candidate);
}

function parseAmountToken(value) {
  const normalized = normalizeArabicDigits(value)
    .replace(/[^\d.,]/g, '')
    .replace(/,/g, '');
  const amount = parseFloat(normalized);
  return Number.isFinite(amount) ? amount : null;
}

function collectAmountCandidates(lines, expectedAmountSDG = 0) {
  const candidates = [];
  const expectedRounded = Math.round(Number(expectedAmountSDG) || 0);

  lines.forEach((line) => {
    const normalizedLine = normalizeArabicDigits(line);
    const lineHasAmountLabel = lineHasAnyKeyword(normalizedLine, RECEIPT_LABELS.amount);
    const numericMatches = normalizedLine.match(/\d[\d,\.]{0,15}/g) || [];
    numericMatches.forEach(match => {
      const parsed = parseAmountToken(match);
      if (!Number.isFinite(parsed) || parsed <= 0) return;
      const rounded = Math.round(parsed);
      const distance = expectedRounded > 0 ? Math.abs(rounded - expectedRounded) : 999999;
      candidates.push({
        amount: parsed,
        rounded,
        confident: lineHasAmountLabel,
        distance
      });
    });
  });

  candidates.sort((a, b) => {
    if (a.confident !== b.confident) return a.confident ? -1 : 1;
    return a.distance - b.distance;
  });

  return candidates;
}

function extractReceiptDateTime(lines) {
  const joined = lines.join(' ');
  const match = normalizeArabicDigits(joined).match(/(\d{1,4}[\/\-]\d{1,2}[\/\-]\d{1,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)/);
  return match ? match[1] : null;
}

function extractAccountDetails(lines, labels) {
  for (const line of lines) {
    if (!lineHasAnyKeyword(line, labels)) continue;
    const direct = extractTextAfterLabel(line, labels);
    if (direct) return direct;
  }
  return null;
}

function analyzeReceiptText(text, transactionRef, expectedAmountSDG = 0) {
  const lines = parseReceiptLines(text);
  const provider = detectReceiptProvider(text);
  const referenceCandidates = collectReferenceCandidates(lines);
  const extractedReference = referenceCandidates[0] || null;
  const extractedReferenceNorm = normalizeTransactionReference(extractedReference);
  const manualReferenceNorm = normalizeTransactionReference(transactionRef);
  const amountCandidates = collectAmountCandidates(lines, expectedAmountSDG);
  const bestAmount = amountCandidates[0] || null;
  const expectedRounded = Math.round(Number(expectedAmountSDG) || 0);
  const amountVerified = !!(bestAmount && expectedRounded > 0 && Math.abs(bestAmount.rounded - expectedRounded) <= 1);
  const status = lines.some(line => lineHasAnyKeyword(line, RECEIPT_LABELS.failure))
    ? 'failed'
    : (lines.some(line => lineHasAnyKeyword(line, RECEIPT_LABELS.success)) ? 'success' : 'unknown');
  const hasReceiptKeywords = lines.some(line => lineHasAnyKeyword(line, RECEIPT_LABELS.receipt));
  const hasReferenceLabel = lines.some(line => lineHasAnyKeyword(line, RECEIPT_LABELS.reference));
  const hasDate = !!extractReceiptDateTime(lines);
  const matchesManualReference = !!(manualReferenceNorm && extractedReferenceNorm && manualReferenceNorm === extractedReferenceNorm);
  const referenceConflict = !!(manualReferenceNorm && extractedReferenceNorm && manualReferenceNorm !== extractedReferenceNorm);

  const isReceiptLike = !!(
    provider &&
    hasReceiptKeywords &&
    ((hasReferenceLabel && extractedReferenceNorm) || bestAmount || hasDate)
  );

  return {
    raw_text: normalizeWhitespace(text).slice(0, 4000),
    provider: provider ? provider.key : null,
    provider_label: provider ? provider.label : null,
    extracted_transaction_reference: extractedReference,
    extracted_transaction_reference_norm: extractedReferenceNorm || null,
    extracted_amount: bestAmount ? bestAmount.rounded : null,
    amount_confident: !!(bestAmount && bestAmount.confident),
    amount_verified: amountVerified,
    status,
    is_receipt_like: isReceiptLike,
    matches_manual_reference: matchesManualReference,
    reference_conflict: referenceConflict,
    extracted_date_time: extractReceiptDateTime(lines),
    sender_account: extractAccountDetails(lines, RECEIPT_LABELS.sender),
    receiver_account: extractAccountDetails(lines, RECEIPT_LABELS.receiver)
  };
}

async function prepareImageForOCR(fileOrUrl) {
  const sourceUrl = typeof fileOrUrl === 'string' ? fileOrUrl : URL.createObjectURL(fileOrUrl);
  try {
    const image = await new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error('image_load_failed'));
      img.src = sourceUrl;
    });

    const maxWidth = 1600;
    const scale = image.width > maxWidth ? (maxWidth / image.width) : 1;
    const width = Math.max(1, Math.round(image.width * scale));
    const height = Math.max(1, Math.round(image.height * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(image, 0, 0, width, height);

    const imageData = context.getImageData(0, 0, width, height);
    const { data } = imageData;
    for (let i = 0; i < data.length; i += 4) {
      const gray = Math.min(255, Math.max(0, (data[i] * 0.299) + (data[i + 1] * 0.587) + (data[i + 2] * 0.114)));
      const boosted = gray > 170 ? 255 : gray < 90 ? 0 : gray;
      data[i] = boosted;
      data[i + 1] = boosted;
      data[i + 2] = boosted;
    }
    context.putImageData(imageData, 0, 0);
    return canvas.toDataURL('image/png');
  } finally {
    if (typeof fileOrUrl !== 'string') {
      URL.revokeObjectURL(sourceUrl);
    }
  }
}

async function runTesseractPass(source, languages, timeoutMs) {
  if (typeof Tesseract === 'undefined') {
    return { text: '', language: languages, timed_out: false, error: 'tesseract_unavailable' };
  }

  let timer = null;
  try {
    const result = await Promise.race([
      Tesseract.recognize(source, languages, { logger: () => {} }),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('ocr_timeout')), timeoutMs);
      })
    ]);
    return {
      text: result?.data?.text || '',
      language: languages,
      timed_out: false,
      error: null
    };
  } catch (error) {
    return {
      text: '',
      language: languages,
      timed_out: String(error?.message || error) === 'ocr_timeout',
      error: String(error?.message || error || 'ocr_failed')
    };
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function buildReceiptDecision(scan, expectedAmountSDG) {
  if (!scan.is_receipt_like || !scan.provider) {
    return {
      passed: false,
      ocr_status: 'rejected_non_receipt',
      amount_verified: false,
      message: 'الصورة المرفوعة لا تبدو كإشعار تحويل معتمد من بنكك أو أوكاش أو فوري.'
    };
  }

  if (scan.status === 'failed') {
    return {
      passed: false,
      ocr_status: 'rejected_failed_transfer',
      amount_verified: false,
      message: 'الإيصال المرفوع يوضح أن العملية غير ناجحة، لذلك تم رفضه.'
    };
  }

  if (scan.reference_conflict) {
    return {
      passed: false,
      ocr_status: 'rejected_reference_mismatch',
      amount_verified: false,
      message: 'رقم العملية المكتوب لا يطابق الرقم الظاهر داخل صورة الإيصال.'
    };
  }

  if (scan.extracted_amount !== null && expectedAmountSDG > 0 && !scan.amount_verified) {
    return {
      passed: false,
      ocr_status: 'rejected_amount_mismatch',
      amount_verified: false,
      message: 'المبلغ الظاهر في الإيصال لا يطابق إجمالي الطلب.'
    };
  }

  if (!scan.extracted_transaction_reference_norm || scan.status === 'unknown' || !scan.amount_confident) {
    return {
      passed: true,
      ocr_status: 'needs_review',
      amount_verified: scan.amount_verified,
      message: 'تم قبول الإيصال مبدئياً، لكن سيخضع لمراجعة إضافية بسبب ضعف جودة القراءة.'
    };
  }

  return {
    passed: true,
    ocr_status: 'passed',
    amount_verified: scan.amount_verified,
    message: ''
  };
}

// =========================================================
// فحص محتوى الإيصال بـ OCR + تصنيف نوعه واستخراج الحقول المهمة
// =========================================================
async function verifyReceiptContent(fileOrUrl, statusCallback, transactionRef, expectedAmountSDG) {
  const defaultResult = {
    passed: false,
    ocr_status: 'rejected_unreadable',
    amount_verified: false,
    message: 'تعذر قراءة الإيصال بوضوح. ارفع لقطة شاشة أو صورة أوضح لإشعار التحويل.',
    provider: null,
    scan_data: {
      provider: null,
      is_receipt_like: false,
      status: 'unknown'
    }
  };

  try {
    const preparedSource = await prepareImageForOCR(fileOrUrl).catch(() => fileOrUrl);
    const passes = [];
    const collectedTexts = [];

    if (statusCallback) statusCallback('جارِ تحليل صورة الإيصال...');
    const fastPass = await runTesseractPass(preparedSource, 'eng', 7000);
    passes.push({ language: fastPass.language, timed_out: fastPass.timed_out, error: fastPass.error });
    if (fastPass.text) collectedTexts.push(fastPass.text);

    let analysis = analyzeReceiptText(collectedTexts.join('\n'), transactionRef, expectedAmountSDG);
    const needsArabicPass = !analysis.provider || !analysis.is_receipt_like || !analysis.extracted_transaction_reference_norm;

    if (needsArabicPass) {
      if (statusCallback) statusCallback('جارِ التحقق من نوع الإيصال وبياناته...');
      const arabicPass = await runTesseractPass(preparedSource, 'ara+eng', 14000);
      passes.push({ language: arabicPass.language, timed_out: arabicPass.timed_out, error: arabicPass.error });
      if (arabicPass.text) collectedTexts.push(arabicPass.text);
      analysis = analyzeReceiptText(collectedTexts.join('\n'), transactionRef, expectedAmountSDG);
    }

    const decision = buildReceiptDecision(analysis, expectedAmountSDG);
    return {
      ...decision,
      provider: analysis.provider,
      scan_data: {
        ...analysis,
        expected_amount: Math.round(Number(expectedAmountSDG) || 0),
        manual_transaction_reference: normalizeTransactionReference(transactionRef),
        ocr_passes: passes
      }
    };
  } catch (error) {
    devWarn('[RAIZEY OCR] Fatal error:', error?.message || error);
    return defaultResult;
  }
}
