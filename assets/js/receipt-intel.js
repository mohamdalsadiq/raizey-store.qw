/* =========================================================================
 * RAIZEY STORE — محرك الفحص الذكي لإيصالات التحويل (Receipt Intelligence v3)
 * =========================================================================
 * مسار الملف: assets/js/receipt-intel.js
 *
 * يعمل بالكامل في المتصفح (بلا سيرفر) ويعتمد على Tesseract.js v5.
 * يجب تحميل tesseract.min.js قبل هذا الملف.
 *
 * ما الجديد في v3:
 *  • قراءة متعددة المراحل (Multi-Pass OCR): كل مرحلة بمعالجة صورة مختلفة
 *    (تحسين تباين → تحويل ثنائي Otsu مع عكس تلقائي للوضع الليلي → تكبير
 *     وتحديد حواف + قراءة أرقام فقط). لا تتوقف المراحل إلا عند إيجاد
 *     رقم العملية والمبلغ، فترتفع نسبة النجاح بشكل كبير.
 *  • دعم كامل للعربية والإنجليزية في كل شيء: أسماء البنوك، تسميات الحقول،
 *    كلمات النجاح/الفشل، أسماء الشهور، صيغ الأرقام والعملات.
 *  • قراءة سطرية (Line-Aware): يقرأ قيمة الحقل من نفس السطر أو السطر التالي
 *    مثل ما تظهر فعلياً في إشعارات بنكك/أوكاش/فوري/كاشي.
 *  • تصحيح أخطاء OCR الشائعة داخل الأرقام (O→0، l→1، S→5، B→8 ...).
 *  • فهم صيغ المبالغ: 52,332 / 52332.00 / 52.332,00 / 52 332 / SDG 52,332.
 *  • استبعاد "الرصيد/الرسوم/العمولة" من مطابقة المبلغ حتى لا يُرفض عميل
 *    صادق بسبب رقم رصيد ظهر في نفس الإشعار.
 *  • الرفض لا يحدث إلا بيقين عالٍ:
 *      – ملف غير صالح
 *      – صورة معدّلة ببرنامج تحرير
 *      – عملية فاشلة/مرفوضة مكتوبة في الإشعار
 *      – الصورة ليست إشعار تحويل إطلاقاً
 *      – رقم العملية في الصورة يخالف ما كتبه العميل (مصدره حقل موسوم)
 *      – المبلغ الموسوم في الإشعار لا يطابق إجمالي الطلب
 *    وأي حالة "قراءة ضعيفة" تُحوَّل للمراجعة اليدوية ولا تُرفض أبداً.
 *  • التكرار (نفس رقم العملية / نفس الصورة) يُرفض في قاعدة البيانات ذرّياً
 *    عبر claim_payment_receipt — لأن أي فحص في المتصفح قابل للتجاوز.
 * ========================================================================= */

