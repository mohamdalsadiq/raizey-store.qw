import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { ReceiptJudgeCore } from "./receipt-judge-core.ts";

// نماذج Vision مستقرة ومتاحة عبر Gemini API؛ نبدأ بالنموذج الرسمي المتوازن.
const GEMINI_MODELS = [
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
  "gemini-3-flash-preview",
];
const GEMINI_TIMEOUT_MS = 24_000;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const MAX_BASE64_CHARS = Math.ceil(MAX_IMAGE_BYTES * 1.36);
const MAX_REQUEST_CHARS = MAX_BASE64_CHARS * 2 + 160_000;
const SCAN_TTL_MINUTES = 30;
const RATE_WINDOW_MINUTES = 10;
const MAX_SCANS_PER_WINDOW = 12;
const ALLOWED_MIME = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const OCR_PROMPT =
  "انسخ حرفياً كل نص ظاهر في هذه الصورة (عربي وإنجليزي، أرقام، تسميات الحقول، " +
  "كل سطر كما هو) بدون أي تلخيص أو تفسير أو إضافة أو ترجمة. حافظ على ترتيب الأسطر. " +
  "إذا لم تكن الصورة تحتوي على أي نص واضح فأعد نصاً فارغاً. لا تكتب أي شيء غير النص المنسوخ.";

const JSON_PROMPT =
  "أنت مدقق إشعارات تحويل بنكي. انظر للصورة وأعد JSON فقط بهذا الشكل بالضبط: " +
  '{"transaction_number":"","amount":"","currency":"","status":"","datetime":"","to_account":"","bank":""}. ' +
  "قواعد صارمة: انسخ رقم العملية/المرجع كما هو رقماً رقماً بلا تخمين ولا تصحيح. " +
  "المبلغ = مبلغ التحويل فقط (وليس الرصيد أو الرسوم). " +
  'إذا لم تكن القيمة ظاهرة بوضوح تماماً في الصورة اتركها سلسلة فارغة "". ' +
  "ممنوع الاختراع أو الاستنتاج. أعد JSON فقط بلا أي شرح.";

type ScanOptions = {
  expectedAmount: number;
  manualRef: string;
  expectedAccount: string;
};

type ScanResult = Record<string, any> & {
  riskFlags?: string[];
  extracted?: Record<string, any>;
};

function env(name: string): string {
  return String(Deno.env.get(name) || "").trim();
}

function json(data: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      ...corsHeaders(),
      ...extraHeaders,
    },
  });
}

