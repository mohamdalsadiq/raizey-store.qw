/* =========================================================================
 * RAIZEY STORE — الفحص الذكي من السيرفر (Server-Side Receipt Verification)
 * =========================================================================
 * مسار الملف: api/verify-receipt.js  (Vercel Serverless Function)
 *
 * الفكرة:
 *   1) الصورة تُرسَل من checkout.html إلى هذا الـ endpoint (base64 مضغوطة).
 *   2) نستدعي Google Gemini Vision لاستخراج كل النص الظاهر في الصورة
 *      حرفياً (بديل OCR أسرع وأدق من Tesseract في متصفح العميل).
 *   3) النص المستخرَج يُمرَّر لنفس محرك القرار الحتمي الموجود في
 *      assets/js/receipt-judge-core.js (buildContext + judge).
 *
 * مبادئ ثابتة:
 *   - Gemini = أداة قراءة نص (OCR) فقط، وليس صانع قرار مالي. القرار حتمي 100%.
 *   - Fail-Closed: أي فشل تقني ⇒ `review` (مراجعة يدوية). أبداً لا `accept`
 *     تلقائي، وأبداً لا `reject` بسبب خطأ تقني.
 *   - الاتصال بـ Gemini مباشر عبر REST بمفتاح process.env.GEMINI_API_KEY
 *     (بدون أي AI Gateway / بدون فوترة).
 *
 * تشخيص سريع من المتصفح:
 *   GET /api/verify-receipt  ⇒ JSON فيه { ok, geminiConfigured, ... }
 *   (لو رجعت صفحة 404 من Vercel فمعناها الدالة لم تُنشر أصلاً.)
 * ========================================================================= */

const ReceiptJudgeCore = require('../assets/js/receipt-judge-core.js');

// أول موديل متاح يُستخدَم؛ لو رجع الأول 404/400 (موديل غير متاح لهذا المفتاح)
// نجرّب التالي تلقائياً بدل أن نسقط كل الفحص لمحرك المتصفح البطيء.
// تم التحقق من هذه الموديلات باستدعاء حقيقي بمفتاح المشروع (لا تعتمد على
// ListModels: هي تُدرِج gemini-2.5-* لكن الاستدعاء يرجع 404
// "no longer available to new users"). الترتيب: الأسرع والأرخص أولاً.
const GEMINI_MODELS = [
  'gemini-3.1-flash-lite',
  'gemini-3-flash-preview',
  'gemini-3.6-flash'
];
const GEMINI_TIMEOUT_MS = 24000;

// حد Vercel لجسم الطلب ≈ 4.5MB. base64 أكبر من الأصل بنحو 33%، لذلك نضع
// سقفاً واقعياً للنص base64 نفسه (3.6MB) — الواجهة تضغط الصورة قبل الإرسال.
const MAX_BASE64_CHARS = 3.6 * 1024 * 1024;

const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp'];

// ── أي شيء يفشل هنا ينتج مراجعة يدوية، لا رفض ولا قبول ──
function softReview(flag, message, debug) {
  const r = ReceiptJudgeCore.blankResult();
  r.decision = 'review';
  r.ocrStatus = 'needs_review';
  r.riskFlags.push(flag);
  r.message = message ||
    'تعذّر إكمال الفحص الآلي للصورة. تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.';
  r.source = 'server';
  if (debug) r.debug = String(debug).slice(0, 300);
  return r;
}

function withTimeout(promise, ms, tag) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('timeout:' + tag)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

// بعض بيئات التشغيل لا تُحلّل الجسم تلقائياً — نقرأه يدوياً كخطة بديلة
function readRawBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > MAX_BASE64_CHARS * 1.2) {
        reject(new Error('body_too_large'));
        req.destroy();
      }
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

async function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string' && req.body.length) {
    try { return JSON.parse(req.body); } catch (e) { /* نكمل للقراءة اليدوية */ }
  }
  const raw = await readRawBody(req);
  if (!raw) return {};
  try { return JSON.parse(raw); } catch (e) { return {}; }
}

const OCR_PROMPT =
  'انسخ حرفياً كل نص ظاهر في هذه الصورة (عربي وإنجليزي، أرقام، تسميات الحقول، ' +
  'كل سطر كما هو) بدون أي تلخيص أو تفسير أو إضافة أو ترجمة. حافظ على ترتيب الأسطر. ' +
  'إذا لم تكن الصورة تحتوي على أي نص واضح فأعد نصاً فارغاً. لا تكتب أي شيء غير النص المنسوخ.';

