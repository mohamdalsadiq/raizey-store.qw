// =========================================================
// RAIZEY STORE — Supabase Client
// =========================================================
const SUPABASE_URL = "https://rglbfizqolrenwfsndyv.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJnbGJmaXpxb2xyZW53ZnNuZHl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNDY4NzMsImV4cCI6MjA5ODcyMjg3M30.bJywsPvgXPdsNOZlVTIwYHz3Z2zcobwinGuUXAb5ev4";

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// دالة مساعدة: جلب سعر الصرف مع هامش الربح مطبق تلقائياً
async function getExchangeRate() {
  try {
    const { data, error } = await supabaseClient
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
    console.error('[RAIZEY] getExchangeRate error:', e);
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
    console.error('[RAIZEY] hashFile error:', e);
    return null;
  }
}

// فحص إذا كانت بصمة الإيصال أو رقم العملية مستخدمة من قبل في نفس الجدول (orders أو wallet_topups)
async function checkDuplicateReceipt(table, hashOrRef) {
  if (!hashOrRef) return false;
  const cleanVal = String(hashOrRef).trim();

  try {
    // 1. فحص بعمود receipt_hash
    const { data: dataHash } = await supabaseClient
      .from(table)
      .select('id')
      .eq('receipt_hash', cleanVal)
      .limit(1)
      .maybeSingle();

    if (dataHash) return true;
  } catch (e) {
    console.warn('[RAIZEY] checkDuplicateReceipt (hash) error:', e);
  }

  // 2. فحص بعمود transaction_reference احتياطياً إن وجد
  try {
    const { data: dataRef } = await supabaseClient
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
  const cleanRef = String(transactionRef).replace(/[\r\n\s\-_]+/g, '');
  if (!cleanRef) return false;

  try {
    const { data } = await supabaseClient
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

// =========================================================
// التحقق من صلاحية صورة الإيصال (نوع + حجم + صحة الملف)
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

// =========================================================
// فحص محتوى الإيصال بـ OCR (Tesseract.js) — نظام الإبلاغ فقط
//
// ⚠️  لا يوقف هذا الكود أي طلب أبداً.
//     النتيجة دائماً passed: true.
//     ocr_status / amount_verified تُحفظ في قاعدة البيانات
//     لتظهر للأدمن كـ 🟢 أو 🟡 فقط.
// =========================================================
async function verifyReceiptContent(fileOrUrl, statusCallback, transactionRef, expectedAmountSDG) {
  // الحالة الافتراضية: تمرير الطلب + طلب مراجعة يدوية
  const SOFT_PASS = { passed: true, ocr_status: 'needs_review', amount_verified: false };

  // إذا لم تُحمَّل Tesseract — نمرّر الطلب ونضعه للمراجعة
  if (typeof Tesseract === 'undefined') {
    console.log('[RAIZEY OCR] Tesseract not loaded — soft pass');
    return SOFT_PASS;
  }

  return new Promise(async (resolve) => {
    // مهلة 20 ثانية — إذا انتهت نمرّر الطلب للمراجعة
    const timeout = setTimeout(() => {
      console.log('[RAIZEY OCR] Timeout — soft pass');
      resolve(SOFT_PASS);
    }, 20000);

    try {
      if (statusCallback) statusCallback('جارِ فحص صورة الإيصال...');

      const result = await Tesseract.recognize(fileOrUrl, 'ara+eng', { logger: () => {} });
      clearTimeout(timeout);

      const text = (result.data.text || '').trim();
      console.log('[RAIZEY OCR] Extracted text length:', text.length);

      // إذا كان النص قصير جداً → لا يمكن التحقق → مراجعة يدوية
      if (text.length < 10) {
        console.log('[RAIZEY OCR] Text too short — needs_review');
        resolve(SOFT_PASS);
        return;
      }

      // ── 1. فحص رقم العملية (للإبلاغ فقط) ──
      let refMatched = false;
      if (transactionRef && transactionRef.trim()) {
        const userDigits = transactionRef.replace(/\D/g, '');
        const ocrDigits  = text.replace(/\D/g, '');
        if (userDigits.length > 0) {
          const fullMatch    = ocrDigits.includes(userDigits);
          const partialMatch = userDigits.length > 4 && ocrDigits.includes(userDigits.slice(0, -1));
          refMatched = fullMatch || partialMatch;
          console.log('[RAIZEY OCR] Ref check — userDigits:', userDigits, '| matched:', refMatched);
        }
      } else {
        // لا يوجد رقم عملية لمقارنته → نعتبره غير محقَّق
        refMatched = false;
      }

      // ── 2. فحص المبلغ (للإبلاغ فقط) ──
      let amountMatched = false;
      if (expectedAmountSDG && expectedAmountSDG > 0) {
        // استخراج كل الأرقام الموجودة في النص (بما فيها الأرقام العربية)
        const normalised = text
          .replace(/[٠-٩]/g, d => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
          .replace(/,/g, '');
        const amounts = [...normalised.matchAll(/\d[\d.]*\d|\d/g)]
          .map(m => parseFloat(m[0]))
          .filter(n => !isNaN(n) && n > 0);

        const rounded = Math.round(expectedAmountSDG);
        // نقبل تطابقاً بهامش ±1%
        amountMatched = amounts.some(a => Math.abs(a - rounded) / rounded <= 0.01);
        console.log('[RAIZEY OCR] Amount check — expected:', rounded, '| found amounts:', amounts, '| matched:', amountMatched);
      }

      // ── 3. القرار النهائي ──
      // passed دائماً true — فقط ocr_status و amount_verified تتغير
      if (refMatched && (!expectedAmountSDG || amountMatched)) {
        resolve({ passed: true, ocr_status: 'passed', amount_verified: amountMatched });
      } else {
        resolve({ passed: true, ocr_status: 'needs_review', amount_verified: amountMatched });
      }

    } catch (e) {
      clearTimeout(timeout);
      console.warn('[RAIZEY OCR] Error — soft pass:', e.message);
      resolve(SOFT_PASS);
    }
  });
}