function corsHeaders(): Record<string, string> {
  const origin = env("RAIZEY_PUBLIC_ORIGIN") || "*";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function withTimeout<T>(promise: Promise<T>, ms: number, tag: string): Promise<T> {
  let timer: number | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout:${tag}`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  });
}

function softReview(flag: string, message?: string): ScanResult {
  const result = ReceiptJudgeCore.blankResult() as ScanResult;
  result.decision = "review";
  result.ocrStatus = "needs_review";
  result.riskFlags = [flag];
  result.message = message ||
    "تعذّر إكمال الفحص الآلي للصورة. أعد المحاولة بعد لحظات؛ لم يُنشأ أي طلب.";
  result.source = "edge";
  result.submissionAllowed = false;
  return result;
}

function normalizeMime(value: unknown): string {
  let mime = String(value || "image/jpeg").toLowerCase().split(";")[0].trim();
  if (mime === "image/jpg") mime = "image/jpeg";
  return ALLOWED_MIME.has(mime) ? mime : "";
}

function cleanBase64(value: unknown): string {
  let text = typeof value === "string" ? value : "";
  const comma = text.indexOf(",");
  if (text.slice(0, 5).toLowerCase() === "data:" && comma !== -1) {
    text = text.slice(comma + 1);
  }
  return text.replace(/\s/g, "");
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

type ParsedImage = { base64: string; mimeType: string; bytes: Uint8Array };

function parseImagePayload(base64Value: unknown, mimeValue: unknown): ParsedImage {
  const base64 = cleanBase64(base64Value);
  const mimeType = normalizeMime(mimeValue);
  if (!base64 || !mimeType) throw new Error("invalid_image_input");
  if (base64.length > MAX_BASE64_CHARS) throw new Error("image_too_large");
  let bytes: Uint8Array;
  try {
    bytes = decodeBase64(base64);
  } catch (_) {
    throw new Error("invalid_base64");
  }
  if (!bytes.byteLength) throw new Error("invalid_image_input");
  if (bytes.byteLength > MAX_IMAGE_BYTES) throw new Error("image_too_large");
  return { base64, mimeType, bytes };
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function callGeminiModel(model: string, base64Data: string, mimeType: string, apiKey: string): Promise<string> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    contents: [{
      role: "user",
      parts: [
        { inline_data: { mime_type: mimeType, data: base64Data } },
        { text: OCR_PROMPT },
      ],
    }],
    generationConfig: { temperature: 0, maxOutputTokens: 2048, thinkingConfig: { thinkingBudget: 0 } },
    safetySettings: [
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
      { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
    ],
  };
  const response = await withTimeout(fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify(body),
  }), GEMINI_TIMEOUT_MS, "gemini_request");
  if (!response.ok) {
    const detail = (await response.text().catch(() => "")).replace(/\s+/g, " ").slice(0, 220);
    const error = new Error(`gemini_http_${response.status}:${detail}`);
    (error as any).status = response.status;
    throw error;
  }
  const data = await response.json();
  const candidate = data?.candidates?.[0];
  const parts = candidate?.content?.parts;
  let text = Array.isArray(parts) ? parts.map((part: any) => typeof part?.text === "string" ? part.text : "").join("\n").trim() : "";
  if (!text) {
    const reason = candidate?.finishReason || data?.promptFeedback?.blockReason || "no_text";
    const error = new Error(`gemini_empty_response:${reason}`);
    (error as any).status = 200;
    if (reason === "STOP" || reason === "no_text") (error as any).code = "no_visible_text";
    throw error;
  }
  if (text.startsWith("{") && text.includes("raw_text")) {
    try {
      const parsed = JSON.parse(text.replace(/^```(?:json)?|```$/g, "").trim());
      if (typeof parsed?.raw_text === "string") text = parsed.raw_text;
    } catch (_) { /* استخدم النص كما هو */ }
  }
  return text;
}

async function extractTextWithGemini(base64Data: string, mimeType: string, apiKey: string) {
  let lastError: any = null;
  for (const model of GEMINI_MODELS) {
    try {
      return { text: await callGeminiModel(model, base64Data, mimeType, apiKey), model };
    } catch (error) {
      lastError = error;
      const message = String((error as any)?.message || "");
      if ((error as any)?.code === "no_visible_text") throw error;
      if (message.startsWith("timeout:") || [401, 403, 429].includes((error as any)?.status)) throw error;
    }
  }
  throw lastError || new Error("gemini_all_models_failed");
}

async function callGeminiJson(model: string, parts: any[], apiKey: string) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    contents: [{ role: "user", parts: parts.concat([{ text: JSON_PROMPT }]) }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 1024,
      responseMimeType: "application/json",
      thinkingConfig: { thinkingBudget: 0 },
    },
  };
  const response = await withTimeout(fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
    body: JSON.stringify(body),
  }), GEMINI_TIMEOUT_MS, "gemini_json");
  if (!response.ok) throw new Error(`gemini_json_http_${response.status}`);
  const data = await response.json();
  const partsOut = data?.candidates?.[0]?.content?.parts;
  const text = Array.isArray(partsOut) ? partsOut.map((part: any) => part?.text || "").join("").replace(/^```(?:json)?|```$/g, "").trim() : "";
  if (!text) throw new Error("gemini_json_empty");
  return JSON.parse(text);
}

async function structuredPass(parts: any[], apiKey: string) {
  let lastError: any = null;
  for (const model of GEMINI_MODELS) {
    try {
      return { data: await callGeminiJson(model, parts, apiKey), model };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error("gemini_json_failed");
}

function authToken(request: Request): string {
  const header = request.headers.get("Authorization") || "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

function buildAdminClient() {
  const url = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) throw new Error("supabase_service_credentials_missing");
  return createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
}

async function enforceRateLimit(admin: any, userId: string): Promise<boolean> {
  const since = new Date(Date.now() - RATE_WINDOW_MINUTES * 60_000).toISOString();
  const { count, error } = await admin
    .from("receipt_scan_results")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", since);
  if (error) throw error;
  return (count || 0) < MAX_SCANS_PER_WINDOW;
}

async function saveScan(admin: any, userId: string, hash: string, bytes: Uint8Array, options: ScanOptions, result: ScanResult, model: string | null, rawText: string) {
  const extracted = result.extracted || {};
  const scanPayload = {
    user_id: userId,
    receipt_hash: hash,
    image_bytes: bytes.byteLength,
    mime_type: result.mimeType || null,
    expected_amount: options.expectedAmount || null,
    manual_ref: options.manualRef || null,
    expected_account: options.expectedAccount || null,
    decision: result.decision || "review",
    ocr_status: result.ocrStatus || "needs_review",
    amount_detected: extracted.amount ?? null,
    tx_ref_ocr: extracted.txRef || null,
    provider: result.provider || null,
    provider_name: result.providerName || null,
    ocr_confidence: result.confidence ?? null,
    risk_flags: Array.isArray(result.riskFlags) ? result.riskFlags : [],
    ocr_data: {
      ...extracted,
      decision: result.decision || null,
      message: result.message || null,
      review_reason: result.reviewReason || null,
      review_severity: result.reviewSeverity || null,
      language: result.language || null,
      passes: result.passes || 0,
      text_length: result.textLength || 0,
      ref_verified: !!result.refVerified,
      amount_verified: !!result.amountVerified,
      engine_source: "supabase_edge",
      engine_version: result.version || 4,
      model,
      raw_text_excerpt: rawText.slice(0, 3000),
    },
    expires_at: new Date(Date.now() + SCAN_TTL_MINUTES * 60_000).toISOString(),
    submission_allowed: result.decision !== "reject",
  };
  const { data, error } = await admin
    .from("receipt_scan_results")
    .insert(scanPayload)
    .select("id, receipt_hash, decision, ocr_status, submission_allowed, expires_at")
    .single();
  if (error) throw error;
  return data;
}

async function processScan(request: Request, admin: any, userId: string, body: any): Promise<ScanResult> {
  let image: ParsedImage;
  try {
    image = parseImagePayload(body?.imageBase64, body?.mimeType);
  } catch (error) {
    const code = String((error as any)?.message || "invalid_image_input");
    if (code === "image_too_large") return softReview(code, "حجم الصورة أكبر من 5 ميجابايت. ارفع صورة JPG أو PNG أو WEBP أصغر.");
    if (code === "invalid_base64") return softReview(code, "تعذّر قراءة الصورة المرسلة. أعد اختيار الملف.");
    return softReview("invalid_image_input", "صيغة الصورة غير صالحة. ارفع JPG أو PNG أو WEBP.");
  }
  const imageBase64 = image.base64;
  const mimeType = image.mimeType;
  const bytes = image.bytes;
  const hash = await sha256Hex(bytes);
  const options: ScanOptions = {
    expectedAmount: Math.max(0, Number(body?.expectedAmount) || 0),
    manualRef: String(body?.manualRef || "").slice(0, 80),
    expectedAccount: String(body?.expectedAccount || "").slice(0, 80),
  };
  const apiKey = env("GEMINI_API_KEY");
  if (!apiKey) return softReview("gemini_not_configured", "محرك الفحص الخادمي غير مُفعّل حالياً. لم يُنشأ أي طلب.");

  let rawText = "";
  let usedModel: string | null = null;
  try {
    const first = await extractTextWithGemini(imageBase64, mimeType, apiKey);
    rawText = first.text;
    usedModel = first.model;
    const extraBase64 = cleanBase64(body?.imageBase64Extra);
    let extraImage: ParsedImage | null = null;
    if (extraBase64) {
      try {
        extraImage = parseImagePayload(extraBase64, body?.mimeTypeExtra);
      } catch (error) {
        const code = String((error as any)?.message || "invalid_image_input");
        if (code === "image_too_large") return softReview(code, "حجم الصورة الإضافية أكبر من 5 ميجابايت. ارفع صورة أصغر.");
        return softReview("invalid_image_input", "صيغة الصورة الإضافية غير صالحة. استخدم JPG أو PNG أو WEBP.");
      }
      const second = await extractTextWithGemini(extraImage.base64, extraImage.mimeType, apiKey);
      rawText += `\n${second.text}`;
    }
  } catch (error) {
    const safeError = String((error as any)?.message || "unknown").replace(/\s+/g, " ").slice(0, 240);
    console.error("[RAIZEY] Gemini receipt OCR failed", safeError);
    if ((error as any)?.code === "no_visible_text") {
      const rejected = ReceiptJudgeCore.blankResult() as ScanResult;
      rejected.decision = "reject";
      rejected.ocrStatus = "rejected";
      rejected.riskFlags = ["not_a_receipt"];
      rejected.message = "الصورة المرفوعة لا تحتوي على نص واضح لإشعار تحويل. ارفع لقطة شاشة كاملة من تطبيق البنك.";
      rejected.source = "edge";
      rejected.submissionAllowed = false;
      rejected.mimeType = mimeType;
      const scan = await saveScan(admin, userId, hash, bytes, options, rejected, usedModel, "");
      return { ...rejected, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
    }
    const technical = softReview(
      String((error as any)?.message || "").startsWith("timeout:") ? "server_ocr_timeout" : "server_ocr_failed",
      "تعذّر تشغيل الفحص الخادمي مؤقتاً. لم يُنشأ أي طلب؛ أعد المحاولة بعد لحظات.",
    );
    technical.serverErrorCode = safeError;
    technical.mimeType = mimeType;
    const scan = await saveScan(admin, userId, hash, bytes, options, technical, usedModel, "");
    return { ...technical, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
  }

  const judgeOptions = {
    expectedAmount: options.expectedAmount,
    manualRef: options.manualRef,
    expectedAccount: options.expectedAccount,
    ocrSource: "server",
    trustedOcr: true,
  };
  let result = ReceiptJudgeCore.judge(
    ReceiptJudgeCore.buildContext([rawText], judgeOptions),
    judgeOptions,
    ReceiptJudgeCore.blankResult(),
  ) as ScanResult;
  const imageParts = [{ inline_data: { mime_type: mimeType, data: imageBase64 } }];
  const extraBase64 = cleanBase64(body?.imageBase64Extra);
  if (extraBase64) {
    try {
      const extraImage = parseImagePayload(extraBase64, body?.mimeTypeExtra);
      imageParts.push({ inline_data: { mime_type: extraImage.mimeType, data: extraImage.base64 } });
    } catch (_) {
      return softReview("invalid_image_input", "صيغة الصورة الإضافية غير صالحة. استخدم JPG أو PNG أو WEBP.");
    }
  }

  const needsArbitration = !((result.decision === "accept" || result.decision === "review_admin") && result.refVerified && result.amountVerified) && result.decision !== "reject";
  if (needsArbitration) {
    try {
      const arbitration = await structuredPass(imageParts, apiKey);
      const d = arbitration.data || {};
      const lines = [
        d.bank ? `البنك: ${d.bank}` : "",
        d.status ? `الحالة: ${d.status}` : "",
        d.transaction_number ? `رقم العملية: ${d.transaction_number}` : "",
        d.amount ? `المبلغ: ${d.amount} ${d.currency || ""}` : "",
        d.datetime ? `التاريخ: ${d.datetime}` : "",
        d.to_account ? `إلى حساب: ${d.to_account}` : "",
      ].filter(Boolean).join("\n");
      if (lines) {
        rawText += `\n${lines}`;
        result = ReceiptJudgeCore.judge(
          ReceiptJudgeCore.buildContext([rawText], judgeOptions),
          judgeOptions,
          ReceiptJudgeCore.blankResult(),
        ) as ScanResult;
        result.passes = 2;
        result.arbitration = { model: arbitration.model, extracted: d };
      }
    } catch (_) {
      result.riskFlags = (result.riskFlags || []).concat(["arbitration_failed"]);
    }
  }
  result.source = "edge";
  result.model = usedModel;
  result.mimeType = mimeType;
  result.confidence = rawText.trim().length > 20 ? 90 : null;
  result.textLength = rawText.length;
  result.submissionAllowed = result.decision !== "reject";
  const scan = await saveScan(admin, userId, hash, bytes, options, result, usedModel, rawText);
  return { ...result, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders() });
  if (request.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  const token = authToken(request);
  if (!token) return json({ ok: false, error: "auth_required" }, 401);

  let admin: any;
  try {
    admin = buildAdminClient();
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data?.user) return json({ ok: false, error: "auth_required" }, 401);
    const userId = data.user.id;
    const rawBody = await request.text();
    if (!rawBody || rawBody.length > MAX_REQUEST_CHARS) return json({ ok: false, error: "request_too_large" }, 413);
    let body: any;
    try { body = JSON.parse(rawBody); } catch (_) { return json({ ok: false, error: "invalid_json" }, 400); }
    if (!(await enforceRateLimit(admin, userId))) return json({ ok: false, error: "rate_limited" }, 429);
    const result = await processScan(request, admin, userId, body);
    return json({ ok: true, ...result });
  } catch (error) {
    console.error("[RAIZEY] process-receipt error", String((error as any)?.message || error));
    return json({
      ok: false,
      error: "receipt_processing_failed",
      message: "تعذّر إكمال الفحص الخادمي. لم يُنشأ أي طلب؛ أعد المحاولة بعد لحظات.",
    }, 500);
  }
});
