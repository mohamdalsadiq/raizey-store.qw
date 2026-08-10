/* =========================================================================
 * RAIZEY STORE — محرك الفحص الذكي لإيصالات التحويل  (Receipt Intelligence)
 * =========================================================================
 * مسار الملف: assets/js/receipt-intel.js
 *
 * يعمل بالكامل في المتصفح (بلا سيرفر) ويعتمد على Tesseract.js.
 * يجب تحميل tesseract.min.js قبل هذا الملف.
 *
 * ── ترتيب مراحل الفحص (كل مرحلة تستطيع الرفض فوراً) ──
 *   0) فحص الملف   : النوع، الحجم، صورة حقيقية قابلة للفتح
 *   1) فحص التلاعب : بصمات برامج التعديل داخل بايتات الملف
 *   2) تحسين الصورة: تدرج رمادي + شد تباين + تحجيم — يرفع دقة القراءة
 *      على صور واتساب المضغوطة والسكرين شوت المقصوص
 *   3) قراءة OCR   : ara+eng ثم eng كخطة بديلة
 *   4) التصنيف     : هل هذه فعلاً صورة إشعار تحويل بنكي/محفظة؟
 *      (لو صورة عشوائية/سيلفي/منتج → ترفض فوراً ولا تدخل مرحلة الاستخراج)
 *   5) الاستخراج   : رقم العملية، المبلغ، التاريخ والوقت، الحسابات، الحالة
 *   6) القرار      : accept / review / reject
 *
 * ── الفلسفة: صارم ضد التلاعب، متسامح مع جودة الصورة ──
 *   • لا نرفض عميلاً حقيقياً بسبب صورة مضغوطة أو OCR ضعيف → تُحوَّل للمراجعة
 *   • نرفض بلا تهاون: صورة ليست إيصالاً، عملية فاشلة، رقم عملية مخالف لما
 *     كتبه المستخدم، مبلغ لا يطابق الطلب، صورة معدّلة ببرنامج تحرير
 *   • التكرار (نفس رقم العملية / نفس الصورة) يُرفض في قاعدة البيانات ذرّياً
 *     عبر claim_payment_receipt — لأن أي فحص في المتصفح قابل للتجاوز
 * ========================================================================= */

