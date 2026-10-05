import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { ReceiptJudgeCore } from "./receipt-judge-core.ts";

// ═════════════════════════════════════════════════════════════════════════
// نماذج Gemini — لا تُكتب أسماء النماذج يدوياً
// ═════════════════════════════════════════════════════════════════════════
// السبب الجذري لفشل الفحص السابق: قائمة أسماء مكتوبة يدوياً (gemini-2.5-*،
// gemini-3.5-*) إمّا أُوقفت من Google أو لا تُدعم لحسابنا، فيفشل كل نموذج
// بدوره (404/400/503/timeout) ثم يعود الفحص برسالة "تعذّر إكمال الفحص".
//
// الإصلاح: نقرأ قائمة النماذج المتاحة فعلياً لهذا المفتاح وقت التشغيل من
//   GET /v1beta/models
// ونشتق منها ترتيب النماذج تلقائياً (stable قبل preview، ثم flash قبل غيرها).
// هذا يجعل الدالة ذاتية الإصلاح عند تغيّر نماذج Google مستقبلاً.
//
// ترتيب مخصص (اختياري): GEMINI_MODEL_ORDER="a,b,c" في Function Secrets.
const GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta";
const GEMINI_MODEL_ORDER_ENV = "GEMINI_MODEL_ORDER";

const GEMINI_REQUEST_TIMEOUT_MS = 25_000;   // مهلة كل محاولة (نموذج واحد)
const GEMINI_JSON_TIMEOUT_MS = 25_000;      // مهلة محاولة الاستخراج المهيكل
const GEMINI_DISCOVERY_TIMEOUT_MS = 8_000;  // مهلة قراءة قائمة النماذج
const GEMINI_TOTAL_BUDGET_MS = 60_000;      // سقف زمني كلي لكل عمليات Gemini
const GEMINI_MAX_MODELS = 4;                // أقصى عدد نماذج تُجرَّب في الفحص
const GEMINI_DISCOVERY_TTL_MS = 60 * 60_000;      // إعادة قراءة القائمة كل ساعة
const GEMINI_DISCOVERY_NEGATIVE_TTL_MS = 5 * 60_000; // فشل القراءة: إعادة بعد 5 دقائق

// نماذج لا تصلح لقراءة الإيصالات (توليد صور/صوت/تضمين/بحث...) — تُستبعد من
// القائمة المشتقة حتى لا نُهدر محاولات على غير المفيد.
const GEMINI_MODEL_DENY = [
  "embedding", "aqa", "imagen", "veo", "tts", "native-audio", "-live",
  "gemma", "codechat", "code-", "robotics", "computer-use", "learnlm",
];

// احتياطي أخير فقط إذا تعذّرت قراءة قائمة النماذج (شبكة/مفتاح غير متاح).
// أسماء مرنة من Google لا أسماء إصدارات مجمّدة. عند الوصول للمفتاح تُستخدم
// القائمة الحقيقية وتُتجاهل هذه.
const FALLBACK_GEMINI_MODELS = [
  "gemini-flash-latest",
  "gemini-flash-lite-latest",
  "gemini-2.5-flash",
];

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const MAX_BASE64_CHARS = Math.ceil(MAX_IMAGE_BYTES * 1.36);
const MAX_REQUEST_CHARS = MAX_BASE64_CHARS * 2 + 160_000;
const SCAN_TTL_MINUTES = 30;
const RATE_WINDOW_MINUTES = 10;
const MAX_SCANS_PER_WINDOW = 12;
const PRODUCTION_ORIGIN = "https://raizey-store-qw.vercel.app";
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
  "أنت مدقّق إشعارات تحويل بنكية سودانية (بنكك، أوكاش، فوري، كاشي...). " +
  "انظر للصورة وأعد JSON فقط بلا أي شرح ولا نص خارج JSON، بهذا الشكل بالضبط: " +
  '{"bank":"","transaction_type":"","amount":"","currency":"","sender_name":"","receiver_name":"",' +
  '"sender_account":"","receiver_account":"","phone":"","transaction_id":"","reference":"",' +
  '"date":"","time":"","status":"","raw_text":""}. ' +
  "قواعد صارمة: " +
  "1) انسخ رقم العملية/المرجع كما هو رقماً رقماً بلا تخمين ولا تصحيح ولا حذف أصفار. " +
  "2) amount = مبلغ التحويل فقط (وليس الرصيد ولا الرسوم ولا الضريبة) بأرقام لاتينية بلا فواصل آلاف. " +
  "3) حوّل الأرقام العربية (٠١٢٣٤٥٦٧٨٩) إلى لاتينية داخل الحقول المهيكلة. " +
  "4) status = نتيجة العملية كما تظهر في الصورة (successful / failed / pending) ولو بالعربية انقلها كما هي. " +
  "5) raw_text = انسخ كل النص الظاهر في الصورة حرفياً (كل سطر كما هو) بلا تلخيص ولا ترجمة. " +
  'إذا لم تكن أي قيمة ظاهرة بوضوح تماماً في الصورة اتركها سلسلة فارغة "". ' +
  "ممنوع الاختراع أو الاستنتاج. أعد JSON فقط.";