/**
 * يستدعي موديلاً واحداً ويعيد النص الخام. يرمي استثناءً عند الفشل.
 * ملاحظات مهمة (سبب فشل النسخة السابقة):
 *   - gemini-2.5-flash موديل "تفكير"؛ بدون thinkingBudget=0 كان يستهلك حصة
 *     الإخراج في التفكير ويعيد candidate بلا parts ⇒ gemini_empty_response.
 *   - المفتاح يُرسَل في هيدر x-goog-api-key (أنظف من وضعه في الـ URL).
 *   - لا نستخدم responseSchema صارماً: النص الخام أبسط وأقل عرضة للفشل.
 */
async function callGeminiModel(model, base64Data, mimeType, apiKey) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

  const body = {
    contents: [{
      role: 'user',
      parts: [
        { inline_data: { mime_type: mimeType, data: base64Data } },
        { text: OCR_PROMPT }
      ]
    }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 2048,
      // إيقاف "التفكير" — مطلوب للموديلات 2.5 حتى لا يعود الرد فارغاً
      thinkingConfig: { thinkingBudget: 0 }
    },
    safetySettings: [
      { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_NONE' },
      { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_NONE' },
      { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_NONE' },
      { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_NONE' }
    ]
  };

  const res = await withTimeout(
    fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey
      },
      body: JSON.stringify(body)
    }),
    GEMINI_TIMEOUT_MS,
    'gemini_request'
  );

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    const err = new Error('gemini_http_' + res.status + ':' + errText.replace(/\s+/g, ' ').slice(0, 220));
    err.status = res.status;
    throw err;
  }

  const data = await res.json();
  const cand = data && data.candidates && data.candidates[0];
  const parts = cand && cand.content && cand.content.parts;
  let text = '';
  if (Array.isArray(parts)) {
    text = parts.map((p) => (p && typeof p.text === 'string' ? p.text : '')).join('\n');
  }
  text = String(text || '').trim();

  if (!text) {
    const reason = (cand && cand.finishReason) ||
      (data && data.promptFeedback && data.promptFeedback.blockReason) || 'no_text';
    const err = new Error('gemini_empty_response:' + reason);
    err.status = 200;
    // الموديل أكمل الرد طبيعياً وقال إن الصورة بلا نص ⇒ ليست إشعار تحويل.
    // (أما STOP بسبب SAFETY / MAX_TOKENS / حجب فهو فشل تقني ⇒ مراجعة يدوية.)
    if (reason === 'STOP' || reason === 'no_text') err.code = 'no_visible_text';
    throw err;
  }

  // لو رجع الموديل JSON بالخطأ ({"raw_text": "..."}) نستخرج المحتوى
  if (text.charAt(0) === '{' && text.indexOf('raw_text') !== -1) {
    try {
      const parsed = JSON.parse(text.replace(/^```(?:json)?|```$/g, '').trim());
      if (parsed && typeof parsed.raw_text === 'string') text = parsed.raw_text;
    } catch (e) { /* نستخدم النص كما هو */ }
  }

  return text;
}

// ── المرور الثاني (التحكيم): استخراج منظّم بصيغة JSON عند الشك ──
const JSON_PROMPT =
  'أنت مدقق إشعارات تحويل بنكي. انظر للصورة وأعد JSON فقط بهذا الشكل بالضبط: ' +
  '{"transaction_number":"","amount":"","currency":"","status":"","datetime":"","to_account":"","bank":""}. ' +
  'قواعد صارمة: انسخ رقم العملية/المرجع كما هو رقماً رقماً بلا تخمين ولا تصحيح. ' +
  'المبلغ = مبلغ التحويل فقط (وليس الرصيد أو الرسوم). ' +
  'إذا لم تكن القيمة ظاهرة بوضوح تماماً في الصورة اتركها سلسلة فارغة "". ' +
  'ممنوع الاختراع أو الاستنتاج. أعد JSON فقط بلا أي شرح.';

async function callGeminiJson(model, parts, apiKey) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    contents: [{ role: 'user', parts: parts.concat([{ text: JSON_PROMPT }]) }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 1024,
      responseMimeType: 'application/json',
      thinkingConfig: { thinkingBudget: 0 }
    }
  };
  const res = await withTimeout(
    fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify(body)
    }),
    GEMINI_TIMEOUT_MS, 'gemini_json'
  );
  if (!res.ok) throw new Error('gemini_json_http_' + res.status);
  const data = await res.json();
  const cand = data && data.candidates && data.candidates[0];
  const ps = cand && cand.content && cand.content.parts;
  let text = Array.isArray(ps) ? ps.map(x => (x && x.text) || '').join('') : '';
  text = String(text || '').replace(/^```(?:json)?|```$/g, '').trim();
  if (!text) throw new Error('gemini_json_empty');
  return JSON.parse(text);
}