(function () {
  'use strict';

  // ───────────────────────────────────────────────────────────────────
  // 1. إعدادات المحرك
  // ───────────────────────────────────────────────────────────────────
  const CONFIG = {
    ocrTimeoutMs:      28000,   // مهلة كل محاولة قراءة
    maxDimension:      1600,    // أقصى بُعد قبل القراءة (يوازن الدقة والسرعة)
    minDimension:      1000,    // نُكبّر الصور الصغيرة لتتضح الأرقام
    amountTolerance:   0.01,    // 1%
    amountMinAbsolute: 2,       // أو 2 جنيه، أيهما أكبر
    minTextForReject:  25       // أقل من ذلك = OCR فشل، لا نرفض بسببه
  };

  // بصمات برامج التعديل — وجودها في بايتات الملف دليل قوي على التزييف
  const EDITOR_SIGNATURES = [
    'photoshop', 'adobe', 'gimp', 'snapseed', 'picsart', 'lightroom',
    'pixlr', 'inkscape', 'canva', 'facetune', 'afterphoto', 'remini',
    'meitu', 'phonto', 'sketchbook', 'paint.net', 'coreldraw'
  ];

  // ───────────────────────────────────────────────────────────────────
  // 2. أنماط البنوك والمحافظ السودانية
  // ───────────────────────────────────────────────────────────────────
  // brand   : كلمات العلامة التجارية (وزن عالي)
  // labels  : تسميات الحقول الخاصة بالمزوّد (وزن متوسط)
  const PROVIDERS = [
    {
      key: 'bankak',
      name: 'بنكك (بنك الخرطوم)',
      brand:  ['بنكك', 'bankak', 'بنك الخرطوم', 'bank of khartoum', 'bok'],
      labels: ['تحويلات', 'رقم العمليه', 'التاريخ و الزمن', 'اسم المرسل اليه',
               'من حساب', 'الى حساب', 'رقم الموبايل'],
      refLen: [9, 14]
    },
    {
      key: 'ocash',
      name: 'أوكاش (بنك أم درمان الوطني)',
      brand:  ['اوكاش', 'او كاش', 'o-cash', 'ocash', 'لكل الناس',
               'بنك ام درمان', 'omdurman national bank', 'onb'],
      labels: ['تفاصيل الحركه', 'رقم الحركه', 'تاريخ الحركه', 'نوع الحركه',
               'اسم العميل', 'رقم الهاتف المحمول', 'التحويل الى حساب مصرفي'],
      refLen: [12, 22]
    },
    {
      key: 'fawry',
      name: 'فوري',
      brand:  ['فوري', 'fawry'],
      labels: ['الرقم المرجعي', 'اسم المستفيد', 'الى البطاقه رقم',
               'من الحساب', 'اسم البنك'],
      refLen: [8, 16]
    },
    {
      key: 'mbok',
      name: 'ماي بنك / بنك الخرطوم',
      brand:  ['mbok', 'my bank', 'ماي بنك'],
      labels: ['رقم العمليه', 'المبلغ', 'من حساب'],
      refLen: [8, 20]
    },
    {
      key: 'cashi',
      name: 'كاشي',
      brand:  ['كاشي', 'cashi'],
      labels: ['رقم العمليه', 'رقم المرجع', 'المبلغ'],
      refLen: [8, 20]
    },
    {
      key: 'faisal',
      name: 'بنك فيصل الإسلامي',
      brand:  ['بنك فيصل', 'faisal islamic'],
      labels: ['رقم العمليه', 'المبلغ', 'رقم الحساب'],
      refLen: [8, 20]
    }
  ];

  // تسميات حقول عامة موجودة في أي إشعار تحويل تقريباً
  const RECEIPT_FIELD_KEYWORDS = [
    'رقم العمليه', 'رقم الحركه', 'الرقم المرجعي', 'رقم المرجع', 'رقم الايصال',
    'المبلغ', 'مبلغ', 'من حساب', 'من الحساب', 'الى حساب', 'الى الحساب',
    'اسم المستفيد', 'اسم العميل', 'اسم المرسل', 'المرسل اليه',
    'تفاصيل الحركه', 'نوع الحركه', 'تاريخ الحركه', 'التاريخ و الزمن',
    'رقم الموبايل', 'رقم الهاتف', 'اسم البنك', 'التعليق', 'تعليقات',
    'حواله', 'تحويل', 'رصيد', 'sdg',
    'transaction', 'reference', 'amount', 'account', 'transfer',
    'receipt', 'balance', 'beneficiary', 'successful'
  ];

  const SUCCESS_KEYWORDS = [
    'ناجح', 'ناجحه', 'تم بنجاح', 'تمت بنجاح', 'تمت العمليه بنجاح',
    'عمليه ناجحه', 'مقبوله', 'successful', 'success', 'completed', 'approved'
  ];

  const FAILURE_KEYWORDS = [
    'فشل', 'فشلت', 'غير ناجح', 'غير ناجحه', 'لم تكتمل', 'غير مكتمله',
    'مرفوض', 'مرفوضه', 'ملغيه', 'ملغاه', 'رصيد غير كاف',
    'failed', 'failure', 'declined', 'rejected', 'unsuccessful', 'cancelled'
  ];

  // ───────────────────────────────────────────────────────────────────
  // 3. أدوات نصية
  // ───────────────────────────────────────────────────────────────────
  // تحويل الأرقام العربية/الفارسية إلى لاتينية
  function latinizeDigits(str) {
    return String(str)
      .replace(/[\u0660-\u0669]/g, d => String(d.charCodeAt(0) - 0x0660))
      .replace(/[\u06F0-\u06F9]/g, d => String(d.charCodeAt(0) - 0x06F0));
  }

  // تطبيع النص العربي: توحيد الهمزات والياء والتاء المربوطة + إزالة التشكيل
  function normalizeText(str) {
    return latinizeDigits(str)
      .toLowerCase()
      .replace(/[\u064B-\u0652\u0640]/g, '')   // تشكيل + تطويل
      .replace(/[أإآٱ]/g, 'ا')
      .replace(/[ىئي]/g, 'ي')
      .replace(/ة/g, 'ه')
      .replace(/ؤ/g, 'و')
      .replace(/[|_]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // تطبيع رقم العملية — نفس منطق normalize_tx_ref في قاعدة البيانات
  function normalizeRef(str) {
    if (!str) return '';
    return latinizeDigits(str).toUpperCase().replace(/[^A-Z0-9]/g, '');
  }

  function digitsOnly(str) {
    return latinizeDigits(String(str || '')).replace(/\D/g, '');
  }

  function countKeywordHits(text, list) {
    let hits = 0;
    const found = [];
    for (const kw of list) {
      if (text.includes(kw)) { hits++; found.push(kw); }
    }
    return { hits, found };
  }

  // ───────────────────────────────────────────────────────────────────
  // 4. فحص بصمات التعديل داخل الملف
  // ───────────────────────────────────────────────────────────────────
  async function detectImageEditing(file) {
    try {
      // البصمات (EXIF / XMP / تعليقات JPEG) تقع في أول وآخر الملف
      const head = await file.slice(0, 96 * 1024).arrayBuffer();
      const tail = await file.slice(Math.max(0, file.size - 32 * 1024)).arrayBuffer();
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

  // ───────────────────────────────────────────────────────────────────
  // 5. تحسين الصورة قبل القراءة
  // ───────────────────────────────────────────────────────────────────
  function loadImage(file) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      const url = URL.createObjectURL(file);
      img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('image_load_failed')); };
      img.src = url;
    });
  }

  async function preprocess(file) {
    const img = await loadImage(file);
    let { naturalWidth: w, naturalHeight: h } = img;
    if (!w || !h) throw new Error('image_load_failed');

    // تحجيم: نكبّر الصغير ونصغّر الكبير — الاثنان يضران بدقة القراءة
    const longest = Math.max(w, h);
    let scale = 1;
    if (longest > CONFIG.maxDimension) scale = CONFIG.maxDimension / longest;
    else if (longest < CONFIG.minDimension) scale = Math.min(2, CONFIG.minDimension / longest);

    const cw = Math.round(w * scale);
    const ch = Math.round(h * scale);

    const canvas = document.createElement('canvas');
    canvas.width = cw;
    canvas.height = ch;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, cw, ch);

    // تدرّج رمادي + شد تباين تلقائي (contrast stretch على المدى الفعلي)
    try {
      const data = ctx.getImageData(0, 0, cw, ch);
      const px = data.data;
      let min = 255, max = 0;

      for (let i = 0; i < px.length; i += 4) {
        const g = (px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114) | 0;
        px[i] = px[i + 1] = px[i + 2] = g;
        if (g < min) min = g;
        if (g > max) max = g;
      }

      const range = Math.max(1, max - min);
      if (range < 235) {
        for (let i = 0; i < px.length; i += 4) {
          const v = ((px[i] - min) * 255 / range) | 0;
          const c = v < 0 ? 0 : (v > 255 ? 255 : v);
          px[i] = px[i + 1] = px[i + 2] = c;
        }
      }
      ctx.putImageData(data, 0, 0);
    } catch (e) {
      // لو فشل getImageData (canvas ملوّث) نكمل بالصورة كما هي
    }

    return canvas.toDataURL('image/png');
  }

  // ───────────────────────────────────────────────────────────────────
  // 6. تشغيل OCR مع مهلة
  // ───────────────────────────────────────────────────────────────────
  function recognizeWithTimeout(image, langs, onProgress) {
    return new Promise((resolve) => {
      let settled = false;
      const done = (val) => { if (!settled) { settled = true; resolve(val); } };
      const timer = setTimeout(() => done(null), CONFIG.ocrTimeoutMs);

      Tesseract.recognize(image, langs, {
        logger: (m) => {
          if (onProgress && m && m.status === 'recognizing text') {
            onProgress(Math.round((m.progress || 0) * 100));
          }
        }
      })
        .then((res) => { clearTimeout(timer); done(res); })
        .catch(() => { clearTimeout(timer); done(null); });
    });
  }

  async function runOcr(file, onStatus) {
    let image;
    try {
      image = await preprocess(file);
    } catch (e) {
      image = file; // نمرّر الملف كما هو لو فشل التحسين
    }

    // المحاولة الأولى: عربي + إنجليزي (تسميات الحقول عربية)
    if (onStatus) onStatus('جارِ قراءة الإيصال...');
    let res = await recognizeWithTimeout(image, 'ara+eng',
      (p) => onStatus && onStatus(`جارِ قراءة الإيصال... ${p}%`));

    let text = res && res.data ? (res.data.text || '') : '';

    // خطة بديلة: إنجليزي فقط (أسرع وأخف، يكفي للأرقام)
    if (normalizeText(text).length < CONFIG.minTextForReject) {
      if (onStatus) onStatus('جارِ إعادة القراءة بدقة أعلى...');
      const res2 = await recognizeWithTimeout(image, 'eng', null);
      if (res2 && res2.data && (res2.data.text || '').length > text.length) {
        res = res2;
        text = res2.data.text || '';
      }
    }

    return {
      raw: text,
      text: normalizeText(text),
      confidence: res && res.data && typeof res.data.confidence === 'number'
        ? res.data.confidence : null
    };
  }

  // ───────────────────────────────────────────────────────────────────
  // 7. تحديد المزوّد
  // ───────────────────────────────────────────────────────────────────
  function detectProvider(text) {
    let best = null;

    for (const p of PROVIDERS) {
      const brand  = countKeywordHits(text, p.brand.map(normalizeText));
      const labels = countKeywordHits(text, p.labels.map(normalizeText));
      const score  = brand.hits * 3 + labels.hits;

      if (score > 0 && (!best || score > best.score)) {
        best = { key: p.key, name: p.name, score, refLen: p.refLen, brandHits: brand.hits };
      }
    }
    return best;
  }

  // ───────────────────────────────────────────────────────────────────
  // 8. استخراج الحقول
  // ───────────────────────────────────────────────────────────────────
  const REF_LABEL_PATTERN =
    '(?:رقم\\s*العمليه|رقم\\s*الحركه|الرقم\\s*المرجعي|رقم\\s*المرجع|رقم\\s*الايصال' +
    '|transaction\\s*(?:id|no|number|ref)?|reference\\s*(?:id|no|number)?|txn|trx|ref)';

  function extractTxRef(text, provider) {
    const candidates = [];

    // (أ) بجانب تسمية الحقل — الأقوى
    const labelled = new RegExp(REF_LABEL_PATTERN + '[^0-9a-z]{0,25}([0-9]{6,25})', 'g');
    let m;
    while ((m = labelled.exec(text)) !== null) {
      candidates.push({ value: m[1], weight: 10 });
    }

    // (ب) أي سلسلة أرقام طويلة (استبعاد ما يشبه التاريخ أو المبلغ)
    const runs = text.match(/\d{8,25}/g) || [];
    for (const r of runs) candidates.push({ value: r, weight: 4 });

    // (ج) أرقام مختلطة بحروف مثل FT2507191234
    const mixed = text.match(/\b(?:ft|tr|trx|txn|rf)[a-z0-9]{6,22}\b/g) || [];
    for (const r of mixed) candidates.push({ value: r.toUpperCase(), weight: 8 });

    if (!candidates.length) return { value: null, all: [] };

    // ترجيح إضافي: الطول المتوقّع لهذا المزوّد
    if (provider && provider.refLen) {
      const [lo, hi] = provider.refLen;
      for (const c of candidates) {
        const len = digitsOnly(c.value).length;
        if (len >= lo && len <= hi) c.weight += 5;
      }
    }

    candidates.sort((a, b) =>
      (b.weight - a.weight) || (digitsOnly(b.value).length - digitsOnly(a.value).length));

    return {
      value: candidates[0].value,
      all: [...new Set(candidates.map(c => c.value))].slice(0, 12)
    };
  }

  function parseNumber(str) {
    const cleaned = String(str).replace(/,/g, '').replace(/\s/g, '');
    const n = parseFloat(cleaned);
    return isNaN(n) ? null : n;
  }

  function extractAmounts(text) {
    const out = [];

    // (أ) بجانب تسمية "المبلغ" — الأقوى
    const labelled = /(?:المبلغ|مبلغ|القيمه|قيمه|amount|total)[^0-9]{0,15}([0-9][0-9,]*(?:\.[0-9]{1,2})?)/g;
    let m;
    while ((m = labelled.exec(text)) !== null) {
      const n = parseNumber(m[1]);
      if (n !== null && n > 0) out.push({ value: n, weight: 10 });
    }

    // (ب) الأرقام المتبوعة/المسبوقة بـ SDG أو ج.س
    const curr = /([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:sdg|جنيه|ج س|ج\.س)|(?:sdg|جنيه)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/g;
    while ((m = curr.exec(text)) !== null) {
      const n = parseNumber(m[1] || m[2]);
      if (n !== null && n > 0) out.push({ value: n, weight: 8 });
    }

    // (ج) أي رقم بصيغة مالية (فاصلة آلاف أو كسر عشري)
    const money = /\b([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+\.[0-9]{2})\b/g;
    while ((m = money.exec(text)) !== null) {
      const n = parseNumber(m[1]);
      if (n !== null && n > 0) out.push({ value: n, weight: 5 });
    }

    // (د) أرقام صحيحة معقولة كمبلغ (احتياطي أخير)
    const plain = /\b([0-9]{3,9})\b/g;
    while ((m = plain.exec(text)) !== null) {
      const n = parseNumber(m[1]);
      if (n !== null && n >= 100) out.push({ value: n, weight: 1 });
    }

    const seen = new Set();
    const unique = [];
    out.sort((a, b) => b.weight - a.weight);
    for (const c of out) {
      if (!seen.has(c.value)) { seen.add(c.value); unique.push(c); }
    }
    return unique.slice(0, 40);
  }

  function extractDateTime(text) {
    // 14-apr-2025 12:55:26 | 29/01/2026 19:42:55 | 28/2/2026 20:45:09
    const patterns = [
      /(\d{1,2}[-/\s](?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-/\s]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)/,
      /(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)/,
      /(\d{2,4}[/-]\d{1,2}[/-]\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)/,
      /(\d{1,2}:\d{2}:\d{2}\s+\d{1,2}[/-]\d{1,2}[/-]\d{2,4})/
    ];
    for (const re of patterns) {
      const m = text.match(re);
      if (m) return m[1].trim();
    }
    return null;
  }

  function extractAccounts(text) {
    const from = text.match(/(?:من\s*حساب|من\s*الحساب|from\s*account)[^0-9]{0,15}([0-9\s]{8,30})/);
    const to   = text.match(/(?:الى\s*حساب|الى\s*الحساب|الى\s*البطاقه\s*رقم|to\s*account)[^0-9]{0,15}([0-9\s]{8,30})/);
    const phone = text.match(/\b(249\d{9}|0\d{9})\b/);
    return {
      from:  from  ? digitsOnly(from[1])  : null,
      to:    to    ? digitsOnly(to[1])    : null,
      phone: phone ? phone[1]             : null
    };
  }

  // ───────────────────────────────────────────────────────────────────
  // 9. المطابقة
  // ───────────────────────────────────────────────────────────────────
  function matchAmount(amountCandidates, expected, text) {
    if (!expected || expected <= 0) return { matched: false, value: null, checked: false };

    const target = Math.round(expected);
    const tol = Math.max(target * CONFIG.amountTolerance, CONFIG.amountMinAbsolute);

    for (const c of amountCandidates) {
      if (Math.abs(c.value - target) <= tol) {
        return { matched: true, value: c.value, checked: true };
      }
    }

    // مرونة إضافية: OCR قد يفقد الفاصلة أو الكسر — نبحث عن سلسلة الأرقام نفسها
    const flat = digitsOnly(text);
    if (String(target).length >= 4 && flat.includes(String(target))) {
      return { matched: true, value: target, checked: true, viaDigits: true };
    }

    return {
      matched: false,
      value: amountCandidates.length ? amountCandidates[0].value : null,
      checked: true
    };
  }

  function matchRef(manualRef, ocrRef, text) {
    const manual = normalizeRef(manualRef);
    if (!manual) return { matched: false, conflict: false, checked: false };

    const flatAll = normalizeRef(text);
    const flatDigits = digitsOnly(text);
    const manualDigits = digitsOnly(manualRef);

    // (أ) الرقم كما كتبه المستخدم موجود حرفياً في نص الصورة
    if (manual.length >= 6 && flatAll.includes(manual)) {
      return { matched: true, conflict: false, checked: true };
    }
    if (manualDigits.length >= 6 && flatDigits.includes(manualDigits)) {
      return { matched: true, conflict: false, checked: true };
    }

    // (ب) تسامح مع خطأ خانة واحدة من OCR (0/O، 1/l، 5/S ...)
    if (manualDigits.length >= 8) {
      const head = manualDigits.slice(0, -1);
      const tailPart = manualDigits.slice(1);
      if (flatDigits.includes(head) || flatDigits.includes(tailPart)) {
        return { matched: true, conflict: false, checked: true, fuzzy: true };
      }
    }

    // (ج) الصورة فيها رقم عملية واضح لكنه مخالف تماماً → تعارض
    const ocrNorm = normalizeRef(ocrRef);
    if (ocrNorm && ocrNorm.length >= 6) {
      return { matched: false, conflict: true, checked: true, ocrRef: ocrNorm };
    }

    return { matched: false, conflict: false, checked: true };
  }

  // ───────────────────────────────────────────────────────────────────
  // 10. الواجهة العامة: analyze()
  // ───────────────────────────────────────────────────────────────────
  /**
   * @param {File}   file
   * @param {Object} opts { expectedAmount, manualRef, onStatus }
   * @returns {Promise<Object>} نتيجة الفحص
   */
  async function analyze(file, opts) {
    const options = opts || {};
    const onStatus = typeof options.onStatus === 'function' ? options.onStatus : null;
    const expectedAmount = Number(options.expectedAmount) || 0;
    const manualRef = options.manualRef || '';

    const result = {
      decision: 'review',
      ocrStatus: 'needs_review',
      message: '',
      provider: null,
      providerName: null,
      confidence: null,
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

    // ── المرحلة 0: صلاحية الملف ──
    if (typeof validateReceiptImage === 'function') {
      const basic = await validateReceiptImage(file);
      if (!basic.valid) {
        result.decision = 'reject';
        result.ocrStatus = 'rejected';
        result.message = basic.message;
        result.riskFlags.push('invalid_file');
        return result;
      }
    }

    // ── المرحلة 1: بصمات التعديل ──
    if (onStatus) onStatus('جارِ التحقق من أصالة الصورة...');
    const editor = await detectImageEditing(file);
    if (editor) {
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('edited_image:' + editor);
      result.message = 'الصورة تبدو معدّلة ببرنامج تحرير صور. أرفق صورة الإشعار الأصلية كما ظهرت في تطبيق البنك بدون أي تعديل.';
      return result;
    }

    // ── المرحلتان 2 و 3: التحسين والقراءة ──
    if (typeof Tesseract === 'undefined') {
      // المحرك غير متاح → لا نعطّل الشراء، نحوّل للمراجعة اليدوية
      result.decision = 'review';
      result.message = 'تم استلام الإيصال وسيُراجع يدوياً من الإدارة.';
      result.riskFlags.push('ocr_unavailable');
      return result;
    }

    const ocr = await runOcr(file, onStatus);
    result.confidence = ocr.confidence;
    result.textLength = ocr.text.length;

    if (onStatus) onStatus('جارِ تحليل بيانات الإيصال...');

    // ── المرحلة 4: التصنيف — هل هذه صورة إشعار تحويل؟ ──
    const provider = detectProvider(ocr.text);
    const fieldHits = countKeywordHits(ocr.text, RECEIPT_FIELD_KEYWORDS.map(normalizeText));
    const refPreMatch = matchRef(manualRef, null, ocr.text);

    const looksLikeReceipt =
      (provider && provider.score >= 2) ||
      fieldHits.hits >= 2 ||
      refPreMatch.matched;

    if (!looksLikeReceipt) {
      if (ocr.text.length >= CONFIG.minTextForReject) {
        // النص واضح لكن لا يحتوي أي مفردة من إشعارات التحويل → صورة غير متعلقة
        result.decision = 'reject';
        result.ocrStatus = 'rejected';
        result.riskFlags.push('not_a_receipt');
        result.message = 'الصورة المرفوعة ليست إشعار تحويل بنكي أو محفظة. ارفع صورة إشعار التحويل من تطبيق (بنكك / أوكاش / فوري) بشكل واضح وكامل.';
        return result;
      }
      // النص غير مقروء أصلاً (تصوير ضعيف) → نطلب صورة أوضح
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('unreadable_image');
      result.message = 'تعذّر قراءة أي بيانات من الصورة. ارفع سكرين شوت واضح لإشعار التحويل بحيث يظهر رقم العملية والمبلغ.';
      return result;
    }

    if (provider) {
      result.provider = provider.key;
      result.providerName = provider.name;
    }

    // ── المرحلة 5: الاستخراج ──
    const refInfo    = extractTxRef(ocr.text, provider);
    const amountList = extractAmounts(ocr.text);
    const accounts   = extractAccounts(ocr.text);

    result.extracted.txRef           = refInfo.value;
    result.extracted.txRefCandidates = refInfo.all;
    result.extracted.amountCandidates = amountList.slice(0, 10).map(a => a.value);
    result.extracted.dateTime        = extractDateTime(ocr.text);
    result.extracted.fromAccount     = accounts.from;
    result.extracted.toAccount       = accounts.to;
    result.extracted.phone           = accounts.phone;

    // حالة العملية
    const okHits   = countKeywordHits(ocr.text, SUCCESS_KEYWORDS.map(normalizeText));
    const failHits = countKeywordHits(ocr.text, FAILURE_KEYWORDS.map(normalizeText));
    result.extracted.statusOk = failHits.hits > 0 ? false : (okHits.hits > 0 ? true : null);

    if (failHits.hits > 0 && okHits.hits === 0) {
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('failed_transaction');
      result.message = 'الإيصال يوضح أن عملية التحويل لم تنجح. أكمل التحويل بنجاح ثم ارفع الإشعار الجديد.';
      return result;
    }

    // ── المرحلة 6: المطابقة والقرار ──
    const refMatch = matchRef(manualRef, refInfo.value, ocr.text);
    const amtMatch = matchAmount(amountList, expectedAmount, ocr.text);

    result.refVerified    = !!refMatch.matched;
    result.amountVerified = !!amtMatch.matched;
    result.extracted.amount = amtMatch.value;

    // تعارض صريح بين الرقم المكتوب يدوياً والرقم في الصورة → رفض
    if (refMatch.conflict) {
      result.decision = 'reject';
      result.ocrStatus = 'rejected';
      result.riskFlags.push('ref_conflict');
      result.message = `رقم العملية الذي كتبته لا يطابق الرقم الموجود في صورة الإيصال (${refMatch.ocrRef}). تأكد من الرقم أو ارفع الإيصال الصحيح.`;
      return result;
    }

    // المبلغ لا يطابق إجمالي الطلب — نرفض فقط عندما تكون القراءة موثوقة
    if (amtMatch.checked && !amtMatch.matched) {
      const highQuality = provider && provider.score >= 2 &&
                          amountList.length > 0 &&
                          ocr.text.length >= 40;
      if (highQuality) {
        result.decision = 'reject';
        result.ocrStatus = 'rejected';
        result.riskFlags.push('amount_mismatch');
        result.message = `المبلغ في الإيصال لا يطابق إجمالي الطلب (${Math.round(expectedAmount).toLocaleString('en-US')} ج.س). راجع المبلغ المحوَّل أو ارفع الإيصال الصحيح.`;
        return result;
      }
      result.riskFlags.push('amount_unverified');
    }

    if (!refMatch.matched) result.riskFlags.push('ref_unverified');
    if (refMatch.fuzzy)    result.riskFlags.push('ref_fuzzy_match');
    if (!provider)         result.riskFlags.push('provider_unknown');

    if (result.refVerified && result.amountVerified) {
      result.decision  = 'accept';
      result.ocrStatus = 'passed';
      result.message   = `تم التحقق من الإيصال بنجاح${result.providerName ? ' (' + result.providerName + ')' : ''}: رقم العملية والمبلغ مطابقان.`;
    } else {
      result.decision  = 'review';
      result.ocrStatus = 'needs_review';
      result.message   = 'تم استلام الإيصال. بعض البيانات لم تُقرأ بدقة، لذلك سيُراجع طلبك يدوياً من الإدارة.';
    }

    return result;
  }

  // ───────────────────────────────────────────────────────────────────
  // 11. تصدير
  // ───────────────────────────────────────────────────────────────────
  window.ReceiptIntel = {
    analyze,
    normalizeRef,
    normalizeText,
    digitsOnly,
    detectProvider,
    CONFIG,
    PROVIDERS
  };
})();