const SAFETY_SETTINGS = [
  { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
];

type ScanOptions = {
  expectedAmount: number;
  manualRef: string;
  expectedAccount: string;
  expectedMethodId: string;
};

type ExpectedMethod = {
  id: string;
  name: string | null;
  account_name: string | null;
  account_number: string | null;
  bin_prefixes: string | null;
  bank_key: string | null;
} | null;

type ScanResult = Record<string, any> & {
  riskFlags?: string[];
  extracted?: Record<string, any>;
};

type GeminiAttempt = { model: string; ok?: boolean; error?: string; status?: number | null };
type GeminiDiagnostics = {
  models: string[];
  orderSource: string;
  chosen: string | null;
  attempts: GeminiAttempt[];
};

function env(name: string): string {
  return String(Deno.env.get(name) || "").trim();
}

function json(request: Request, data: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "X-Content-Type-Options": "nosniff",
      ...corsHeaders(request),
      ...extraHeaders,
    },
  });
}

function corsHeaders(request: Request): Record<string, string> {
  const configured = env("RAIZEY_PUBLIC_ORIGIN");
  const origins = configured && configured !== "*"
    ? configured.split(",").map((value) => value.trim()).filter(Boolean)
    : [PRODUCTION_ORIGIN];
  const requestOrigin = request.headers.get("Origin") || "";
  const origin = origins.includes(requestOrigin) ? requestOrigin : origins[0];
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

/**
 * fetch مع مهلة حقيقية: يُلغي الطلب فعلياً عبر AbortController بدل ترك
 * الطلب معلّقاً في الخلفية (السلوك القديم كان يُبقي الطلب حياً ويستهلك
 * مهلة الـEdge Function وأي حصة من المزوّد بلا فائدة).
 */
async function fetchWithTimeout(url: string, init: RequestInit, ms: number, tag: string): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    if ((error as any)?.name === "AbortError") {
      const timeoutError = new Error(`timeout:${tag}`);
      (timeoutError as any).status = 0;
      throw timeoutError;
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function smartReview(flag: string, message?: string): ScanResult {
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

// ═════════════════════════════════════════════════════════════════════════
// اكتشاف النماذج المتاحة فعلياً (بدل التخمين)
// ═════════════════════════════════════════════════════════════════════════
let geminiModelCache: { at: number; models: string[] } | null = null;

function isStableModelName(name: string): boolean {
  return !/(preview|exp|experimental|alpha|beta|latest|deprecated)/i.test(name);
}

function scoreGeminiModel(name: string): number {
  const base = name.replace(/^models\//, "").toLowerCase();
  let score = 0;
  // الاستقرار أولاً (نموذج preview قد يختفي بلا إنذار)
  if (isStableModelName(base)) score += 100;
  // التوازن بين الدقة/السرعة/التكلفة: flash ثم flash-lite ثم pro
  if (/flash/.test(base) && !/lite/.test(base)) score += 50;
  else if (/flash-lite/.test(base)) score += 40;
  else if (/pro/.test(base)) score += 20;
  // إصدار أحدث أفضل
  const v = base.match(/gemini-(\d+)(?:\.(\d+))?/);
  if (v) score += Math.min(90, parseInt(v[1], 10) * 10 + parseInt(v[2] || "0", 10));
  // نماذج توليد الصور/الصوت أبطأ ولا حاجة لها هنا
  if (/(image|audio|tts|vision-only)/.test(base)) score -= 25;
  return score;
}

async function discoverGeminiModels(apiKey: string): Promise<string[]> {
  const now = Date.now();
  if (geminiModelCache) {
    const ttl = geminiModelCache.models.length ? GEMINI_DISCOVERY_TTL_MS : GEMINI_DISCOVERY_NEGATIVE_TTL_MS;
    if (now - geminiModelCache.at < ttl) return geminiModelCache.models;
  }
  // المفتاح يُرسل في ترويسة لا في الرابط حتى لا يظهر في أي سجل URLs.
  const response = await fetchWithTimeout(
    `${GEMINI_API_BASE}/models?pageSize=200`,
    { method: "GET", headers: { "x-goog-api-key": apiKey } },
    GEMINI_DISCOVERY_TIMEOUT_MS,
    "gemini_models",
  );
  if (!response.ok) {
    geminiModelCache = { at: now, models: [] };
    throw new Error(`gemini_models_http_${response.status}`);
  }
  const data = await response.json();
  const list = Array.isArray(data?.models) ? data.models : [];
  const usable = list
    .filter((entry: any) =>
      Array.isArray(entry?.supportedGenerationMethods) &&
      entry.supportedGenerationMethods.includes("generateContent"))
    .map((entry: any) => String(entry?.name || "").replace(/^models\//, ""))
    .filter((name: string) =>
      !!name &&
      name.startsWith("gemini") &&
      !GEMINI_MODEL_DENY.some((denied) => name.toLowerCase().includes(denied)));
  usable.sort((a: string, b: string) => scoreGeminiModel(b) - scoreGeminiModel(a));
  const models = usable.slice(0, GEMINI_MAX_MODELS * 2);
  geminiModelCache = { at: now, models };
  return models;
}

async function resolveGeminiModels(apiKey: string): Promise<{ models: string[]; source: string }> {
  const override = env(GEMINI_MODEL_ORDER_ENV);
  if (override) {
    const models = override.split(",").map((value) => value.trim()).filter(Boolean).slice(0, GEMINI_MAX_MODELS);
    if (models.length) return { models, source: "env" };
  }
  try {
    const discovered = await discoverGeminiModels(apiKey);
    if (discovered.length) return { models: discovered.slice(0, GEMINI_MAX_MODELS), source: "discovery" };
  } catch (error) {
    console.error("[RAIZEY] Gemini model discovery failed:", String((error as any)?.message || error).slice(0, 160));
  }
  return { models: FALLBACK_GEMINI_MODELS.slice(0, GEMINI_MAX_MODELS), source: "fallback" };
}

// ═════════════════════════════════════════════════════════════════════════
// نداء Gemini واحد — مع إعادة محاولة واحدة بلا thinkingConfig عند 400
// ═════════════════════════════════════════════════════════════════════════
async function postGeminiGenerate(
  model: string,
  body: Record<string, any>,
  apiKey: string,
  tag: string,
  timeoutMs: number,
): Promise<any> {
  const url = `${GEMINI_API_BASE}/models/${encodeURIComponent(model)}:generateContent`;
  const attempt = async (payload: Record<string, any>) => {
    const response = await fetchWithTimeout(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify(payload),
    }, timeoutMs, tag);
    if (!response.ok) {
      const detail = (await response.text().catch(() => "")).replace(/\s+/g, " ").slice(0, 220);
      const error = new Error(`gemini_http_${response.status}:${detail}`);
      (error as any).status = response.status;
      (error as any).detail = detail;
      throw error;
    }
    return await response.json();
  };
  try {
    return await attempt(body);
  } catch (error) {
    const status = (error as any)?.status;
    const detail = String((error as any)?.detail || "");
    // بعض النماذج لا تدعم thinkingConfig فتُرجع 400 INVALID_ARGUMENT.
    // نعيد المحاولة مرة واحدة بعد حذفه بدل إسقاط النموذج بالكامل.
    if (status === 400 && body?.generationConfig?.thinkingConfig && /thinking|INVALID_ARGUMENT/i.test(detail)) {
      const retryBody = JSON.parse(JSON.stringify(body));
      delete retryBody.generationConfig.thinkingConfig;
      return await attempt(retryBody);
    }
    throw error;
  }
}

function textFromCandidate(data: any, tag: string): string {
  const candidate = data?.candidates?.[0];
  const parts = candidate?.content?.parts;
  const text = Array.isArray(parts)
    ? parts.map((part: any) => typeof part?.text === "string" ? part.text : "").join("\n").trim()
    : "";
  if (text) return text;
  const reason = candidate?.finishReason || data?.promptFeedback?.blockReason || "no_text";
  const error = new Error(`gemini_empty_response:${reason}`);
  (error as any).status = 200;
  (error as any).tag = tag;
  // STOP/no_text يعني أن النموذج اشتغل فعلاً ولم يجد نصاً → الصورة بلا نص.
  // أي سبب آخر (MAX_TOKENS/SAFETY) عطل قابل لإعادة المحاولة بنموذج آخر.
  if (reason === "STOP" || reason === "no_text") (error as any).code = "no_visible_text";
  throw error;
}

async function callGeminiModel(
  model: string,
  base64Data: string,
  mimeType: string,
  apiKey: string,
  timeoutMs: number,
): Promise<string> {
  const data = await postGeminiGenerate(model, {
    contents: [{
      role: "user",
      parts: [
        { inline_data: { mime_type: mimeType, data: base64Data } },
        { text: OCR_PROMPT },
      ],
    }],
    generationConfig: { temperature: 0, maxOutputTokens: 2048, thinkingConfig: { thinkingBudget: 0 } },
    safetySettings: SAFETY_SETTINGS,
  }, apiKey, "gemini_request", timeoutMs);
  let text = textFromCandidate(data, "gemini_request");
  // بعض النماذج تُصرّ على إرجاع JSON حتى مع طلب نص صريح — نستخرج raw_text.
  if (text.startsWith("{") && text.includes("raw_text")) {
    try {
      const parsed = JSON.parse(text.replace(/^```(?:json)?|```$/g, "").trim());
      if (typeof parsed?.raw_text === "string") text = parsed.raw_text;
    } catch (_) { /* استخدم النص كما هو */ }
  }
  return text;
}

type OcrOutcome = { text: string; model: string; attempts: GeminiAttempt[] };

async function extractTextWithGemini(
  base64Data: string,
  mimeType: string,
  apiKey: string,
  models: string[],
  deadline: number,
): Promise<OcrOutcome> {
  let lastError: any = null;
  const attempts: GeminiAttempt[] = [];
  for (const model of models) {
    const remaining = deadline - Date.now();
    if (remaining < 3000) break; // لا معنى لبدء محاولة لا تكفي لها المهلة
    const timeoutMs = Math.min(GEMINI_REQUEST_TIMEOUT_MS, remaining);
    try {
      const text = await callGeminiModel(model, base64Data, mimeType, apiKey, timeoutMs);
      attempts.push({ model, ok: true });
      return { text, model, attempts };
    } catch (error) {
      lastError = error;
      const message = String((error as any)?.message || "");
      attempts.push({ model, error: message.slice(0, 200), status: (error as any)?.status ?? null });
      // أخطاء قاتلة لا يفيد معها تجربة نموذج آخر
      if ((error as any)?.code === "no_visible_text") {
        (error as any).attempts = attempts;
        throw error;
      }
      if ([401, 403, 429].includes((error as any)?.status)) {
        (error as any).attempts = attempts;
        throw error;
      }
      // timeout / 400 / 404 / 5xx → جرّب النموذج التالي
      console.error(`[RAIZEY] Gemini model ${model} failed, trying next:`, message.slice(0, 160));
    }
  }
  if (!lastError) {
    lastError = new Error("timeout:gemini_budget");
    (lastError as any).status = 0;
  }
  (lastError as any).attempts = attempts;
  throw lastError;
}

async function callGeminiJson(model: string, parts: any[], apiKey: string, timeoutMs: number) {
  const data = await postGeminiGenerate(model, {
    contents: [{ role: "user", parts: parts.concat([{ text: JSON_PROMPT }]) }],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: 1024,
      responseMimeType: "application/json",
      thinkingConfig: { thinkingBudget: 0 },
    },
  }, apiKey, "gemini_json", timeoutMs);
  const candidate = data?.candidates?.[0];
  const partsOut = candidate?.content?.parts;
  const text = Array.isArray(partsOut)
    ? partsOut.map((part: any) => part?.text || "").join("").replace(/^```(?:json)?|```$/g, "").trim()
    : "";
  if (!text) throw new Error("gemini_json_empty");
  return JSON.parse(text);
}

async function structuredPass(
  parts: any[],
  apiKey: string,
  models: string[],
  deadline: number,
): Promise<{ data: Record<string, any>; model: string; attempts: GeminiAttempt[] }> {
  let lastError: any = null;
  const attempts: GeminiAttempt[] = [];
  for (const model of models) {
    const remaining = deadline - Date.now();
    if (remaining < 3000) break;
    const timeoutMs = Math.min(GEMINI_JSON_TIMEOUT_MS, remaining);
    try {
      const data = await callGeminiJson(model, parts, apiKey, timeoutMs);
      attempts.push({ model, ok: true });
      return { data, model, attempts };
    } catch (error) {
      lastError = error;
      attempts.push({ model, error: String((error as any)?.message || "").slice(0, 160), status: (error as any)?.status ?? null });
    }
  }
  throw lastError || new Error("gemini_json_failed");
}

/**
 * يحوّل حقول الاستخراج المهيكل إلى أسطر بنفس تسميات receipt-judge-core
 * حتى تُدمج في نص الفحص بنفس صيغة إشعار حقيقي — بلا تغيير في منطق الحكم.
 */
function structuredFieldsToLines(data: Record<string, any>): string[] {
  const value = (key: string): string => {
    const raw = data?.[key];
    if (raw === null || raw === undefined) return "";
    return String(raw).trim().slice(0, 120);
  };
  const lines: string[] = [];
  const bank = value("bank");
  if (bank) lines.push(`البنك: ${bank}`);
  const type = value("transaction_type");
  if (type) lines.push(`نوع العملية: ${type}`);
  const txId = value("transaction_id");
  if (txId) lines.push(`رقم العملية: ${txId}`);
  const reference = value("reference");
  if (reference && reference !== txId) lines.push(`المرجع: ${reference}`);
  const amount = value("amount");
  if (amount) lines.push(`المبلغ: ${amount} ${value("currency")}`.trim());
  const status = value("status");
  if (status) lines.push(`الحالة: ${status}`);
  const datetime = [value("date"), value("time")].filter(Boolean).join(" ");
  if (datetime) lines.push(`التاريخ: ${datetime}`);
  const toAccount = value("receiver_account");
  if (toAccount) lines.push(`الى حساب: ${toAccount}`);
  const fromAccount = value("sender_account");
  if (fromAccount) lines.push(`من حساب: ${fromAccount}`);
  const sender = value("sender_name");
  if (sender) lines.push(`اسم المرسل: ${sender}`);
  const receiver = value("receiver_name");
  if (receiver) lines.push(`اسم المستفيد: ${receiver}`);
  const phone = value("phone");
  if (phone) lines.push(`رقم الهاتف: ${phone}`);
  return lines;
}

function sanitizeStructuredFields(data: Record<string, any>): Record<string, string> {
  const out: Record<string, string> = {};
  const keys = [
    "bank", "transaction_type", "amount", "currency", "sender_name", "receiver_name",
    "sender_account", "receiver_account", "phone", "transaction_id", "reference",
    "date", "time", "status",
  ];
  for (const key of keys) {
    const raw = data?.[key];
    if (raw === null || raw === undefined || raw === "") continue;
    out[key] = String(raw).trim().slice(0, 200);
  }
  return out;
}

// ═════════════════════════════════════════════════════════════════════════
// Supabase + الحفظ
// ═════════════════════════════════════════════════════════════════════════
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

async function saveScan(
  admin: any,
  userId: string,
  hash: string,
  bytes: Uint8Array,
  options: ScanOptions,
  result: ScanResult,
  diagnostics: GeminiDiagnostics,
  rawText: string,
  expectedMethod?: ExpectedMethod,
) {
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
      expected_method_id: expectedMethod ? expectedMethod.id : null,
      expected_method_name: expectedMethod ? expectedMethod.name : null,
      engine_source: "supabase_edge",
      engine_version: result.version || 4,
      model: diagnostics.chosen || null,
      model_order_source: diagnostics.orderSource,
      models_tried: diagnostics.attempts,
      gemini_models: diagnostics.models,
      extracted_fields: result.extractedFields || null,
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

// ═════════════════════════════════════════════════════════════════════════
// مسار الفحص
// ═════════════════════════════════════════════════════════════════════════
async function processScan(request: Request, admin: any, userId: string, body: any): Promise<ScanResult> {
  let image: ParsedImage;
  try {
    image = parseImagePayload(body?.imageBase64, body?.mimeType);
  } catch (error) {
    const code = String((error as any)?.message || "invalid_image_input");
    if (code === "image_too_large") return smartReview(code, "حجم الصورة أكبر من 5 ميجابايت. ارفع صورة JPG أو PNG أو WEBP أصغر.");
    if (code === "invalid_base64") return smartReview(code, "تعذّر قراءة الصورة المرسلة. أعد اختيار الملف.");
    return smartReview("invalid_image_input", "صيغة الصورة غير صالحة. ارفع JPG أو PNG أو WEBP.");
  }
  const imageBase64 = image.base64;
  const mimeType = image.mimeType;
  const bytes = image.bytes;
  const hash = await sha256Hex(bytes);
  const options: ScanOptions = {
    expectedAmount: Math.max(0, Number(body?.expectedAmount) || 0),
    manualRef: String(body?.manualRef || "").slice(0, 80),
    expectedAccount: String(body?.expectedAccount || "").slice(0, 80),
    expectedMethodId: String(body?.expectedMethodId || "").slice(0, 40),
  };
  // ── المهمة 35: جلب بيانات الوسيلة المختارة من السيرفر ──
  // لا تُؤخذ بيانات التحقق (BIN/الاسم) من العميل أبداً — تُقرأ من قاعدة
  // البيانات عبر service_role. غياب الأعمدة الجديدة (قبل ترحيل SQL) لا
  // يكسر الفحص: تُتجاهل الطبقة الجديدة بهدوء.
  let expectedMethod: ExpectedMethod = null;
  if (/^[0-9a-f-]{36}$/i.test(options.expectedMethodId)) {
    try {
      const { data: m } = await admin
        .from("payment_methods")
        .select("*")
        .eq("id", options.expectedMethodId)
        .eq("is_active", true)
        .maybeSingle();
      if (m) {
        expectedMethod = {
          id: String(m.id),
          name: m.name ?? null,
          account_name: m.account_name ?? null,
          account_number: m.account_number ?? null,
          bin_prefixes: m.bin_prefixes ?? null,
          bank_key: m.bank_key ?? null,
        };
      }
    } catch (_) { /* بدون بيانات وسيلة — الفحص يكمل بالمنطق القديم */ }
  }
  const apiKey = env("GEMINI_API_KEY");
  if (!apiKey) return smartReview("gemini_not_configured", "محرك الفحص الخادمي غير مُفعّل حالياً. لم يُنشأ أي طلب.");

  const diagnostics: GeminiDiagnostics = { models: [], orderSource: "unknown", chosen: null, attempts: [] };
  const resolved = await resolveGeminiModels(apiKey);
  diagnostics.models = resolved.models;
  diagnostics.orderSource = resolved.source;
  const deadline = Date.now() + GEMINI_TOTAL_BUDGET_MS;

  let rawText = "";
  try {
    const first = await extractTextWithGemini(imageBase64, mimeType, apiKey, resolved.models, deadline);
    diagnostics.chosen = first.model;
    diagnostics.attempts = first.attempts.slice();
    rawText = first.text;
    const extraBase64 = cleanBase64(body?.imageBase64Extra);
    if (extraBase64) {
      let extraImage: ParsedImage;
      try {
        extraImage = parseImagePayload(extraBase64, body?.mimeTypeExtra);
      } catch (error) {
        const code = String((error as any)?.message || "invalid_image_input");
        if (code === "image_too_large") return smartReview(code, "حجم الصورة الإضافية أكبر من 5 ميجابايت. ارفع صورة أصغر.");
        return smartReview("invalid_image_input", "صيغة الصورة الإضافية غير صالحة. استخدم JPG أو PNG أو WEBP.");
      }
      const second = await extractTextWithGemini(extraImage.base64, extraImage.mimeType, apiKey, resolved.models, deadline);
      rawText += `\n${second.text}`;
    }
  } catch (error) {
    const safeError = String((error as any)?.message || "unknown").replace(/\s+/g, " ").slice(0, 240);
    console.error("[RAIZEY] Gemini receipt OCR failed", safeError);
    if (Array.isArray((error as any)?.attempts)) diagnostics.attempts = (error as any).attempts;
    if ((error as any)?.code === "no_visible_text") {
      const rejected = ReceiptJudgeCore.blankResult() as ScanResult;
      rejected.decision = "reject";
      rejected.ocrStatus = "rejected";
      rejected.riskFlags = ["not_a_receipt"];
      rejected.message = "الصورة المرفوعة لا تحتوي على نص واضح لإشعار تحويل. ارفع لقطة شاشة كاملة من تطبيق البنك.";
      rejected.source = "edge";
      rejected.submissionAllowed = false;
      rejected.mimeType = mimeType;
      const scan = await saveScan(admin, userId, hash, bytes, options, rejected, diagnostics, "");
      return { ...rejected, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
    }
    const technical = smartReview(
      String((error as any)?.message || "").startsWith("timeout:") ? "server_ocr_timeout" : "server_ocr_failed",
      "تعذّر تشغيل الفحص الخادمي مؤقتاً. لم يُنشأ أي طلب؛ أعد المحاولة بعد لحظات.",
    );
    technical.serverErrorCode = safeError;
    technical.mimeType = mimeType;
    // للتشخيص: يُحفظ سبب الفشل التقني في ocr_data ليراه الأدمن عند المراجعة
    technical.extracted = {
      ...(technical.extracted || {}),
      server_error_code: safeError,
      gemini_attempts: diagnostics.attempts,
    };
    const scan = await saveScan(admin, userId, hash, bytes, options, technical, diagnostics, "");
    return { ...technical, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
  }

  const judgeOptions = {
    expectedAmount: options.expectedAmount,
    manualRef: options.manualRef,
    expectedAccount: options.expectedAccount,
    expectedMethod,
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
      return smartReview("invalid_image_input", "صيغة الصورة الإضافية غير صالحة. استخدم JPG أو PNG أو WEBP.");
    }
  }

  // المهمة 37 — إصلاح فجوة التحكيم:
  // قرارات الرفض بسبب عدم تطابق المبلغ تستحق رأياً ثانياً من الـ JSON المنظم
  // (قد تكون قراءة الـ OCR للمبلغ خاطئة)، لكن فقط amount_mismatch —
  // وليس ref_conflict أو معاملة فاشلة أو صورة ليست إيصالاً.
  const riskFlags = result.riskFlags || [];
  const isAmountMismatchReject =
    result.decision === "reject" &&
    riskFlags.includes("amount_mismatch") &&
    !riskFlags.includes("ref_conflict") &&
    !riskFlags.includes("not_a_receipt") &&
    !riskFlags.some((f) => String(f).startsWith("failed_transaction"));

  // ── الاستخراج المهيكل + التحكيم الثاني ──
  // يُشغَّل عندما لا يصل الحكم الحتمي إلى نتيجة واثقة (قبول تلقائي بمرجع
  // ومبلغ مؤكدين)، أو على رفض amount_mismatch (المهمة 37). حقوله تُدمج في
  // نص الفحص بأسطر بنفس تسميات receipt-judge-core، لذا لا يتغيّر منطق
  // القرار — يتحسّن فقط ما يقرأه من بيانات.
  const needsArbitration =
    !((result.decision === "accept" || result.decision === "review_admin") &&
      result.refVerified && result.amountVerified) &&
    (result.decision !== "reject" || isAmountMismatchReject);
  if (needsArbitration) {
    try {
      const arbitration = await structuredPass(imageParts, apiKey, resolved.models, deadline);
      const d = arbitration.data || {};
      result.extractedFields = sanitizeStructuredFields(d);
      const lines = structuredFieldsToLines(d);
      if (lines.length) {
        rawText += `\n${lines.join("\n")}`;
        result = ReceiptJudgeCore.judge(
          ReceiptJudgeCore.buildContext([rawText], judgeOptions),
          judgeOptions,
          ReceiptJudgeCore.blankResult(),
        ) as ScanResult;
        result.passes = 2;
        result.extractedFields = sanitizeStructuredFields(d);
        result.arbitration = { model: arbitration.model, extracted: result.extractedFields };
        // علامة تشخيصية: التحكيم طُبّق على قرار رفض (المهمة 37)
        if (isAmountMismatchReject) {
          result.riskFlags = (result.riskFlags || []).concat(["arbitration_on_reject"]);
        }
      }
    } catch (_) {
      result.riskFlags = (result.riskFlags || []).concat(["arbitration_failed"]);
    }
  }
  result.source = "edge";
  result.model = diagnostics.chosen;
  result.mimeType = mimeType;
  result.confidence = rawText.trim().length > 20 ? 90 : null;
  result.textLength = rawText.length;
  result.submissionAllowed = result.decision !== "reject";
  const scan = await saveScan(admin, userId, hash, bytes, options, result, diagnostics, rawText, expectedMethod);
  return { ...result, scanId: scan.id, receiptHash: hash, expiresAt: scan.expires_at };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(request) });
  if (request.method !== "POST") return json(request, { ok: false, error: "method_not_allowed" }, 405);

  const token = authToken(request);
  if (!token) return json(request, { ok: false, error: "auth_required" }, 401);

  let admin: any;
  try {
    admin = buildAdminClient();
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data?.user) return json(request, { ok: false, error: "auth_required" }, 401);
    const userId = data.user.id;
    const rawBody = await request.text();
    if (!rawBody || rawBody.length > MAX_REQUEST_CHARS) return json(request, { ok: false, error: "request_too_large" }, 413);
    let body: any;
    try { body = JSON.parse(rawBody); } catch (_) { return json(request, { ok: false, error: "invalid_json" }, 400); }
    if (!(await enforceRateLimit(admin, userId))) {
      return json(request, { ok: false, error: "rate_limited" }, 429, { "Retry-After": "600" });
    }
    const result = await processScan(request, admin, userId, body);
    return json(request, { ok: true, ...result });
  } catch (error) {
    console.error("[RAIZEY] process-receipt error", String((error as any)?.message || error));
    return json(request, {
      ok: false,
      error: "receipt_processing_failed",
      message: "تعذّر إكمال الفحص الخادمي. لم يُنشأ أي طلب؛ أعد المحاولة بعد لحظات.",
    }, 500);
  }
});
