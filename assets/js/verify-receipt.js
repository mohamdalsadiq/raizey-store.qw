/* =========================================================================
 * RAIZEY STORE — الفحص الذكي من السيرفر (Server-Side Receipt Verification)
 * =========================================================================
 * مسار الملف: api/verify-receipt.js  (Vercel Serverless Function)
 *
 * الفكرة:
 *   1) الصورة تُرسَل من checkout.html إلى هذا الـ endpoint (base64).
 *   2) نستدعي Google Gemini Vision لاستخراج كل النص الظاهر في الصورة
 *      حرفياً (بديل OCR أسرع وأدق من Tesseract في متصفح العميل).
 *   3) النص المستخرَج يُمرَّر لنفس محرك القرار الحتمي الموجود في
 *      assets/js/receipt-judge-core.js (buildContext + judge) — بحيث
 *      يكون القرار (قبول / رفض / مراجعة) مبنياً على نفس المنطق المُختبَر
 *      في المحرك الأصلي، وليس على "رأي" النموذج اللغوي نفسه.
 *
 * لماذا هذا التصميم؟
 *   - Gemini يُستخدَم فقط كأداة قراءة نص (OCR)، وليس كصانع قرار مالي.
 *     القرار النهائي حتمي 100% (نفس الأكواد المُختبَرة)، ما يمنع أي
 *     "هلوسة" من النموذج اللغوي من قبول طلب مزيّف.
 *   - Fail-Closed دائماً: أي فشل (مفتاح API غير مُعد، انتهاء مهلة، خطأ
 *     شبكة، رد غير مفهوم من Gemini) يُرجع حالة `review` (مراجعة يدوية)
 *     فقط — أبداً لا يُرجع `accept` تلقائياً.
 *   - Timeout صارم (12 ثانية) حتى لا يعلّق العميل بلا نتيجة.
 *
 * الإعداد المطلوب منك (صاحب المشروع):
 *   أضف في Vercel → Project Settings → Environment Variables:
 *     GEMINI_API_KEY = <مفتاحك من https://aistudio.google.com/apikey>
 *   (مجاني — الفئة المجانية لموديل gemini-2.5-flash تكفي حجم الموقع
 *    الحالي. لا حاجة لأي بطاقة ائتمان.)
 * ========================================================================= */

const ReceiptJudgeCore = require('../assets/js/receipt-judge-core.js');

const GEMINI_MODEL = 'gemini-2.5-flash';
const GEMINI_TIMEOUT_MS = 12000;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024; // 8MB حد أعلى معقول لصورة إشعار

// ── ضمان عدم التعليق أبداً: أي شيء يفشل هنا ينتج مراجعة يدوية، لا رفض ولا قبول ──
function softReview(flag, message) {
  const r = ReceiptJudgeCore.blankResult();
  r.decision = 'review';
  r.ocrStatus = 'needs_review';
  r.riskFlags.push(flag);
  r.message = message ||
    'تعذّر إكمال الفحص الآلي للصورة. تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.';
  r.source = 'server';
  return r;
}

function withTimeout(promise, ms, tag) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('timeout:' + tag)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * يستدعي Gemini لاستخراج كل النص الظاهر في الصورة حرفياً، بأقل قدر ممكن
 * من "التفسير" — المطلوب نسخ النص فقط كما يظهر، عربياً وإنجليزياً معاً.
 */