async function structuredPass(parts, apiKey) {
  let lastErr = null;
  for (const model of GEMINI_MODELS) {
    try { return { data: await callGeminiJson(model, parts, apiKey), model }; }
    catch (e) { lastErr = e; }
  }
  throw lastErr || new Error('gemini_json_failed');
}

async function extractTextWithGemini(base64Data, mimeType, apiKey) {
  let lastErr = null;
  for (const model of GEMINI_MODELS) {
    try {
      return { text: await callGeminiModel(model, base64Data, mimeType, apiKey), model };
    } catch (err) {
      lastErr = err;
      const msg = String((err && err.message) || '');
      // صورة بلا أي نص ظاهر: قراءة مؤكدة، لا فائدة من موديل آخر
      if (err && err.code === 'no_visible_text') throw err;
      // مهلة أو خطأ مصادقة/حصة ⇒ لا فائدة من تجربة موديل آخر
      if (msg.indexOf('timeout') === 0) throw err;
      if (err.status === 401 || err.status === 403 || err.status === 429) throw err;
      // 404 (موديل غير متاح) أو 400 أو رد فارغ ⇒ نجرّب الموديل التالي
    }
  }
  throw lastErr || new Error('gemini_all_models_failed');
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, max-age=0');

  // ── فحص صحة النشر (يُفتح مباشرة من المتصفح للتشخيص) ──
  if (req.method === 'GET' || req.method === 'HEAD') {
    res.status(200).json({
      ok: true,
      endpoint: 'verify-receipt',
      geminiConfigured: !!process.env.GEMINI_API_KEY,
      models: GEMINI_MODELS,
      judgeCoreLoaded: typeof ReceiptJudgeCore.judge === 'function',
      maxBase64Chars: MAX_BASE64_CHARS,
      hint: 'POST { imageBase64, mimeType, expectedAmount, manualRef, expectedAccount }'
    });
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json(softReview('method_not_allowed', 'طريقة طلب غير مدعومة.'));
    return;
  }

  let body;
  try {
    body = await parseBody(req);
  } catch (err) {
    res.status(200).json(softReview('image_too_large',
      'حجم الصورة كبير جداً. ارفع لقطة شاشة عادية (أقل من 3 ميجابايت).', err && err.message));
    return;
  }
  body = body || {};

  let { imageBase64, mimeType, expectedAmount, manualRef, expectedAccount,
        imageBase64Extra, mimeTypeExtra } = body;

  if (!imageBase64 || typeof imageBase64 !== 'string') {
    res.status(200).json(softReview('missing_image', 'لم تصل بيانات الصورة. حاول رفعها مرة أخرى.'));
    return;
  }

  // تنظيف: إزالة بادئة data: إن وُجدت، وأي مسافات/أسطر داخل base64
  const comma = imageBase64.indexOf(',');
  if (imageBase64.slice(0, 5) === 'data:' && comma !== -1) {
    imageBase64 = imageBase64.slice(comma + 1);
  }
  imageBase64 = imageBase64.replace(/\s/g, '');

  if (imageBase64.length > MAX_BASE64_CHARS) {
    res.status(200).json(softReview('image_too_large',
      'حجم الصورة كبير جداً. ارفع لقطة شاشة عادية (أقل من 3 ميجابايت).'));
    return;
  }

  let mt = String(mimeType || 'image/jpeg').toLowerCase().split(';')[0].trim();
  if (mt === 'image/jpg') mt = 'image/jpeg';
  if (ALLOWED_MIME.indexOf(mt) === -1) {
    res.status(200).json(softReview('unsupported_image_format',
      'صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WEBP فقط.'));
    return;
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    // Fail-Closed: مراجعة يدوية — والواجهة تنتقل لمحرك المتصفح كخطة بديلة
    res.status(200).json(softReview('gemini_not_configured',
      'محرك الفحص السريع غير مُفعَّل حالياً على السيرفر.',
      'GEMINI_API_KEY missing in this environment'));
    return;
  }

  const options = {
    expectedAmount: Number(expectedAmount) || 0,
    manualRef: manualRef || '',
    expectedAccount: expectedAccount || '',
    // قراءة السيرفر دقيقة ⇒ محرك القرار يرفض "ليست إيصالاً" بلا حد أدنى للنص
    ocrSource: 'server',
    trustedOcr: true
  };

  // صورة إضافية اختيارية (الإشعار الأبيض / بقية الشاشة)
  let extraB64 = null, mtExtra = 'image/jpeg';
  if (imageBase64Extra && typeof imageBase64Extra === 'string') {
    let e = imageBase64Extra;
    const c2 = e.indexOf(',');
    if (e.slice(0, 5) === 'data:' && c2 !== -1) e = e.slice(c2 + 1);
    e = e.replace(/\s/g, '');
    if (e.length && e.length <= MAX_BASE64_CHARS) {
      extraB64 = e;
      let m2 = String(mimeTypeExtra || 'image/jpeg').toLowerCase().split(';')[0].trim();
      if (m2 === 'image/jpg') m2 = 'image/jpeg';
      if (ALLOWED_MIME.indexOf(m2) === -1) {
        extraB64 = null;
      } else {
        mtExtra = m2;
      }
    }
  }

  let rawText = '';
  let usedModel = null;
  try {
    const out = await extractTextWithGemini(imageBase64, mt, apiKey);
    rawText = out.text;
    usedModel = out.model;
    if (extraB64) {
      try {
        const out2 = await extractTextWithGemini(extraB64, mtExtra, apiKey);
        rawText = rawText + '\n' + out2.text;
      } catch (e2) { /* الصورة الإضافية اختيارية */ }
    }
  } catch (err) {
    const tag = String((err && err.message) || 'unknown');

    // ── صورة بلا أي نص ظاهر ⇒ رفض مؤكد (ليست إشعار تحويل) ──
    if (err && err.code === 'no_visible_text') {
      const r = ReceiptJudgeCore.blankResult();
      r.decision = 'reject';
      r.ocrStatus = 'rejected';
      r.riskFlags.push('not_a_receipt');
      r.source = 'server';
      r.textLength = 0;
      r.message = 'الصورة المرفوعة لا تحتوي على أي نص — إذاً هي ليست إشعار تحويل. ' +
        'ارفع لقطة شاشة لإشعار التحويل من التطبيق (بنكك / أوكاش / فوري / كاشي) كاملة وواضحة.';
      res.status(200).json(r);
      return;
    }

    console.error('[RAIZEY] gemini ocr failed:', tag);
    const flag = tag.indexOf('timeout') === 0 ? 'server_ocr_timeout' : 'server_ocr_failed';
    res.status(200).json(softReview(flag,
      'تعذّر تشغيل محرك الفحص السريع (غالباً اتصال مؤقت). تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.',
      tag));
    return;
  }

  try {
    const imgParts = [{ inline_data: { mime_type: mt, data: imageBase64 } }];
    if (extraB64) imgParts.push({ inline_data: { mime_type: mtExtra, data: extraB64 } });

    let ctx = ReceiptJudgeCore.buildContext([rawText], options);
    let result = ReceiptJudgeCore.judge(ctx, options, ReceiptJudgeCore.blankResult());

    // ── المرور الثاني (التحكيم): يعمل فقط عندما لا يكون القرار قبولاً مؤكداً ──
    // لا يُستخدم للتساهل: مخرجاته نص إضافي يمرّ على نفس محرك القرار الحتمي.
    // القبول الكامل والقبول-مع-تدقيق-إداري كلاهما مؤكَّد البيانات ⇒ لا تحكيم
    const needsArbitration = !((result.decision === 'accept' ||
                                result.decision === 'review_admin') &&
                               result.refVerified && result.amountVerified) &&
                             result.decision !== 'reject';
    if (needsArbitration) {
      try {
        const sp = await structuredPass(imgParts, apiKey);
        const d = sp.data || {};
        const lines = [
          d.bank ? ('البنك: ' + d.bank) : '',
          d.status ? ('الحالة: ' + d.status) : '',
          d.transaction_number ? ('رقم العملية: ' + d.transaction_number) : '',
          d.amount ? ('المبلغ: ' + d.amount + ' ' + (d.currency || '')) : '',
          d.datetime ? ('التاريخ: ' + d.datetime) : '',
          d.to_account ? ('إلى حساب: ' + d.to_account) : ''
        ].filter(Boolean).join('\n');
        if (lines) {
          const merged = rawText + '\n' + lines;
          const ctx2 = ReceiptJudgeCore.buildContext([merged], options);
          const r2 = ReceiptJudgeCore.judge(ctx2, options, ReceiptJudgeCore.blankResult());
          r2.passes = 2;
          r2.arbitration = { model: sp.model, extracted: d };
          rawText = merged;
          result = r2;
        }
      } catch (e) {
        result.riskFlags = (result.riskFlags || []).concat(['arbitration_failed']);
      }
    }

    result.source = 'server';
    result.model = usedModel;
    result.confidence = rawText && rawText.trim().length > 20 ? 90 : null;
    result.textLength = rawText.length;
    res.status(200).json(result);
  } catch (err) {
    console.error('[RAIZEY] judge error:', (err && err.message) || err);
    res.status(200).json(softReview('judge_error',
      'حدث خطأ غير متوقع أثناء تحليل الإيصال. تم استلام طلبك وسيُراجع يدوياً من الإدارة.',
      (err && err.message) || 'judge_error'));
  }
};