(function () {
  'use strict';

  // ═══════════════════════════════════════════════════════════════════
  // 1) الإعدادات
  // ═══════════════════════════════════════════════════════════════════
  const CONFIG = {
    passTimeoutMs:     15000,  // مهلة كل مرحلة قراءة على حدة
    totalBudgetMs:     40000,  // سقف زمني كلي لكل مراحل القراءة
    engineTimeoutMs:   18000,  // مهلة تجهيز المحرك بالعربية+الإنجليزية
    engineFallbackMs:  12000,  // مهلة تجهيز المحرك بالإنجليزية فقط
    hardDeadlineMs:    55000,  // سقف مطلق: analyze() لا تتجاوزه أبداً
    fileCheckMs:       8000,   // مهلة فحص صلاحية الملف
    editorCheckMs:     8000,   // مهلة فحص بصمات التعديل
    imageLoadMs:       15000,  // مهلة تحميل/معالجة الصورة
    maxDimension:      1800,   // أقصى بُعد قبل القراءة
    minDimension:      1200,   // نُكبّر الصور الصغيرة لتتضح الأرقام
    sharpDimension:    2400,   // بُعد مرحلة الأرقام (تكبير أكبر)
    amountTolerance:   0.01,   // 1%
    amountMinAbsolute: 2,      // أو 2 جنيه، أيهما أكبر
    minTextForReject:  60,     // أقل من ذلك لا يصح الرفض بحجة "ليست إيصالاً"
    staleReceiptDays:  10      // إشعار أقدم من ذلك → مراجعة يدوية (ليس رفضاً)
  };

  // بصمات برامج التعديل — وجودها في بايتات الملف دليل قوي على التزييف
  const EDITOR_SIGNATURES = [
    'photoshop', 'adobe photoshop', 'adobe illustrator', 'gimp', 'snapseed',
    'picsart', 'lightroom', 'pixlr', 'inkscape', 'canva', 'facetune',
    'remini', 'meitu', 'phonto', 'sketchbook', 'paint.net', 'coreldraw',
    'photoroom', 'lensa', 'airbrush', 'toolwiz', 'photodirector'
  ];

  // ═══════════════════════════════════════════════════════════════════
  // 2) قواميس المزوّدين — عربي + إنجليزي
  // ═══════════════════════════════════════════════════════════════════
  const PROVIDERS = [
    {
      key: 'bankak',
      name: 'بنكك (بنك الخرطوم)',
      brand: ['بنكك', 'bankak', 'bank ak', 'بنك الخرطوم', 'bank of khartoum', 'bokh', 'bok'],
      labels: [
        'تحويلات', 'تحويل', 'رقم العمليه', 'التاريخ و الزمن', 'اسم المرسل اليه',
        'من حساب', 'الى حساب', 'رقم الموبايل', 'المبلغ', 'التعليق',
        'transfers', 'transfer', 'transaction no', 'transaction number',
        'date & time', 'date and time', 'sent to name', 'sender name',
        'from account', 'to account', 'mobile no', 'amount', 'comment'
      ],
      refLen: [9, 16]
    },
    {
      key: 'ocash',
      name: 'أوكاش (بنك أم درمان الوطني)',
      brand: ['اوكاش', 'او كاش', 'o cash', 'o-cash', 'ocash', 'لكل الناس',
              'بنك ام درمان', 'بنك ام درمان الوطني', 'omdurman national bank', 'onb'],
      labels: [
        'تفاصيل الحركه', 'رقم الحركه', 'تاريخ الحركه', 'نوع الحركه', 'قيمه الحركه',
        'اسم العميل', 'رقم الهاتف المحمول', 'التحويل الى حساب مصرفي', 'المبلغ',
        'حركه ناجحه', 'مقدم الخدمه', 'نوع الخدمه', 'رقم السجل', 'اسم المشترك',
        'رقم الحساب', 'الحساب المحلي', 'التحويل الى بنك داخل السودان',
        'transaction details', 'transaction number', 'transaction date',
        'transaction type', 'transaction amount', 'customer name',
        'mobile phone number', 'transfer to bank account', 'amount',
        'service provider', 'service type', 'subscriber name', 'record number',
        'local account', 'successful transaction'
      ],
      refLen: [10, 24]
    },
    {
      key: 'fawry',
      name: 'فوري',
      brand: ['فوري', 'fawry', 'fawri'],
      labels: [
        'الرقم المرجعي', 'اسم المستفيد', 'الى البطاقه رقم', 'من الحساب',
        'اسم البنك', 'المبلغ', 'رقم العمليه', 'رقم الهاتف', 'التاريخ', 'التعليق',
        'ناجح', 'الى الحساب',
        'reference number', 'reference no', 'beneficiary name', 'to card number',
        'from account', 'bank name', 'amount', 'transaction no', 'phone number',
        'date', 'comment', 'successful'
      ],
      refLen: [8, 18]
    },
    {
      key: 'mbok',
      name: 'ماي بنك (بنك الخرطوم)',
      brand: ['mbok', 'my bank', 'ماي بنك', 'mybank'],
      labels: ['رقم العمليه', 'المبلغ', 'من حساب', 'الى حساب',
               'transaction no', 'amount', 'from account', 'to account'],
      refLen: [8, 20]
    },
    {
      key: 'cashi',
      name: 'كاشي',
      brand: ['كاشي', 'cashi', 'cashy'],
      labels: ['رقم العمليه', 'رقم المرجع', 'المبلغ', 'المحفظه',
               'transaction no', 'reference no', 'amount', 'wallet'],
      refLen: [8, 20]
    },
    {
      key: 'faisal',
      name: 'بنك فيصل الإسلامي',
      brand: ['بنك فيصل', 'فيصل الاسلامي', 'faisal islamic', 'faisal bank'],
      labels: ['رقم العمليه', 'المبلغ', 'رقم الحساب',
               'transaction no', 'amount', 'account number'],
      refLen: [8, 20]
    },
    {
      key: 'nilebank',
      name: 'بنك النيل / بنكي',
      brand: ['بنك النيل', 'nile bank', 'بنكي', 'bankee'],
      labels: ['رقم العمليه', 'المبلغ', 'من حساب', 'transaction no', 'amount'],
      refLen: [8, 20]
    },
    {
      key: 'alsalam',
      name: 'بنك السلام',
      brand: ['بنك السلام', 'alsalam bank', 'al salam bank'],
      labels: ['رقم العمليه', 'المبلغ', 'رقم الحساب', 'transaction no', 'amount'],
      refLen: [8, 20]
    }
  ];

  // تسميات حقول عامة في أي إشعار تحويل — عربي وإنجليزي معاً، لأن نفس
  // التطبيق قد يكون مضبوطاً بأي من اللغتين وقت أخذ لقطة الشاشة
  const RECEIPT_FIELD_KEYWORDS = [
    // عربي
    'رقم العمليه', 'رقم الحركه', 'الرقم المرجعي', 'رقم المرجع', 'رقم الايصال',
    'رقم الاشعار', 'رقم التحويل', 'المبلغ', 'مبلغ', 'المبلغ المحول',
    'من حساب', 'من الحساب', 'الى حساب', 'الى الحساب', 'الحساب المحول اليه',
    'اسم المستفيد', 'اسم العميل', 'اسم المرسل', 'المرسل اليه', 'اسم الحساب',
    'تفاصيل الحركه', 'نوع الحركه', 'تاريخ الحركه', 'التاريخ و الزمن',
    'التاريخ', 'الزمن', 'الوقت', 'رقم الموبايل', 'رقم الهاتف', 'اسم البنك',
    'التعليق', 'تعليقات', 'ملاحظات', 'حواله', 'تحويل', 'تحويلات', 'رصيد',
    'ايصال', 'اشعار', 'عمليه', 'محفظه', 'sdg', 'ج س', 'جنيه',
    'مقدم الخدمه', 'نوع الخدمه', 'رقم السجل', 'اسم المشترك', 'الحساب المحلي',
    'حركه', 'حركه ناجحه', 'رقم الحساب', 'الى البطاقه رقم',
    // إنجليزي
    'transaction', 'transactions', 'transfer', 'transfers', 'reference',
    'amount', 'account', 'receipt', 'balance', 'beneficiary', 'sender',
    'recipient', 'sent to', 'paid to', 'from account', 'to account',
    'status', 'date', 'time', 'mobile', 'phone number', 'bank name',
    'remark', 'remarks', 'comment', 'narration', 'description', 'details',
    'wallet', 'voucher', 'fee', 'charge', 'successful', 'succeeded'
  ];

  const SUCCESS_KEYWORDS = [
    'ناجح', 'ناجحه', 'تم بنجاح', 'تمت بنجاح', 'تمت العمليه بنجاح',
    'عمليه ناجحه', 'حركه ناجحه', 'حركة ناجحة', 'تم التحويل بنجاح', 'مقبوله', 'مكتمله', 'تم الدفع',
    'تم بنجاح ارسال', 'تمت العملية',
    'successful', 'success', 'succeeded', 'completed', 'complete', 'approved',
    'transfer successful', 'transaction successful', 'payment successful',
    'done', 'confirmed', 'accepted', 'paid'
  ];

  const FAILURE_KEYWORDS = [
    'فشل', 'فشلت', 'فاشله', 'غير ناجح', 'غير ناجحه', 'لم تكتمل', 'غير مكتمله',
    'مرفوض', 'مرفوضه', 'ملغيه', 'ملغاه', 'تم الالغاء', 'رصيد غير كاف',
    'الرصيد غير كافي', 'العمليه غير مكتمله', 'حدث خطا', 'تم ارجاع المبلغ',
    'معلقه', 'قيد الانتظار',
    'failed', 'failure', 'declined', 'rejected', 'unsuccessful', 'not successful',
    'cancelled', 'canceled', 'reversed', 'refunded', 'insufficient balance',
    'insufficient funds', 'error occurred', 'not completed', 'incomplete',
    'timed out', 'expired'
  ];

  // تسميات "مبلغ العملية" — الأقوى في المطابقة
  const AMOUNT_LABELS = [
    'المبلغ', 'مبلغ', 'المبلغ المحول', 'المبلغ المرسل', 'المبلغ المدفوع',
    'قيمه الحركه', 'قيمه العمليه', 'القيمه', 'قيمه', 'مبلغ التحويل',
    'المبلغ الكلي', 'الاجمالي', 'اجمالي',
    'amount', 'amt', 'transfer amount', 'transaction amount', 'amount paid',
    'amount transferred', 'amount sent', 'total', 'total amount', 'value',
    'paid amount', 'debit amount', 'credit amount', 'sum'
  ];

  // تسميات يجب استثناؤها من مطابقة المبلغ (رصيد/رسوم/ضريبة/حدود)
  const NON_AMOUNT_LABELS = [
    'رصيد', 'الرصيد', 'الرصيد المتاح', 'الرصيد الحالي', 'رصيدك', 'المتبقي',
    'رسوم', 'الرسوم', 'عموله', 'العموله', 'ضريبه', 'الضريبه', 'قيمه مضافه',
    'حد', 'الحد', 'الحد اليومي', 'حد التحويل',
    'balance', 'available balance', 'current balance', 'remaining',
    'fee', 'fees', 'charge', 'charges', 'commission', 'tax', 'vat',
    'limit', 'daily limit', 'stamp'
  ];

  const REF_LABELS = [
    'رقم العمليه', 'رقم العملية', 'رقم الحركه', 'الرقم المرجعي', 'رقم المرجع',
    'رقم الايصال', 'رقم الاشعار', 'رقم التحويل', 'رقم المعامله', 'المرجع',
    'transaction no', 'transaction number', 'transaction id', 'transaction ref',
    'reference number', 'reference no', 'reference id', 'reference',
    'trans no', 'trx no', 'txn no', 'txn id', 'receipt no', 'voucher no',
    'operation no', 'op no', 'ref no', 'ref'
  ];

  // ═══════════════════════════════════════════════════════════════════
  // 3) أدوات نصية (عربي/إنجليزي)
  // ═══════════════════════════════════════════════════════════════════
  function latinizeDigits(str) {
    return String(str == null ? '' : str)
      .replace(/[\u0660-\u0669]/g, d => String(d.charCodeAt(0) - 0x0660))
      .replace(/[\u06F0-\u06F9]/g, d => String(d.charCodeAt(0) - 0x06F0));
  }

  // تطبيع عام: يوحّد الهمزات والياء والتاء المربوطة، يزيل التشكيل،
  // ويحوّل الفواصل العربية (٬ ٫) والرموز إلى ما يقابلها لاتينياً
  function normalizeText(str) {
    return latinizeDigits(str)
      .toLowerCase()
      .replace(/[\u064B-\u0652\u0640]/g, '')     // تشكيل + تطويل
      .replace(/[أإآٱ]/g, 'ا')
      .replace(/[ىئي]/g, 'ي')
      .replace(/ة/g, 'ه')
      .replace(/ؤ/g, 'و')
      .replace(/\u066C/g, ',')                   // فاصلة الآلاف العر��ية
      .replace(/\u066B/g, '.')                   // الفاصلة العشرية العربية
      .replace(/[\u060C;؛]/g, ' ')
      .replace(/[|_\u200f\u200e\u202a-\u202e]/g, ' ')
      .replace(/[ \t\u00a0]+/g, ' ')
      .trim();
  }

  // تطبيع رقم العملية — نفس منطق normalize_tx_ref في قاعدة البيانات
  function normalizeRef(str) {
    if (!str) return '';
    return latinizeDigits(str).toUpperCase().replace(/[^A-Z0-9]/g, '');
  }

  function digitsOnly(str) {
    return latinizeDigits(String(str == null ? '' : str)).replace(/\D/g, '');
  }

  // تصحيح أخطاء OCR داخل السلاسل الرقمية: يُطبَّق فقط إذا كان الرمز
  // غالبيته أرقام، حتى لا نُفسد كلمات حقيقية
  const DIGIT_CONFUSIONS = {
    o: '0', O: '0', d: '0', D: '0', q: '9', Q: '0', '°': '0', 'ه': '0',
    i: '1', I: '1', l: '1', L: '1', '!': '1', '|': '1', ']': '1', '[': '1',
    z: '2', Z: '2', s: '5', S: '5', b: '6', G: '6', g: '9',
    t: '7', T: '7', B: '8', '&': '8', a: '4', A: '4', e: '8', '€': '8'
  };

  function fixOcrDigits(token) {
    const t = String(token || '');
    if (!t) return '';
    const digits = (t.match(/\d/g) || []).length;
    const letters = (t.match(/[a-z]/gi) || []).length;
    if (!digits || digits < letters) return t; // ليست سلسلة رقمية
    let out = '';
    for (const ch of t) out += (DIGIT_CONFUSIONS[ch] !== undefined ? DIGIT_CONFUSIONS[ch] : ch);
    return out;
  }

  function countKeywordHits(text, list) {
    let hits = 0;
    const found = [];
    for (const kw of list) {
      if (kw && text.includes(kw)) { hits++; found.push(kw); }
    }
    return { hits, found };
  }

  function hasAny(text, list) {
    for (const kw of list) if (kw && text.includes(kw)) return true;
    return false;
  }

  // مسافة ليفنشتاين (لسلاسل قصيرة) — لمقارنة أرقام العمليات
  function levenshtein(a, b) {
    a = String(a); b = String(b);
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    if (Math.abs(a.length - b.length) > 4) return 99;
    let prev = new Array(b.length + 1);
    for (let j = 0; j <= b.length; j++) prev[j] = j;
    for (let i = 1; i <= a.length; i++) {
      const cur = [i];
      for (let j = 1; j <= b.length; j++) {
        cur[j] = Math.min(
          prev[j] + 1,
          cur[j - 1] + 1,
          prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1)
        );
      }
      prev = cur;
    }
    return prev[b.length];
  }

  // كشف لغة الإشعار (للتقرير فقط)
  function detectLanguage(text) {
    const ar = (text.match(/[\u0600-\u06FF]/g) || []).length;
    const en = (text.match(/[a-z]/gi) || []).length;
    if (ar >= 8 && en >= 8) return 'mixed';
    if (ar > en) return 'ar';
    if (en > ar) return 'en';
    return 'unknown';
  }

  // ═══════════════════════════════════════════════════════════════════
  // 4) فحص بصمات التعديل داخل الملف
  // ═══════════════════════════════════════════════════════════════════
  async function detectImageEditing(file) {
    try {
      const head = await file.slice(0, 128 * 1024).arrayBuffer();
      const tail = await file.slice(Math.max(0, file.size - 48 * 1024)).arrayBuffer();
      const decoder = new TextDecoder('latin1');
      const blob = (decoder.decode(head) + ' ' + decoder.decode(tail)).toLowerCase();
      for (const sig of EDITOR_SIGNATURES) {
        if (blob.includes(sig)) return sig;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 5) معالجة الصورة — ثلاث صيغ مختلفة تُستخدم في مراحل القراءة
  // ═══════════════════════════════════════════════════════════════════
  function loadImage(file) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      const url = URL.createObjectURL(file);
      let settled = false;
      const cleanup = () => { try { URL.revokeObjectURL(url); } catch (e) {} };
      const timer = setTimeout(() => {
        if (settled) return;
        settled = true; cleanup();
        reject(new Error('image_load_timeout'));
      }, CONFIG.imageLoadMs);
      img.onload = () => {
        if (settled) return;
        settled = true; clearTimeout(timer); cleanup(); resolve(img);
      };
      img.onerror = () => {
        if (settled) return;
        settled = true; clearTimeout(timer); cleanup();
        reject(new Error('image_load_failed'));
      };
      img.src = url;
    });
  }

  function drawScaled(img, targetLongest, minLongest) {
    let w = img.naturalWidth, h = img.naturalHeight;
    if (!w || !h) throw new Error('image_load_failed');

    const longest = Math.max(w, h);
    let scale = 1;
    if (longest > targetLongest) scale = targetLongest / longest;
    else if (minLongest && longest < minLongest) scale = Math.min(3, minLongest / longest);

    const cw = Math.max(1, Math.round(w * scale));
    const ch = Math.max(1, Math.round(h * scale));

    const canvas = document.createElement('canvas');
    canvas.width = cw; canvas.height = ch;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, cw, ch);
    return { canvas, ctx, cw, ch };
  }

  // تدرّج رمادي + متوسط الإضاءة
  function toGray(px) {
    let sum = 0;
    for (let i = 0; i < px.length; i += 4) {
      const g = (px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114) | 0;
      px[i] = px[i + 1] = px[i + 2] = g;
      sum += g;
    }
    return sum / (px.length / 4);
  }

  // شدّ التباين على المدى الفعلي
  function contrastStretch(px) {
    let min = 255, max = 0;
    for (let i = 0; i < px.length; i += 4) {
      const g = px[i];
      if (g < min) min = g;
      if (g > max) max = g;
    }
    const range = Math.max(1, max - min);
    if (range >= 235) return;
    for (let i = 0; i < px.length; i += 4) {
      let v = ((px[i] - min) * 255 / range) | 0;
      v = v < 0 ? 0 : (v > 255 ? 255 : v);
      px[i] = px[i + 1] = px[i + 2] = v;
    }
  }

  // عتبة Otsu التلقائية
  function otsuThreshold(px) {
    const hist = new Array(256).fill(0);
    const total = px.length / 4;
    for (let i = 0; i < px.length; i += 4) hist[px[i]]++;
    let sum = 0;
    for (let t = 0; t < 256; t++) sum += t * hist[t];
    let sumB = 0, wB = 0, maxVar = -1, threshold = 128;
    for (let t = 0; t < 256; t++) {
      wB += hist[t];
      if (!wB) continue;
      const wF = total - wB;
      if (!wF) break;
      sumB += t * hist[t];
      const mB = sumB / wB;
      const mF = (sum - sumB) / wF;
      const between = wB * wF * (mB - mF) * (mB - mF);
      if (between > maxVar) { maxVar = between; threshold = t; }
    }
    return threshold;
  }

  // نواة تحديد الحواف (Unsharp خفيف)
  function sharpen(ctx, cw, ch) {
    try {
      const src = ctx.getImageData(0, 0, cw, ch);
      const s = src.data;
      const out = ctx.createImageData(cw, ch);
      const o = out.data;
      const k = [0, -1, 0, -1, 5, -1, 0, -1, 0];
      for (let y = 0; y < ch; y++) {
        for (let x = 0; x < cw; x++) {
          let acc = 0, ki = 0;
          for (let dy = -1; dy <= 1; dy++) {
            for (let dx = -1; dx <= 1; dx++, ki++) {
              const yy = Math.min(ch - 1, Math.max(0, y + dy));
              const xx = Math.min(cw - 1, Math.max(0, x + dx));
              acc += s[(yy * cw + xx) * 4] * k[ki];
            }
          }
          const v = acc < 0 ? 0 : (acc > 255 ? 255 : acc);
          const idx = (y * cw + x) * 4;
          o[idx] = o[idx + 1] = o[idx + 2] = v;
          o[idx + 3] = 255;
        }
      }
      ctx.putImageData(out, 0, 0);
    } catch (e) { /* تجاهل */ }
  }

  /**
   * variant:
   *  'enhanced' → رمادي + شد تباين (الافتراضي، الأسرع والأدق عموماً)
   *  'binary'   → رمادي + Otsu ثنائي + عكس تلقائي لصور الوضع الليلي
   *  'sharp'    → تكبير أعلى + رمادي + شد تباين + تحديد حواف (لأرقام صغيرة)
   */
  async function preprocess(file, variant, cachedImg) {
    const img = cachedImg || await loadImage(file);
    const target = variant === 'sharp' ? CONFIG.sharpDimension : CONFIG.maxDimension;
    const minDim = variant === 'sharp' ? CONFIG.sharpDimension : CONFIG.minDimension;
    const { canvas, ctx, cw, ch } = drawScaled(img, target, minDim);

    try {
      const data = ctx.getImageData(0, 0, cw, ch);
      const px = data.data;
      const mean = toGray(px);

      if (variant === 'binary') {
        const dark = mean < 115;                 // خلفية داكنة (وضع ليلي)
        const th = otsuThreshold(px);
        for (let i = 0; i < px.length; i += 4) {
          let v = px[i] > th ? 255 : 0;
          if (dark) v = 255 - v;                 // اعكس ليصبح نصاً أسود على أبيض
          px[i] = px[i + 1] = px[i + 2] = v;
        }
        ctx.putImageData(data, 0, 0);
      } else {
        if (mean < 115) {                        // اعكس الوضع الليلي أولاً
          for (let i = 0; i < px.length; i += 4) {
            const v = 255 - px[i];
            px[i] = px[i + 1] = px[i + 2] = v;
          }
        }
        contrastStretch(px);
        ctx.putImageData(data, 0, 0);
        if (variant === 'sharp') sharpen(ctx, cw, ch);
      }
    } catch (e) {
      // getImageData قد يفشل (canvas ملوّث) — نكمل بالصورة كما هي
    }

    return { image: canvas.toDataURL('image/png'), img };
  }

  // ═══════════════════════════════════════════════════════════════════
  // 6) محرك OCR — يُنشأ مرة واحدة ويُعاد استخدامه لكل المراحل
  // ═══════════════════════════════════════════════════════════════════
  let currentProgressHandler = null;   // نسبة تقدّم القراءة
  let currentEngineHandler = null;     // نسبة تقدّم تجهيز المحرك (تحميل النواة/اللغة)
  let workerPromise = null;            // لا يُخزَّن إلا بعد نجاح التجهيز فعلياً

  /**
   * سبب المشكلة الجذري كان هنا: كل انتظار في هذا الملف كان بلا مهلة، فإذا
   * تعطّل تحميل نواة Tesseract أو بيانات اللغة من الشبكة، بقي الـ await
   * معلّقاً للأبد ولم تصل الواجهة إلى نتيجة. الآن لا يوجد await واحد بلا مهلة.
   */
  function withTimeout(promise, ms, tag) {
    let timer = null;
    return Promise.race([
      Promise.resolve(promise),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('timeout:' + (tag || ''))), ms);
      })
    ]).then(
      (v) => { clearTimeout(timer); return v; },
      (e) => { clearTimeout(timer); throw e; }
    );
  }

  // إنهاء محرك تخلّينا عنه بعد المهلة (حتى لا يستهلك الذاكرة عندما يكتمل لاحقاً)
  function abandon(workerLike) {
    if (!workerLike || typeof workerLike.then !== 'function') return;
    workerLike.then(
      (w) => { try { if (w && w.terminate) w.terminate(); } catch (e) {} },
      () => {}
    );
  }

  function resetEngine(worker) {
    workerPromise = null;
    if (worker) { try { worker.terminate(); } catch (e) {} }
  }

  function engineLogger(m) {
    if (!m) return;
    if (m.status === 'recognizing text') {
      if (currentProgressHandler) currentProgressHandler(Math.round((m.progress || 0) * 100));
      return;
    }
    if (currentEngineHandler) {
      currentEngineHandler(Math.round((m.progress || 0) * 100), String(m.status || ''));
    }
  }

  /**
   * تحميل مكتبة Tesseract نفسها إن لم تكن موجودة (وسم <script> فشل، أو
   * الشبكة حجبت الـ CDN). نجرّب أكثر من مصدر، ولكل واحد مهلة صريحة.
   */
  const TESSERACT_SOURCES = [
    'https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js',
    'https://unpkg.com/tesseract.js@5/dist/tesseract.min.js'
  ];
  let tesseractLoader = null;

  function loadScriptOnce(src, ms) {
    return new Promise((resolve, reject) => {
      const el = document.createElement('script');
      let settled = false;
      const finish = (ok, err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        ok ? resolve() : reject(err || new Error('script_failed'));
      };
      const timer = setTimeout(() => finish(false, new Error('timeout:script')), ms);
      el.src = src;
      el.async = true;
      el.onload = () => finish(true);
      el.onerror = () => finish(false, new Error('script_error'));
      document.head.appendChild(el);
    });
  }

  async function ensureTesseract() {
    if (typeof Tesseract !== 'undefined' && Tesseract && Tesseract.createWorker) return;
    if (tesseractLoader) return tesseractLoader;

    tesseractLoader = (async () => {
      let lastError = null;
      for (const src of TESSERACT_SOURCES) {
        try {
          await loadScriptOnce(src, 9000);
          if (typeof Tesseract !== 'undefined' && Tesseract && Tesseract.createWorker) return;
          lastError = new Error('library_missing_after_load');
        } catch (e) {
          lastError = e;
        }
      }
      throw lastError || new Error('tesseract_unavailable');
    })();

    try {
      await tesseractLoader;
    } catch (e) {
      tesseractLoader = null;   // نسمح بإعادة المحاولة لاحقاً
      throw e;
    }
  }

  /**
   * تجهيز المحرك بمهلة صريحة وبتدرّج:
   *   1) ara+eng (أفضل قراءة للتسميات العربية)
   *   2) eng فقط (أصغر وأسرع — يكفي للأرقام)
   * أي فشل/مهلة لا يُخزَّن في الكاش، فتنجح المحاولة التالية بمحرك نظيف.
   */
  async function getWorker() {
    if (workerPromise) {
      try {
        const cached = await withTimeout(workerPromise, 5000, 'engine_cache');
        if (cached && !cached.__dead) return cached;
        resetEngine(cached);
      } catch (e) {
        workerPromise = null;
      }
    }

    await ensureTesseract();

    const attempts = [
      { langs: 'ara+eng', ms: CONFIG.engineTimeoutMs },
      { langs: 'eng', ms: CONFIG.engineFallbackMs }
    ];

    let lastError = null;
    for (const attempt of attempts) {
      let raw = null;
      try {
        raw = Tesseract.createWorker(attempt.langs, 1, {
          logger: engineLogger,
          errorHandler: () => {}
        });
      } catch (e) {
        lastError = e;
        continue;
      }

      try {
        const worker = await withTimeout(raw, attempt.ms, 'engine');
        if (!worker || typeof worker.recognize !== 'function') throw new Error('engine_invalid');
        worker.__langs = attempt.langs;
        worker.__arabicUnavailable = attempt.langs.indexOf('ara') === -1;
        worker.__dead = false;
        workerPromise = Promise.resolve(worker);
        return worker;
      } catch (e) {
        lastError = e;
        abandon(raw);           // المحاولة المعلّقة تُترك وتُنهى عند اكتمالها
        workerPromise = null;
      }
    }

    throw lastError || new Error('engine_unavailable');
  }

  async function setParams(worker, params) {
    try { await withTimeout(worker.setParameters(params), 10000, 'set_params'); }
    catch (e) { /* تجاهل — لا نوقف الفحص بسبب ضبط معاملات */ }
  }

  function recognizeWithTimeout(worker, image, ms) {
    return new Promise((resolve) => {
      let settled = false;
      let timer = null;
      const done = (val) => {
        if (settled) return;
        settled = true;
        if (timer) clearTimeout(timer);
        resolve(val);
      };
      timer = setTimeout(() => done({ timedOut: true, fatal: true }), Math.max(3000, ms));
      let p;
      try {
        p = worker.recognize(image);
      } catch (e) {
        done({ timedOut: true, fatal: true });
        return;
      }
      Promise.resolve(p).then(
        (res) => done({ res, timedOut: false }),
        () => done({ timedOut: true, fatal: false })
      );
    });
  }

  async function runPass(worker, image, psm, whitelist, onProgress, ms) {
    await setParams(worker, {
      tessedit_pageseg_mode: String(psm),
      tessedit_char_whitelist: whitelist || '',
      preserve_interword_spaces: '1'
    });
    currentProgressHandler = onProgress || null;
    const outcome = await recognizeWithTimeout(worker, image, ms || CONFIG.passTimeoutMs);
    currentProgressHandler = null;

    if (outcome.timedOut) {
      return { text: '', confidence: null, timedOut: true, fatal: !!outcome.fatal };
    }
    const raw = outcome.res && outcome.res.data ? (outcome.res.data.text || '') : '';
    const conf = outcome.res && outcome.res.data && typeof outcome.res.data.confidence === 'number'
      ? outcome.res.data.confidence : null;
    return { text: raw, confidence: conf, timedOut: false, fatal: false };
  }

  // ═══════════════════════════════════════════════════════════════════
  // 7) تحديد المزوّد
  // ═══════════════════════════════════════════════════════════════════
  function detectProvider(text) {
    let best = null;
    for (const p of PROVIDERS) {
      const brand = countKeywordHits(text, p.brand.map(normalizeText));
      const labels = countKeywordHits(text, p.labels.map(normalizeText));
      const score = brand.hits * 3 + labels.hits;
      if (score > 0 && (!best || score > best.score)) {
        best = { key: p.key, name: p.name, score, refLen: p.refLen, brandHits: brand.hits };
      }
    }
    return best;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 8) تحليل الأسطر واستخراج الحقول
  // ═══════════════════════════════════════════════════════════════════
  function toLines(rawText) {
    return String(rawText || '')
      .split(/\r?\n/)
      .map(l => normalizeText(l))
      .filter(l => l.length > 0);
  }

  // تفسير رقم مالي بأي صيغة: 52,332 | 52332.00 | 52.332,00 | 52 332
  function parseAmountToken(token) {
    let s = latinizeDigits(String(token || '')).replace(/[^\d.,\s]/g, '').trim();
    if (!s) return null;
    s = s.replace(/\s+/g, '');            // 52 332 → 52332
    if (!/\d/.test(s)) return null;

    const lastComma = s.lastIndexOf(',');
    const lastDot = s.lastIndexOf('.');
    const lastSep = Math.max(lastComma, lastDot);

    if (lastSep === -1) {
      const n = parseFloat(s);
      return isNaN(n) ? null : n;
    }

    const tailLen = s.length - lastSep - 1;
    const sepChar = s[lastSep];
    const sepCount = (s.match(new RegExp('\\' + sepChar, 'g')) || []).length;

    // الفاصل الأخير فاصلة عشرية فقط إذا تبعه رقم أو رقمان وكان وحيداً من نوعه
    const isDecimal = (tailLen === 1 || tailLen === 2) && sepCount === 1;

    let intPart, fracPart = '';
    if (isDecimal) {
      intPart = s.slice(0, lastSep).replace(/[.,]/g, '');
      fracPart = s.slice(lastSep + 1);
    } else {
      intPart = s.replace(/[.,]/g, '');
    }
    const n = parseFloat(intPart + (fracPart ? '.' + fracPart : ''));
    return isNaN(n) ? null : n;
  }

  const NUM_TOKEN_RE = /\d[\d.,\s]{0,18}\d|\d/g;

  function labelHitAt(line, labels) {
    for (const l of labels) {
      const idx = line.indexOf(l);
      if (idx !== -1) return { label: l, index: idx };
    }
    return null;
  }

  const DATE_LINE_RE =
    /\d{1,2}\s*[-/.]\s*\d{1,2}\s*[-/.]\s*\d{2,4}|\d{4}\s*[-/.]\s*\d{1,2}\s*[-/.]\s*\d{1,2}|\d{1,2}:\d{2}|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)|(?:يناير|فبراير|مارس|ابريل|مايو|يونيو|يوليو|اغسطس|سبتمبر|اكتوبر|نوفمبر|ديسمبر)/;

  const CURRENCY_RE = /(sdg|جنيه|ج س|ج\.س|جنية|sd|egp|usd|sar|aed)/;

  /**
   * استخراج مرشحات المبالغ من الأسطر مع أوزان:
   *  10 → بجانب تسمية "المبلغ/amount" في نفس السطر
   *   9 → التسمية في سطر والقيمة في السطر التالي
   *   8 → مصحوبة بعملة (SDG / ج.س)
   *   5 → صيغة مالية (فاصلة آلاف أو كسر عشري)
   *   1 → رقم صحيح معقول (احتياطي)
   * والمبالغ الملحقة بتسميات الرصيد/الرسوم تُعلَّم isExcluded حتى لا تُستخدم
   * في قرار الرفض.
   */
  // أسطر لا تحتوي مبلغاً إطلاقاً: أرقام حسابات/بطاقات/هواتف/سجلات
  const IDENTIFIER_LINE_LABELS = [
    'من حساب', 'من الحساب', 'الى حساب', 'الى الحساب', 'رقم الحساب',
    'الحساب المحلي', 'الى البطاقه رقم', 'رقم البطاقه', 'رقم السجل',
    'رقم الموبايل', 'رقم الهاتف', 'رقم الجوال', 'المحفظه',
    'from account', 'to account', 'account number', 'account no',
    'card number', 'to card number', 'record number', 'mobile no',
    'mobile number', 'phone number', 'wallet'
  ];

  function extractAmounts(lines) {
    const amountLabels = AMOUNT_LABELS.map(normalizeText);
    const excludeLabels = NON_AMOUNT_LABELS.map(normalizeText);
    const identifierLabels = IDENTIFIER_LINE_LABELS.map(normalizeText);
    const out = [];

    const push = (value, weight, opts) => {
      if (value === null || !isFinite(value) || value <= 0) return;
      if (value > 1e12) return;
      out.push(Object.assign({ value, weight }, opts || {}));
    };

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const next = lines[i + 1] || '';
      const isDateLine = DATE_LINE_RE.test(line);
      const labelHit = labelHitAt(line, amountLabels);
      const excluded = !!labelHitAt(line, excludeLabels);
      const hasCurrency = CURRENCY_RE.test(line);

      // سطر رقم حساب/بطاقة/هاتف لا يُستخرَج منه مبلغ (إلا لو فيه تسمية "المبلغ" فعلاً)
      const isIdentifierLine = !labelHit && !!labelHitAt(line, identifierLabels);
      if (isIdentifierLine) continue;

      const tokens = line.match(NUM_TOKEN_RE) || [];
      for (const tok of tokens) {
        const value = parseAmountToken(tok);
        if (value === null) continue;
        const clean = tok.replace(/\s/g, '');
        const rawDigits = digitsOnly(clean);

        // تجاهل ما يشبه أرقام الحسابات/العمليات/الهواتف (أرقام طويلة بلا فواصل)
        const looksLikeId = rawDigits.length >= 9 && !/[.,]/.test(clean);
        const formatted = /[.,]/.test(clean);

        if (labelHit) {
          push(value, 10, { excluded, line: i, source: 'label', formatted });
        } else if (hasCurrency) {
          push(value, 8, { excluded, line: i, source: 'currency', formatted });
        } else if (formatted && !isDateLine) {
          push(value, 5, { excluded, line: i, source: 'money', formatted });
        } else if (!isDateLine && !looksLikeId && rawDigits.length >= 3 && rawDigits.length <= 9 && value >= 50) {
          push(value, 1, { excluded, line: i, source: 'plain', formatted });
        }
      }

      // التسمية في سطر والقيمة في السطر التالي (تخطيط شائع في الإشعارات)
      if (labelHit && !(line.match(NUM_TOKEN_RE) || []).length) {
        const nextTokens = next.match(NUM_TOKEN_RE) || [];
        for (const tok of nextTokens) {
          const value = parseAmountToken(tok);
          push(value, 9, {
            excluded: !!labelHitAt(next, excludeLabels),
            line: i + 1, source: 'label_next', formatted: /[.,]/.test(tok)
          });
        }
      }
    }

    // إزالة التكرار مع الاحتفاظ بأعلى وزن
    out.sort((a, b) => b.weight - a.weight);
    const seen = new Map();
    for (const c of out) {
      const key = c.value.toFixed(2);
      if (!seen.has(key)) seen.set(key, c);
      else if (seen.get(key).excluded && !c.excluded) seen.set(key, c);
    }
    return Array.from(seen.values()).slice(0, 60);
  }

  /**
   * استخراج مرشحات رقم العملية:
   *  10 → بجانب تسمية "رقم العملية/transaction no" (نفس السطر أو التالي)
   *   8 → رمز مختلط مثل FT2507191234
   *   4 → أي سلسلة أرقام طويلة
   */
  function extractTxRef(lines, joinedText, provider) {
    const refLabels = REF_LABELS.map(normalizeText);
    const candidates = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const hit = labelHitAt(line, refLabels);
      if (!hit) continue;

      const after = line.slice(hit.index + hit.label.length);
      const inline = after.match(/[a-z0-9][a-z0-9\-/]{4,28}/g) || [];
      for (const tok of inline) {
        const fixed = fixOcrDigits(tok);
        if (digitsOnly(fixed).length >= 6) candidates.push({ value: fixed, weight: 10, labelled: true });
      }
      if (!inline.length) {
        const next = lines[i + 1] || '';
        const nx = next.match(/[a-z0-9][a-z0-9\-/]{4,28}/g) || [];
        for (const tok of nx) {
          const fixed = fixOcrDigits(tok);
          if (digitsOnly(fixed).length >= 6) candidates.push({ value: fixed, weight: 9, labelled: true });
        }
      }
    }

    // رموز مختلطة معروفة
    const mixed = joinedText.match(/\b(?:ft|tr|trx|txn|rf|ref|bok)[a-z0-9]{6,22}\b/g) || [];
    for (const r of mixed) candidates.push({ value: r.toUpperCase(), weight: 8, labelled: false });

    // أي سلسلة أرقام طويلة
    const runs = joinedText.match(/\d{8,26}/g) || [];
    for (const r of runs) candidates.push({ value: r, weight: 4, labelled: false });

    if (!candidates.length) return { value: null, labelledValue: null, all: [] };

    if (provider && provider.refLen) {
      const [lo, hi] = provider.refLen;
      for (const c of candidates) {
        const len = digitsOnly(c.value).length;
        if (len >= lo && len <= hi) c.weight += 5;
      }
    }

    candidates.sort((a, b) =>
      (b.weight - a.weight) || (digitsOnly(b.value).length - digitsOnly(a.value).length));

    const labelled = candidates.filter(c => c.labelled);
    return {
      value: candidates[0].value,
      labelledValue: labelled.length ? labelled[0].value : null,
      labelledAll: labelled.map(c => c.value),
      all: [...new Set(candidates.map(c => c.value))].slice(0, 15)
    };
  }

  const MONTHS_EN = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  const MONTHS_AR = ['يناير', 'فبراير', 'مارس', 'ابريل', 'مايو', 'يونيو', 'يوليو',
                     'اغسطس', 'سبتمبر', 'اكتوبر', 'نوفمبر', 'ديسمبر'];

  function extractDateTime(text) {
    // ترتيب مهم: صيغة السنة أولاً (2026-03-14) قبل صيغة اليوم أولاً (14-03-2026)،
    // وإلا اقتُطع "26-03-14" من "2026-03-14" وفُهم أنه عام 2014 → إشعار "قديم" زائف.
    const patterns = [
      new RegExp('(\\d{1,2}[-/\\s](?:' + MONTHS_EN.join('|') + ')[a-z]*[-/\\s]\\d{2,4}(?:\\s+\\d{1,2}:\\d{2}(?::\\d{2})?(?:\\s*(?:am|pm))?)?)'),
      new RegExp('(\\d{1,2}\\s*(?:' + MONTHS_AR.join('|') + ')\\s*\\d{2,4}(?:\\s+\\d{1,2}:\\d{2}(?::\\d{2})?)?)'),
      /(?:^|[^\d])(\d{4}[/.-]\d{1,2}[/.-]\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)/,
      /(?:^|[^\d])(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*(?:am|pm))?)?)/,
      /(\d{1,2}:\d{2}:\d{2}\s+\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})/
    ];
    for (const re of patterns) {
      const m = text.match(re);
      if (m) return m[1].trim();
    }
    return null;
  }

  // محاولة تحويل التاريخ المقروء إلى Date (لكشف الإشعارات القديمة)
  function parseReceiptDate(str) {
    if (!str) return null;
    const s = latinizeDigits(str).toLowerCase();
    let m = s.match(/(\d{1,2})[-/\s]([a-z]{3})[a-z]*[-/\s](\d{2,4})/);
    if (m) {
      const mi = MONTHS_EN.indexOf(m[2]);
      if (mi >= 0) {
        let y = parseInt(m[3], 10);
        if (y < 100) y += 2000;
        const d = new Date(y, mi, parseInt(m[1], 10));
        return isNaN(d.getTime()) ? null : d;
      }
    }
    m = s.match(/(?:^|[^\d])(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})(?![\d])/);
    if (m) {
      const d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
      if (!isNaN(d.getTime())) return d;
    }
    m = s.match(/(?:^|[^\d])(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})(?![\d])/);
    if (m) {
      let y = parseInt(m[3], 10);
      if (y < 100) y += 2000;
      const a = parseInt(m[1], 10), b = parseInt(m[2], 10);
      // نفترض dd/mm إن كان الأول > 12
      const day = a > 12 ? a : (b > 12 ? b : a);
      const mon = a > 12 ? b : (b > 12 ? a : b);
      const d = new Date(y, mon - 1, day);
      return isNaN(d.getTime()) ? null : d;
    }
    m = s.match(/(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})/);
    if (m) {
      const d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
      return isNaN(d.getTime()) ? null : d;
    }
    return null;
  }

  function extractAccounts(text) {
    const from = text.match(/(?:من\s*حساب|من\s*الحساب|from\s*account|source\s*account|debit\s*account)[^0-9]{0,18}([0-9\s-]{6,32})/);
    const to = text.match(/(?:الى\s*حساب|الى\s*الحساب|الحساب\s*المحول\s*اليه|الى\s*البطاقه\s*رقم|to\s*account|beneficiary\s*account|credit\s*account|destination\s*account)[^0-9]{0,18}([0-9\s-]{6,32})/);
    const phone = text.match(/\b(249\d{9}|0\d{9})\b/);
    return {
      from: from ? digitsOnly(from[1]) : null,
      to: to ? digitsOnly(to[1]) : null,
      phone: phone ? phone[1] : null
    };
  }

  // ��══════════════════════════════════════════════════════════════════
  // 9) المطابقة
  // ═══════════════════════════════════════════════════════════════════
  function amountVariants(target) {
    // صيغ رقمية محتملة للمبلغ المطلوب داخل نص مقروء آلياً
    const t = Math.round(target);
    const set = new Set([String(t), String(t) + '00', String(t) + '0']);
    if (target % 1 !== 0) set.add(String(target.toFixed(2)).replace('.', ''));
    return Array.from(set);
  }

  function matchAmount(candidates, expected, flatDigits, digitRuns) {
    if (!expected || expected <= 0) {
      return { matched: false, value: null, checked: false, best: null, labelledMismatch: false };
    }

    const target = Math.round(expected);
    const tol = Math.max(target * CONFIG.amountTolerance, CONFIG.amountMinAbsolute);
    const targetDigits = String(target);

    // (أ) مطابقة مباشرة بالتفاوت المسموح
    for (const c of candidates) {
      if (Math.abs(c.value - target) <= tol) {
        return { matched: true, value: c.value, checked: true, via: 'value', labelledMismatch: false };
      }
    }

    // (ب) مطابقة على مستوى سلسلة الأرقام (OCR فقد الفاصلة أو الكسور)
    for (const c of candidates) {
      const cd = digitsOnly(c.value.toString());
      if (!cd) continue;
      if (cd === targetDigits) {
        return { matched: true, value: target, checked: true, via: 'digits', labelledMismatch: false };
      }
      // 52,332.00 قُرئ 5233200 → إزالة أصفار الكسور
      if (cd.length > targetDigits.length && cd.startsWith(targetDigits)) {
        const rest = cd.slice(targetDigits.length);
        if (/^0{1,2}$/.test(rest)) {
          return { matched: true, value: target, checked: true, via: 'trailing_zeros', labelledMismatch: false };
        }
      }
      // 5233200 مقسوماً على 100 يساوي المطلوب
      // (التفاوت يُقاس دائماً بالنسبة إلى المبلغ المطلوب — لا يُضخَّم بـ ×100،
      //  وإلا صار أي رقم تقريباً "مطابقاً")
      if (Math.abs(c.value / 100 - target) <= tol || Math.abs(c.value * 100 - target) <= tol) {
        return { matched: true, value: target, checked: true, via: 'scale', labelledMismatch: false };
      }
    }

    // (ج) وجود سلسلة أرقام المبلغ في النص الكامل — مع احترام حدود الأرقام
    //     حتى لا يُعتبر ظهور "5233" داخل رقم حساب طويل مطابقةً للمبلغ.
    //     ومن 5 خانات فأكثر فقط: تطابق 4 خانات وارد جداً بالمصادفة داخل
    //     مجموعات أرقام الحسابات (0033 0913 5108 0001).
    if (targetDigits.length >= 5) {
      const runs = Array.isArray(digitRuns) && digitRuns.length ? digitRuns : null;
      for (const v of amountVariants(target)) {
        const seen = runs
          ? runs.some(run => run === v || (run.length <= v.length + 2 && run.indexOf(v) !== -1))
          : flatDigits.includes(v);
        if (seen) {
          return { matched: true, value: target, checked: true, via: 'flat', labelledMismatch: false };
        }
      }
    }

    // (د) تسامح مع خطأ خانة واحدة في المبلغ (خصوصاً المبالغ الكبيرة)
    //     شرط إضافي مهم: الفرق العددي الناتج يجب أن يكون صغيراً (≤ 10%)،
    //     وإلا فإن 20,000 مقابل 50,000 (خانة واحدة مختلفة!) ستُعدّ مطابقة خطأً.
    if (targetDigits.length >= 5) {
      for (const c of candidates) {
        const cd = digitsOnly(c.value.toString());
        if (cd.length !== targetDigits.length) continue;
        if (levenshtein(cd, targetDigits) > 1) continue;
        const relative = Math.abs(c.value - target) / target;
        if (relative <= 0.1) {
          return { matched: true, value: c.value, checked: true, via: 'fuzzy', fuzzy: true, labelledMismatch: false };
        }
      }
    }

    // لا مطابقة — نرجع أفضل مرشح موسوم غير مستثنى (لأجل قرار الرفض)
    const labelled = candidates.filter(c => c.weight >= 8 && !c.excluded);
    const best = labelled.length ? labelled[0] : (candidates.length ? candidates[0] : null);

    return {
      matched: false,
      checked: true,
      value: best ? best.value : null,
      best,
      labelledMismatch: labelled.length > 0
    };
  }

  function matchRef(manualRef, refInfo, joinedText) {
    const manual = normalizeRef(manualRef);
    if (!manual) return { matched: false, conflict: false, checked: false };

    const flatAll = normalizeRef(joinedText);
    const flatDigits = digitsOnly(joinedText);
    const manualDigits = digitsOnly(manualRef);

    // (أ) الرقم كما كتبه المستخدم موجود حرفياً في نص الصورة
    if (manual.length >= 6 && flatAll.includes(manual)) {
      return { matched: true, conflict: false, checked: true };
    }
    if (manualDigits.length >= 6 && flatDigits.includes(manualDigits)) {
      return { matched: true, conflict: false, checked: true };
    }

    // (ب) بعد تصحيح لبس الأرقام في النص كاملاً
    const fixedFlat = digitsOnly(fixOcrDigits(flatAll));
    if (manualDigits.length >= 6 && fixedFlat.includes(manualDigits)) {
      return { matched: true, conflict: false, checked: true, fuzzy: true };
    }

    // (ج) تسامح مع خطأ خانة أو خانتين من OCR
    const all = (refInfo && refInfo.all) ? refInfo.all : [];
    if (manualDigits.length >= 8) {
      const maxDist = manualDigits.length >= 12 ? 2 : 1;
      for (const cand of all) {
        const cd = digitsOnly(cand);
        if (!cd) continue;
        if (Math.abs(cd.length - manualDigits.length) <= 1 && levenshtein(cd, manualDigits) <= maxDist) {
          return { matched: true, conflict: false, checked: true, fuzzy: true };
        }
      }
      // جزء من الرقم (بداية/نهاية) موجود — قص أو خانة ناقصة
      const head = manualDigits.slice(0, -1);
      const tail = manualDigits.slice(1);
      if (flatDigits.includes(head) || flatDigits.includes(tail)) {
        return { matched: true, conflict: false, checked: true, fuzzy: true };
      }
    }

    // (د) تعارض: الصورة فيها رقم عملية **موسوم بحقله** ويخالف المكتوب تماماً
    const labelled = (refInfo && refInfo.labelledAll) ? refInfo.labelledAll : [];
    for (const cand of labelled) {
      const cd = digitsOnly(cand);
      if (cd.length < 6) continue;
      const dist = levenshtein(cd, manualDigits);
      const closeLength = Math.abs(cd.length - manualDigits.length) <= 1;
      if (closeLength && dist <= 2) continue;   // لبس قراءة، ليس تعارضاً
      return { matched: false, conflict: true, checked: true, ocrRef: cd };
    }

    return { matched: false, conflict: false, checked: true };
  }

  // ═══════════════════════════════════════════════════════════════════
  // 10) بناء السياق من النصوص المقروءة + محرك القرار
  // ═══════════════════════════════════════════════════════════════════
  function buildContext(texts, options) {
    const joined = texts.map(t => normalizeText(t)).join(' \n ');
    const lines = toLines(texts.join('\n'));
    const flatDigits = digitsOnly(joined);
    const provider = detectProvider(joined);
    const fieldHits = countKeywordHits(joined, RECEIPT_FIELD_KEYWORDS.map(normalizeText));
    const refInfo = extractTxRef(lines, joined, provider);
    const amountList = extractAmounts(lines);
    const digitRuns = latinizeDigits(joined).match(/\d+/g) || [];
    const refMatch = matchRef(options.manualRef, refInfo, joined);
    const amtMatch = matchAmount(amountList, options.expectedAmount, flatDigits, digitRuns);
    return { joined, lines, flatDigits, digitRuns, provider, fieldHits, refInfo, amountList, refMatch, amtMatch };
  }

  const EMPTY_CONTEXT = {
    joined: '', lines: [], flatDigits: '', provider: null,
    fieldHits: { hits: 0, found: [] },
    refInfo: { value: null, labelledValue: null, labelledAll: [], all: [] },
    amountList: [],
    refMatch: { matched: false, conflict: false, checked: false },
    amtMatch: { matched: false, checked: false, value: null, best: null, labelledMismatch: false }
  };

  /**
   * محرك القرار: يطبّق التصنيف ثم الاستخراج ثم المطابقة على سياق جاهز.
   * الرفض هنا لا يحدث إلا بيقين عالٍ؛ وأي شك يذهب إلى المراجعة اليدوية.
   */
  function judge(ctx, options, result) {
    const expectedAmount = Number(options.expectedAmount) || 0;
    const manualRef = options.manualRef || '';
    const expectedAccount = digitsOnly(options.expectedAccount || '');
    const { joined, provider, fieldHits, refInfo, amountList, refMatch, amtMatch, flatDigits } = ctx;

    result.textLength = joined.length;
    result.language = detectLanguage(joined);

    // ── التصنيف: هل هذه صورة إشعار تحويل؟ ──
    const looksLikeReceipt =
      (provider && provider.score >= 2) ||
      fieldHits.hits >= 2 ||
      refMatch.matched ||
      amtMatch.matched ||
      (refInfo.labelledValue && amountList.length > 0);

    if (!looksLikeReceipt) {
      if (joined.length >= CONFIG.minTextForReject && fieldHits.hits === 0 && !provider) {
        // النص واضح وطويل ولا يحتوي أي مفردة من إشعارات التحويل بأي من
        // اللغتين → الصورة فعلاً ليست إيصالاً
        result.decision = 'reject';
        result.ocrStatus = 'rejected';
        result.riskFlags.push('not_a_receipt');
        result.message = 'الصورة المرفوعة ليست إشعار تحويل بنكي أو محفظة. ارفع صورة إشعار التحويل من التطبيق (بنكك / أوكاش / فوري / كاشي) كاملة وواضحة.';
        return result;
      }
      // قراءة ضعيفة → مراجعة يدوية (لا نطرد عميلاً حقيقياً)
      result.decision = 'review';
      result.ocrStatus = 'needs_review';
      result.riskFlags.push('low_ocr_confidence');
      result.message = 'تعذّر قراءة بعض بيانات الإيصال بوضوح. تم استلام طلبك وسيُراجع يدوياً من الإدارة — لنتيجة فورية جرّب رفع لقطة شاشة (سكرين شوت) للإشعار مباشرة من التطبيق.';
      return result;
    }

    if (provider) {
      result.provider = provider.key;
      result.providerName = provider.name;
    }

    // ── تعبئة المستخرجات ──
    const accounts = extractAccounts(joined);
    result.extracted.txRef = refInfo.labelledValue || refInfo.value;
    result.extracted.txRefCandidates = refInfo.all;
    result.extracted.amountCandidates = amountList.slice(0, 12).map(a => a.value);
    result.extracted.dateTime = extractDateTime(joined);
    result.extracted.fromAccount = accounts.from;
    result.extracted.toAccount = accounts.to;
    result.extracted.phone = accounts.phone;

    // ── حالة العملية (عربي/إنجليزي) ──
    const failHits = countKeywordHits(joined, FAILURE_KEYWORDS.map(normalizeText));

    // نحذف عبارات الفشل من النص قبل عدّ كلمات النجاح، وإلا فإن
    // "غير مكتملة" ستُحسب نجاحاً لأنها تحتوي كلمة "مكتملة".
    let successScope = joined;
    for (const phrase of failHits.found) {
      successScope = successScope.split(phrase).join(' ');
    }
    const okHits = countKeywordHits(successScope, SUCCESS_KEYWORDS.map(normalizeText));
    result.extracted.statusOk = failHits.hits > 0 ? false : (okHits.hits > 0 ? true : null);

    if (failHits.hits > 0 && okHits.hits === 0) {
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('failed_transaction:' + failHits.found[0]);
      result.message = 'الإيصال يوضح أن عملية التحويل لم تنجح (' + failHits.found[0] + '). أكمل التحويل بنجاح ثم ارفع الإشعار الجديد.';
      return result;
    }

    result.refVerified = !!refMatch.matched;
    result.amountVerified = !!amtMatch.matched;
    result.extracted.amount = amtMatch.matched
      ? (amtMatch.value !== null ? amtMatch.value : Math.round(expectedAmount))
      : (amtMatch.value !== null ? amtMatch.value : null);

    // ── تعارض رقم العملية (مصدره حقل موسوم) → رفض ──
    if (refMatch.conflict) {
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('ref_conflict');
      result.message = `رقم العملية الذي كتبته (${normalizeRef(manualRef)}) لا يطابق الرقم الموجود في صورة الإيصال (${refMatch.ocrRef}). صحّح رقم العملية بالضغط على "تعديل" أو ارفع صورة الإشعار الصحيح.`;
      return result;
    }

    // ── المبلغ لا يطابق إجمالي الطلب ──
    if (amtMatch.checked && !amtMatch.matched) {
      const best = amtMatch.best;
      const target = Math.round(expectedAmount);

      // ثقة عالية في قراءة المبلغ: قيمة موسومة بحقل "المبلغ/amount" أو بعملة،
      // وليست رصيداً أو رسوماً، والقراءة العامة للإيصال معقولة
      const readableReceipt = (provider && provider.score >= 2) || fieldHits.hits >= 3;
      const highConfidence = !!best && best.weight >= 8 && !best.excluded && readableReceipt;

      // فرق ناتج عن صيغة/كسور فقط (×10 ×100 ÷100) لا يُعتبر تلاعباً
      const ratio = best && best.value ? best.value / target : 0;
      const formattingArtifact = !!best && (
        Math.abs(ratio - 100) < 0.02 || Math.abs(ratio - 0.01) < 0.0002 ||
        Math.abs(ratio - 10) < 0.02 || Math.abs(ratio - 0.1) < 0.002 ||
        Math.abs(ratio - 1000) < 0.2 || Math.abs(ratio - 0.001) < 0.00002
      );

      if (highConfidence && !formattingArtifact) {
        const shortfall = target - best.value;
        result.decision = 'reject';
        result.ocrStatus = 'rejected';
        result.riskFlags.push('amount_mismatch');
        result.message =
          `المبلغ في إشعار التحويل (${Math.round(best.value).toLocaleString('en-US')} ج.س) لا يطابق إجمالي الطلب المطلوب ` +
          `(${target.toLocaleString('en-US')} ج.س)` +
          (shortfall > 0
            ? `. ناقص ${Math.round(shortfall).toLocaleString('en-US')} ج.س — حوّل المبلغ كاملاً ثم ارفع الإشعار الجديد.`
            : `. تأكد من رفع إشعار التحويل الخاص بهذا الطلب بالمبلغ المطلوب بالضبط.`);
        return result;
      }
      result.riskFlags.push('amount_unverified');
    }

    // ── إشارات إضافية (لا تُسبب رفضاً — للمراجعة والتقرير) ──
    if (!refMatch.matched) result.riskFlags.push('ref_unverified');
    if (refMatch.fuzzy) result.riskFlags.push('ref_fuzzy_match');
    if (amtMatch.fuzzy) result.riskFlags.push('amount_fuzzy_match');
    if (!provider) result.riskFlags.push('provider_unknown');

    if (expectedAccount && expectedAccount.length >= 6) {
      const acctSeen = flatDigits.includes(expectedAccount) ||
                       (accounts.to && (accounts.to.includes(expectedAccount) || expectedAccount.includes(accounts.to)));
      if (!acctSeen) result.riskFlags.push('destination_account_unverified');
    }

    const recDate = parseReceiptDate(result.extracted.dateTime);
    if (recDate) {
      const ageDays = (Date.now() - recDate.getTime()) / 86400000;
      if (ageDays > CONFIG.staleReceiptDays) result.riskFlags.push('stale_receipt');
      if (ageDays < -1) result.riskFlags.push('future_dated_receipt');
    }

    const needsManual = result.riskFlags.includes('stale_receipt') ||
                        result.riskFlags.includes('future_dated_receipt');

    if (result.refVerified && result.amountVerified && !needsManual) {
      result.decision = 'accept';
      result.ocrStatus = 'passed';
      result.message = `تم التحقق من الإيصال بنجاح${result.providerName ? ' (' + result.providerName + ')' : ''}: رقم العملية والمبلغ مطابقان.`;
    } else {
      result.decision = 'review';
      result.ocrStatus = 'needs_review';
      if (needsManual) {
        result.message = 'تاريخ الإشعار غير متوافق مع وقت الطلب، لذلك سيُراجع طلبك يدوياً من الإدارة.';
      } else if (result.amountVerified && !result.refVerified) {
        result.message = 'المبلغ مطابق تماماً، لكن لم نتمكن من ��أكيد رقم العملية من الصورة. تم استلام طلبك وسيُراجع يدوياً من الإدارة.';
      } else if (result.refVerified && !result.amountVerified) {
        result.message = 'رقم العملية مطابق، لكن لم نتمكن من قراءة المبلغ بدقة من الصورة. تم استلام طلبك وسيُراجع يدوياً من الإدارة.';
      } else {
        result.message = 'تم استلام الإيصال. بعض البيانات لم تُقرأ بدقة، لذلك سيُراجع طلبك يدوياً من الإدارة.';
      }
    }

    return result;
  }

  function blankResult() {
    return {
      version: 3,
      decision: 'review',
      ocrStatus: 'needs_review',
      message: '',
      provider: null,
      providerName: null,
      confidence: null,
      language: null,
      passes: 0,
      riskFlags: [],
      textLength: 0,
      extracted: {
        txRef: null, txRefCandidates: [], amount: null, amountCandidates: [],
        dateTime: null, fromAccount: null, toAccount: null, phone: null,
        statusOk: null
      },
      amountVerified: false,
      refVerified: false
    };
  }

  /**
   * محاكاة القرار على نص جاهز (بلا صورة) — للاختبار والتشخيص من الكونسول:
   *   ReceiptIntel.simulate(textFromReceipt, { expectedAmount, manualRef })
   */
  function simulate(text, opts) {
    const options = opts || {};
    return judge(buildContext([String(text || '')], {
      expectedAmount: Number(options.expectedAmount) || 0,
      manualRef: options.manualRef || ''
    }), options, blankResult());
  }

  // ═══════════════════════════════════════════════════════════════════
  // 11) الواجهة العامة: analyze()
  // ═══════════════════════════════════════════════════════════════════
  /**
   * @param {File} file
   * @param {Object} opts { expectedAmount, manualRef, expectedAccount, onStatus }
   * @returns {Promise<Object>}
   */
  async function analyze(file, opts) {
    const options = opts || {};
    const onStatus = typeof options.onStatus === 'function' ? options.onStatus : null;
    const expectedAmount = Number(options.expectedAmount) || 0;
    const manualRef = options.manualRef || '';
    const expectedAccount = digitsOnly(options.expectedAccount || '');
    const startedAt = Date.now();
    const say = (t) => { if (onStatus) { try { onStatus(t); } catch (e) {} } };
    const remaining = () => CONFIG.totalBudgetMs - (Date.now() - startedAt);

    const result = blankResult();

    // ── المرحلة 0: صلاحية الملف ──
    if (typeof validateReceiptImage === 'function') {
      let basic = { valid: true };
      try {
        basic = await withTimeout(
          Promise.resolve(validateReceiptImage(file)), CONFIG.fileCheckMs, 'file_check'
        );
      } catch (e) {
        basic = { valid: true };   // تعذّر الفحص السريع → نكمل، ولا نوقف العميل
        result.riskFlags.push('file_check_timeout');
      }
      if (basic && !basic.valid) {
        result.decision = 'reject';
        result.ocrStatus = 'rejected';
        result.message = basic.message;
        result.riskFlags.push('invalid_file');
        return result;
      }
      // صالح لكن تعذّر فك ترميزه/أبعاده صغيرة ⇒ مراجعة يدوية فوراً (Fail-Closed)
      // لا نُشغّل OCR على ملف لا يستطيع المتصفح فك ترميزه أصلاً.
      if (basic && basic.needsManualReview) {
        result.decision = 'review';
        result.ocrStatus = 'needs_review';
        result.message = basic.message ||
          'تعذّر معاينة الصورة في هذا المتصفح. تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب.';
        result.riskFlags.push('file_decode_' + (basic.reason || 'unknown'));
        return result;
      }
    }

    // ── المرحلة 1: بصمات التعديل ──
    say('جارِ التحقق من أصالة الصورة...');
    let editor = null;
    try {
      editor = await withTimeout(detectImageEditing(file), CONFIG.editorCheckMs, 'editor_check');
    } catch (e) {
      editor = null;
      result.riskFlags.push('editor_check_timeout');
    }
    if (editor) {
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('edited_image:' + editor);
      result.message = 'الصورة تبدو معدّلة ببرنامج تحرير صور. أرفق صورة الإشعار الأصلية كما ظهرت في تطبيق البنك بدون أي تعديل.';
      return result;
    }

    // ── محرك القراءة متاح؟ ──
    if (typeof Tesseract === 'undefined') {
      result.decision = 'review';
      result.message = 'تم استلام الإيصال وسيُراجع يدوياً من الإدارة.';
      result.riskFlags.push('ocr_unavailable');
      return result;
    }

    say('جارِ تجهيز محرك القراءة...');
    let worker;
    currentEngineHandler = (pct, status) => {
      const label = (status || '').indexOf('language') !== -1
        ? 'تحميل بيانات اللغة'
        : 'تجهيز محرك القراءة';
      say(`${label}... ${Math.min(99, Math.max(0, pct))}%`);
    };
    try {
      worker = await getWorker();
    } catch (e) {
      currentEngineHandler = null;
      result.decision = 'review';
      result.ocrStatus = 'needs_review';
      result.message = 'تعذّر تشغيل محرك الفحص الآلي (غالباً بسبب الاتصال بالإنترنت). تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.';
      result.riskFlags.push(
        String(e && e.message || '').indexOf('timeout') === 0 ? 'ocr_engine_timeout' : 'ocr_engine_failed'
      );
      return result;
    }
    currentEngineHandler = null;
    if (worker.__arabicUnavailable) result.riskFlags.push('arabic_model_unavailable');

    // ── مراحل القراءة المتعددة ──
    const PASSES = [
      { variant: 'enhanced', psm: 6,  whitelist: '', label: 'قراءة أولية' },
      { variant: 'binary',   psm: 4,  whitelist: '', label: 'قراءة معززة' },
      { variant: 'sharp',    psm: 11, whitelist: '0123456789.,:/-', label: 'قراءة الأرقام' }
    ];

    let cachedImg = null;
    const texts = [];
    let bestConfidence = null;
    let timedOutAll = true;

    // سياق العمل يُعاد بناؤه بعد كل مرحلة قراءة
    let ctx = EMPTY_CONTEXT;
    const judgeOptions = { expectedAmount, manualRef, expectedAccount };

    let engineDead = false;

    for (let i = 0; i < PASSES.length; i++) {
      const pass = PASSES[i];

      // لا نبدأ مرحلة جديدة إذا لم يبقَ وقت كافٍ في الميزانية الكلية
      if (i > 0 && remaining() < 8000) break;

      let image;
      try {
        const pre = await withTimeout(
          preprocess(file, pass.variant, cachedImg), CONFIG.imageLoadMs + 5000, 'preprocess'
        );
        image = pre.image;
        cachedImg = pre.img;
      } catch (e) {
        if (i === 0) image = file; else continue;
      }

      say(`${pass.label} — جارِ قراءة الإيصال...`);
      const passMs = Math.min(CONFIG.passTimeoutMs, Math.max(6000, remaining()));
      const out = await runPass(worker, image, pass.psm, pass.whitelist,
        (p) => say(`${pass.label} — ${p}%`), passMs);

      if (!out.timedOut) {
        timedOutAll = false;
        result.passes++;
        if (out.text && out.text.trim()) texts.push(out.text);
        if (out.confidence !== null && (bestConfidence === null || out.confidence > bestConfidence)) {
          bestConfidence = out.confidence;
        }
      } else if (out.fatal) {
        // المحرك لم يرد إطلاقاً → لا معنى لمراحل إضافية عليه، ونتخلّص منه
        engineDead = true;
        worker.__dead = true;
        resetEngine(worker);
        result.riskFlags.push('ocr_pass_timeout');
        break;
      }

      ctx = buildContext(texts, judgeOptions);

      // شروط التوقف المبكر: عندنا ما يكفي للحكم
      const refDone = !manualRef || ctx.refMatch.matched || ctx.refMatch.conflict;
      const amtDone = !expectedAmount || ctx.amtMatch.matched;
      if (refDone && amtDone && ctx.joined.length >= 40) break;
    }

    // إعادة ضبط الفلاتر لأي استخدام لاحق للمحرك
    if (!engineDead) await setParams(worker, { tessedit_char_whitelist: '' });

    result.confidence = bestConfidence;
    result.textLength = ctx.joined.length;
    result.language = detectLanguage(ctx.joined);

    // كل المراحل انتهت بمهلة (اتصال/جهاز بطيء) → مراجعة يدوية، لا رفض
    if (timedOutAll || !texts.length) {
      result.decision = 'review';
      result.ocrStatus = 'needs_review';
      result.riskFlags.push(timedOutAll ? 'ocr_timeout' : 'ocr_empty');
      result.message = 'تعذّر إكمال الفحص الآلي للصورة (غالباً بسبب بطء الاتصال أو الجهاز). تم استلام إيصالك وسيُراجع يدوياً من الإدارة.';
      return result;
    }

    say('جارِ تحليل بيانات الإيصال...');
    return judge(ctx, judgeOptions, result);

  }

  // ═══════════════════════════════════════════════════════════════════
  // 11.b) ضمان نهائي: analyze() لا تبقى معلّقة أبداً
  // ═══════════════════════════════════════════════════════════════════
  function softReview(flag, message) {
    const r = blankResult();
    r.decision = 'review';
    r.ocrStatus = 'needs_review';
    r.riskFlags.push(flag);
    r.message = message;
    return r;
  }

  /**
   * الواجهة العامة الفعلية: تُرجع نتيجة دائماً — نجاح أو رفض أو مراجعة —
   * وخلال CONFIG.hardDeadlineMs كحدٍّ أقصى مطلق، مهما تعطّل أي شيء بالداخل.
   */
  function analyzeSafe(file, opts) {
    const options = opts || {};
    let watchdog = null;
    let finished = false;

    const guard = new Promise((resolve) => {
      watchdog = setTimeout(() => {
        if (finished) return;
        // المحرك على الأغلب معلّق — نتخلّى عنه ليُبنى نظيفاً في المحاولة القادمة
        const stale = workerPromise;
        workerPromise = null;
        currentProgressHandler = null;
        currentEngineHandler = null;
        abandon(stale);
        resolve(softReview(
          'scan_watchdog_timeout',
          'استغرق الفحص الآلي وقتاً أطول من المسموح، لذلك أُوقف تلقائياً. تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.'
        ));
      }, CONFIG.hardDeadlineMs);
    });

    const run = (async () => {
      try {
        return await analyze(file, options);
      } catch (err) {
        try { console.warn('[RAIZEY] receipt analyze error:', err); } catch (e) {}
        currentProgressHandler = null;
        currentEngineHandler = null;
        return softReview(
          'scan_error',
          'تعذّر إكمال الفحص الآلي للصورة. تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.'
        );
      }
    })();

    return Promise.race([run, guard]).then((res) => {
      finished = true;
      if (watchdog) clearTimeout(watchdog);
      return res && typeof res === 'object'
        ? res
        : softReview('scan_error', 'تعذّر إكمال الفحص الآلي للصورة. تم استلام إيصالك وسيُراجع يدوياً من الإدارة.');
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // 12) تصدير
  // ═══════════════════════════════════════════════════════════════════
  window.ReceiptIntel = {
    VERSION: 3,
    analyze: analyzeSafe,
    analyzeRaw: analyze,
    simulate,
    buildContext,
    judge,
    matchAmount,
    matchRef,
    detectLanguage,
    normalizeRef,
    normalizeText,
    digitsOnly,
    detectProvider,
    parseAmountToken,
    extractAmounts,
    extractTxRef,
    toLines,
    CONFIG,
    PROVIDERS
  };
})();