async function extractTextWithGemini(base64Data, mimeType, apiKey) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

  const prompt =
    'انسخ حرفياً كل نص ظاهر في هذه الصورة (عربي وإنجليزي، أرقام، تسميات الحقول، ' +
    'كل سطر كما هو) بدون أي تلخيص أو تفسير أو إضافة. إذا لم تكن الصورة تحتوي على ' +
    'أي نص واضح، أعد نصاً فارغاً. أعد النتيجة بصيغة JSON فقط بالشكل التالي:\n' +
    '{"raw_text": "...النص الكامل كما يظهر، سطراً بسطر..."}';

  const body = {
    contents: [{
      parts: [
        { inline_data: { mime_type: mimeType, data: base64Data } },
        { text: prompt }
      ]
    }],
    generationConfig: {
      temperature: 0,
      responseMimeType: 'application/json',
      responseSchema: {
        type: 'object',
        properties: { raw_text: { type: 'string' } },
        required: ['raw_text']
      }
    }
  };

  const res = await withTimeout(
    fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }),
    GEMINI_TIMEOUT_MS,
    'gemini_request'
  );

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error('gemini_http_' + res.status + ':' + errText.slice(0, 200));
  }

  const data = await res.json();
  const textPart = data &&
    data.candidates && data.candidates[0] &&
    data.candidates[0].content && data.candidates[0].content.parts &&
    data.candidates[0].content.parts[0] && data.candidates[0].content.parts[0].text;

  if (!textPart) throw new Error('gemini_empty_response');

  let parsed;
  try {
    parsed = JSON.parse(textPart);
  } catch (e) {
    // بعض الردود قد تُغلَّف بأسطر إضافية رغم طلب JSON الصارم — محاولة استخراج آمنة
    const match = textPart.match(/\{[\s\S]*\}/);
    if (!match) throw new Error('gemini_bad_json');
    parsed = JSON.parse(match[0]);
  }

  return String(parsed.raw_text || '');
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (req.method !== 'POST') {
    res.status(405).json(softReview('method_not_allowed', 'طريقة طلب غير مدعومة.'));
    return;
  }

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (e) { body = {}; }
  }
  body = body || {};

  const { imageBase64, mimeType, expectedAmount, manualRef, expectedAccount } = body;

  // ── تحقق أساسي من المدخلات — أي نقص يُرجع مراجعة يدوية وليس خطأ يكسر الواجهة ──
  if (!imageBase64 || typeof imageBase64 !== 'string') {
    res.status(200).json(softReview('missing_image', 'لم تصل بيانات الصورة. حاول رفعها مرة أخرى.'));
    return;
  }
  if (imageBase64.length > MAX_IMAGE_BYTES * 1.4) { // base64 أكبر بنحو 33% من الحجم الأصلي
    res.status(200).json(softReview('image_too_large', 'حجم الصورة كبير جداً. ارفع صورة أصغر (لقطة شاشة عادية تكفي).'));
    return;
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    // مفتاح Gemini غير مُعد بعد على السيرفر — Fail-Closed: مراجعة يدوية،
    // والواجهة الأمامية ستنتقل تلقائياً لمحرك Tesseract في المتصفح كخطة بديلة.
    res.status(200).json(softReview('gemini_not_configured', 'محرك الفحص السريع غير مُفعَّل حالياً على السيرفر.'));
    return;
  }

  const options = {
    expectedAmount: Number(expectedAmount) || 0,
    manualRef: manualRef || '',
    expectedAccount: expectedAccount || ''
  };

  let rawText;
  try {
    rawText = await extractTextWithGemini(imageBase64, mimeType || 'image/jpeg', apiKey);
  } catch (err) {
    const tag = String(err && err.message || 'unknown');
    const flag = tag.indexOf('timeout') === 0 ? 'server_ocr_timeout' : 'server_ocr_failed';
    res.status(200).json(softReview(flag,
      'تعذّر تشغيل محرك الفحص السريع (غالباً اتصال مؤقت). تم استلام إيصالك وسيُراجع يدوياً من الإدارة — يمكنك إكمال الطلب الآن.'));
    return;
  }

  try {
    const ctx = ReceiptJudgeCore.buildContext([rawText], options);
    const result = ReceiptJudgeCore.judge(ctx, options, ReceiptJudgeCore.blankResult());
    result.source = 'server';
    result.confidence = rawText && rawText.trim().length > 20 ? 90 : null;
    result.textLength = rawText.length;
    res.status(200).json(result);
  } catch (err) {
    // خطأ غير متوقع في محرك القرار نفسه — لا يجوز أن يُسقِط الطلب، مراجعة يدوية فقط
    res.status(200).json(softReview('judge_error', 'حدث خطأ غير متوقع أثناء تحليل الإيصال. تم استلام طلبك وسيُراجع يدوياً من الإدارة.'));
  }
};
