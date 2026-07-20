// =========================================================
// RAIZEY STORE — Supabase Client
// =========================================================
const SUPABASE_URL = "https://rglbfizqolrenwfsndyv.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJnbGJmaXpxb2xyZW53ZnNuZHl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNDY4NzMsImV4cCI6MjA5ODcyMjg3M30.bJywsPvgXPdsNOZlVTIwYHz3Z2zcobwinGuUXAb5ev4";

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// دالة مساعدة: جلب سعر الصرف مع هامش الربح مطبق تلقائياً
async function getExchangeRate() {
  const { data, error } = await supabaseClient
    .from('settings')
    .select('key, value')
    .in('key', ['usd_to_sdg_rate', 'profit_margin_percent']);

  if (error || !data) return 0;

  const map = {};
  data.forEach(row => { map[row.key] = parseFloat(row.value) || 0; });

  const rate = map.usd_to_sdg_rate || 0;
  const margin = map.profit_margin_percent || 0;

  return rate * (1 + margin / 100);
}

// دالة مساعدة: تنسيق السعر بالجنيه (أرقام إنجليزية لتطابق خط الأسعار الرقمي)
function formatSDG(amount) {
  return new Intl.NumberFormat('en-US').format(Math.round(amount));
}

// بصمة رقمية SHA-256 لملف الإيصال — تُستخدم لكشف الإيصالات المكررة
async function hashFile(file) {
  const buffer = await file.arrayBuffer();
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, '0')).join('');
}

// فحص إذا كانت بصمة الإيصال مستخدمة من قبل في نفس الجدول (orders أو wallet_topups)
async function checkDuplicateReceipt(table, hash) {
  const { data } = await supabaseClient
    .from(table)
    .select('id')
    .eq('receipt_hash', hash)
    .limit(1)
    .maybeSingle();
  return !!data;
}

// =========================================================
// تنظيف HTML لمنع هجمات XSS
// =========================================================
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;');
}

// =========================================================
// التحقق من صلاحية صورة الإيصال (نوع + حجم + صحة الملف)
// =========================================================
async function validateReceiptImage(file) {
  // 1. فحص نوع MIME + الامتداد
  const allowedMime = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
  const allowedExts = ['jpg', 'jpeg', 'png', 'webp'];
  const fileExt = (file.name.split('.').pop() || '').toLowerCase();

  if (!allowedMime.includes(file.type.toLowerCase()) || !allowedExts.includes(fileExt)) {
    return { valid: false, message: 'نوع الملف غير مدعوم. استخدم JPG أو PNG أو WEBP فقط.' };
  }

  // 2. فحص الحجم (أقل من 5 ميجابايت)
  if (file.size > 5 * 1024 * 1024) {
    return { valid: false, message: 'حجم الصورة كبير جداً. الحد الأقصى المسموح 5 ميجابايت.' };
  }

  // 3. الحجم الأدنى (أكبر من 10 كيلوبايت — لمنع الصور المجردة أو الفارغة)
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

// =========================================================
// فحص محتوى الإيصال بـ OCR (Tesseract.js) مع مهلة آمنة
// تُفعَّل فقط إذا كانت مكتبة Tesseract محمّلة في الصفحة
// =========================================================
async function verifyReceiptContent(file, statusCallback) {
  // كلمات مفتاحية مالية تُشير إلى وثيقة تحويل/إيصال حقيقية
  const keywords = [
    'تحويل', 'بنكك', 'أوكاش', 'ذهب', 'رقم العملية', 'رقم التحويل',
    'تاريخ', 'المبلغ', 'SDG', 'ج.س', 'رصيد', 'مرسل', 'مستلم',
    'Amount', 'Transfer', 'Receipt', 'Transaction', 'Balance',
    'مدفوع', 'دفع', 'شحن', 'محفظة'
  ];

  if (typeof Tesseract === 'undefined') {
    return { passed: true, skipped: true, reason: 'tesseract_not_loaded' };
  }

  return new Promise(async (resolve) => {
    // مهلة 30 ثانية — بعدها نسمح بالرفع مع تحذير
    const timeout = setTimeout(() => {
      resolve({ passed: true, skipped: true, reason: 'timeout' });
    }, 30000);

    try {
      if (statusCallback) statusCallback('جارِ فحص صورة الإيصال...');

      const result = await Tesseract.recognize(file, 'ara+eng', {
        logger: () => {}  // إخفاء سجلات التشخيص
      });

      clearTimeout(timeout);
      const text = (result.data.text || '').trim();
      const found = keywords.some(kw => text.includes(kw));

      resolve({ passed: found, text, skipped: false });
    } catch (e) {
      clearTimeout(timeout);
      // في حالة أي خطأ غير متوقع نسمح بالرفع
      resolve({ passed: true, skipped: true, reason: e.message });
    }
  });
}
