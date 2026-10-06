/*
 * RAIZEY STORE — اختبار دالة process-receipt (Edge Function) بلا شبكة
 * =====================================================================
 * يحمّل supabase/functions/process-receipt/index.ts بعد استبدال الاعتمادات
 * الخارجية (Supabase + Gemini) ببدائل مراقِبة، ثم يختبر:
 *   - اكتشاف النماذج المتاحة فعلياً عبر GET /v1beta/models
 *   - ترتيب النماذج (stable قبل preview) وتجاهل النماذج غير الصالحة
 *   - التبديل بين النماذج عند 404/503/400
 *   - إعادة المحاولة بلا thinkingConfig عند 400 INVALID_ARGUMENT
 *   - انتهاء المهلة عبر AbortController حقيقي
 *   - ترتيب flash-lite أولاً (قياس: ~55% توكنات أقل بنفس الدقة)
 *   - إعادة المحاولة عند 429/503 بدل الفشل الفوري
 *   - إعادة استخدام فحص سابق لنفس البصمة والمدخلات (بلا استدعاء AI)
 *   - فلاتر IS NULL في منع التكرار (eq.null يُرجع 400 من PostgREST)
 *   - تخزين رقم العملية الذي وثّقه القرار في tx_ref_ocr (لا التاريخ)
 *   - فشل كل النماذج → review (والدالة لا تنهار)
 *   - صورة بلا نص → reject not_a_receipt
 *   - JWT مفقود/غير صالح → 401
 *   - تجاوز الحد → 429
 *   - عدم تسريب مفتاح Gemini في أي URL
 *
 * التشغيل:  bun scripts/test_process_receipt_edge.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const indexPath = path.join(root, "supabase/functions/process-receipt/index.ts");
const judgePath = path.join(root, "supabase/functions/process-receipt/receipt-judge-core.ts");

const API_KEY = "TEST_GEMINI_KEY_DO_NOT_LEAK";
const GOOD_TOKEN = "good-user-jwt";

let passed = 0;
const failures = [];
function check(label, actual, expected) {
  if (actual === expected) {
    passed++;
    console.log(`PASS  ${label}  → ${actual}`);
    return;
  }
  failures.push(`${label}: expected ${expected}, got ${actual}`);
  console.log(`FAIL  ${label}  → expected ${expected}, got ${actual}`);
}

// ── تجهيز الوحدة: استبدال الاعتمادات الخارجية ──
function buildModule() {
  const indexSrc = fs.readFileSync(indexPath, "utf8");
  const judgeSrc = fs
    .readFileSync(judgePath, "utf8")
    .replace(/export\s*\{\s*ReceiptJudgeCore\s*\};?\s*$/m, "");
  return indexSrc
    .replace(/^import\s+"jsr:[^"]+";\s*$/m, "")
    .replace(
      /^import\s+\{\s*createClient\s*\}\s+from\s+"npm:@supabase\/supabase-js@2";\s*$/m,
      "const createClient = (...args) => globalThis.__raizeyCreateClient(...args);",
    )
    .replace(
      /^import\s+\{\s*ReceiptJudgeCore\s*\}\s+from\s+"\.\/receipt-judge-core\.ts";\s*$/m,
      judgeSrc,
    );
}

const tmpDir = path.join(root, "scripts/.tmp");
fs.mkdirSync(tmpDir, { recursive: true });
const tmpFile = path.join(tmpDir, "process-receipt.generated.ts");
fs.writeFileSync(tmpFile, buildModule(), "utf8");

const envState = {};
const fetchedUrls = [];
let fetchImpl = async () => { throw new Error("fetch_not_configured"); };

globalThis.Deno = {
  env: { get: (name) => envState[name] },
  serve: (handler) => { globalThis.__servedHandler = handler; },
};
globalThis.fetch = (...args) => { fetchedUrls.push(String(args[0])); return fetchImpl(...args); };

// ── بديل Supabase مراقِب ──
function createAdminMock(state) {
  function from(table) {
    const selectResult = table === "payment_methods"
      ? { data: state.paymentMethod || null, error: null }
      : { count: state.scanCount || 0, data: null, error: null };
    // تُسجَّل كل الفلاتر حتى نتحقق من *شكل* استعلام منع التكرار: PostgREST
    // يردّ 400 على eq.null في الأعمدة الرقمية، فيجب أن يكون IS NULL صريحاً.
    const record = (op) => (column, value) => {
      state.filters.push({ op, table, column, value });
      return q;
    };
    const q = {
      select: () => q,
      eq: record("eq"),
      gte: record("gte"),
      gt: record("gt"),
      is: record("is"),
      order: () => q,
      limit: () => q,
      maybeSingle: async () => {
        // استعلام إعادة استخدام فحص سابق (findReusableScan) يستخدم maybeSingle
        if (table === "receipt_scan_results" && state.reusableScan) {
          return { data: state.reusableScan, error: null };
        }
        return selectResult;
      },
      single: async () => selectResult,
      then: (resolve, reject) => Promise.resolve(selectResult).then(resolve, reject),
      insert: (payload) => {
        state.inserted.push({ table, payload });
        const inserted = { data: { id: "scan-uuid-1", receipt_hash: payload.receipt_hash, decision: payload.decision, ocr_status: payload.ocr_status, submission_allowed: payload.submission_allowed, expires_at: payload.expires_at }, error: null };
        const iq = {
          select: () => iq,
          eq: () => iq,
          maybeSingle: async () => inserted,
          single: async () => inserted,
          then: (resolve, reject) => Promise.resolve(inserted).then(resolve, reject),
        };
        return iq;
      },
    };
    return q;
  }
  return {
    auth: { getUser: async (token) => (token === GOOD_TOKEN ? { data: { user: { id: "user-1" } }, error: null } : { data: { user: null }, error: { message: "invalid_jwt" } }) },
    from,
  };
}

function makeRequest(body, token) {
  const headers = { "Content-Type": "application/json", Origin: "https://raizey-store-qw.vercel.app" };
  if (token !== null && token !== undefined) headers.Authorization = `Bearer ${token}`;
  return new Request("https://rglbfizqolrenwfsndyv.supabase.co/functions/v1/process-receipt", {
    method: "POST", headers, body: JSON.stringify(body),
  });
}

// PNG/TIFF magic bytes ناقصة لكن كافية لاجتياز التحقق (base64 لمحتوى ثنائي)
const IMAGE_BASE64 = Buffer.from("raizey-receipt-image-bytes").toString("base64");

function validBankakText() {
  const now = new Date();
  const stamp = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")} ${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  return [
    "بنكك", "تحويلات", "تمت العملية بنجاح",
    "رقم العملية: FT250719123456",
    "المبلغ: 125,000.00 SDG",
    "من حساب: 1234567890",
    "الى حساب: 2050123456789012",
    "اسم المرسل اليه: محمد الصادق",
    `التاريخ و الزمن: ${stamp}`,
    "الرصيد المتاح: 500,000.00 SDG",
  ].join("\n");
}

// usageMetadata مرفقة بنفس شكل رد Google الفعلي، حتى يُختبر *حساب* الاستهلاك
// (ocr_data.tokens) لا مجرد وجود الحقل.
function geminiTextResponse(text) {
  return {
    candidates: [{ content: { parts: [{ text }] }, finishReason: "STOP" }],
    usageMetadata: {
      promptTokenCount: 1099,
      candidatesTokenCount: 200,
      thoughtsTokenCount: 0,
      totalTokenCount: 1299,
      promptTokensDetails: [
        { modality: "TEXT", tokenCount: 10 },
        { modality: "IMAGE", tokenCount: 1089 },
      ],
    },
  };
}
function geminiEmptyResponse() {
  return { candidates: [{ content: { parts: [] }, finishReason: "STOP" }] };
}
function httpResponse(status, body) {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), { status });
}

const MODEL_LIST_BODY = {
  models: [
    { name: "models/gemini-3.1-flash-lite", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-3.5-flash", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-2.5-flash", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-4.0-flash-preview", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-embedding-001", supportedGenerationMethods: ["embedContent"] },
    { name: "models/imagen-3.0-generate", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemma-3-27b-it", supportedGenerationMethods: ["generateContent"] },
  ],
};

/** ينفّذ فحصاً واحداً ببديل Supabase/Gemini مخصّص ويعيد النتيجة والحالة. */
async function runScan({ body, token = GOOD_TOKEN, env = {}, scanCount = 0, paymentMethod = null, reusableScan = null, fetchHandler, expectStatus }) {
  const state = { inserted: [], filters: [], scanCount, paymentMethod, reusableScan };
  globalThis.__raizeyCreateClient = () => createAdminMock(state);
  Object.assign(envState, {
    GEMINI_API_KEY: API_KEY,
    GEMINI_MODEL_ORDER: "",
    SUPABASE_URL: "https://rglbfizqolrenwfsndyv.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
    ...env,
  });
  fetchedUrls.length = 0;
  fetchImpl = fetchHandler;
  const handler = globalThis.__servedHandler;
  if (!handler) throw new Error("handler_not_registered");
  const response = await handler(makeRequest(body, token));
  const status = response.status;
  let json = null;
  try { json = await response.json(); } catch (_) {}
  if (expectStatus !== undefined) check("http status", status, expectStatus);
  return { status, json, state };
}

const baseBody = {
  imageBase64: IMAGE_BASE64,
  mimeType: "image/png",
  expectedAmount: 125000,
  manualRef: "FT250719123456",
  expectedAccount: "2050123456789012",
  expectedMethodId: null,
};

await import(pathToFileURL(tmpFile).href);

console.log("\n── اكتشاف النماذج والترتيب ──");
{
  const generatedModels = [];
  const result = await runScan({
    body: baseBody,
    fetchHandler: async (url, init) => {
      const href = String(url);
      if (href.includes("/models?")) return httpResponse(200, MODEL_LIST_BODY);
      const model = href.match(/\/models\/([^:]+):generateContent/)[1];
      generatedModels.push(model);
      return httpResponse(200, geminiTextResponse(validBankakText()));
    },
  });
  check("result ok", result.json.ok, true);
  check("decision accept", result.json.decision, "accept");
  // القياس يحكم: flash-lite يقرأ نفس الإيصال بنفس الدقة بـ~55% استهلاكاً أقل
  // (بلا توكنات تفكير)، فهو الخيار الأول — وflash العادي احتياط.
  check("chosen model is the cheapest accurate class (flash-lite)", generatedModels[0], "gemini-3.1-flash-lite");
  const ocrData = result.state.inserted[0].payload.ocr_data;
  check("model order source", ocrData.model_order_source, "discovery");
  check(
    "embedding/image/gemma excluded + flash-lite ranked first",
    ocrData.gemini_models.join("|"),
    "gemini-3.1-flash-lite|gemini-3.5-flash|gemini-2.5-flash|gemini-4.0-flash-preview",
  );
  check("preview ranked below stable", ocrData.gemini_models.indexOf("gemini-3.5-flash") < ocrData.gemini_models.indexOf("gemini-4.0-flash-preview"), true);
  check("provider detected", result.json.provider, "bankak");
  check("api key not in any URL", fetchedUrls.some((u) => u.includes(API_KEY)), false);
  check("submission allowed", result.state.inserted[0].payload.submission_allowed, true);
  // عقد p_ocr_excerpt: checkout.html/checkout-v2.html يقرآن scanResult.rawExcerpt.
  check("rawExcerpt returned", typeof result.json.rawExcerpt === "string", true);
  check("rawExcerpt within client cap", result.json.rawExcerpt.length <= 300, true);
  check("rawExcerpt carries OCR text", result.json.rawExcerpt.includes("FT250719123456"), true);
  // استهلاك الإيصال يُسجَّل فعلياً كي يمكن إثبات خفض التوكنات في الإنتاج.
  check("token usage recorded per receipt", ocrData.tokens && ocrData.tokens.total, 1299);
  check("image tokens recorded (main cost driver)", ocrData.tokens.image, 1089);
}

console.log("\n── rawExcerpt: بلا نص ⇒ null (لا كسر للعقد) ──");
{
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async () => httpResponse(200, geminiEmptyResponse()),
  });
  check("empty OCR → rawExcerpt null", result.json.rawExcerpt, null);
  check("rawExcerpt (empty case) stored in ocr_data as empty excerpt", result.state.inserted[0].payload.ocr_data.raw_text_excerpt, "");
}

console.log("\n── التهدئة: النموذج الميت/المزدحم لا يتصدّر الطلب التالي ──");
{
  // قياس حقيقي: قائمة /v1beta/models تُدرج gemini-2.5-flash بينما نداوله يُرجع
  // 404 "no longer available to new users"، فكان يستهلك محاولة من محاولاتنا
  // المحدودة. الفحص: بعد فشل النموذج الأعلى ترتيباً، يجب أن يبدأ الطلب التالي
  // بالنموذج السليم مباشرة (مع بقاء الميت متاحاً كاحتياط أخير).
  // نستخدم نفس قائمة النماذج المخزّنة مؤقتاً من فحص الاكتشاف أعلاه، ونحاكي
  // بالضبط ما شوهد في الإنتاج: الخيار الأول مزدحم (503) والثاني ميت (404).
  // الترتيب المرتّب: flash-lite ثم flash ثم flash ثم preview.
  const callOrder = [];
  const handler = async (url) => {
    const href = String(url);
    if (href.includes("/models?")) return httpResponse(200, MODEL_LIST_BODY);
    const model = href.match(/\/models\/([^:]+):generateContent/)[1];
    callOrder.push(model);
    if (model === "gemini-3.1-flash-lite") {
      return httpResponse(503, { error: { message: "high demand", status: "UNAVAILABLE" } });
    }
    if (model === "gemini-3.5-flash") {
      return httpResponse(404, { error: { message: "This model is no longer available to new users" } });
    }
    return httpResponse(200, geminiTextResponse(validBankakText()));
  };

  const first = await runScan({ body: baseBody, fetchHandler: handler });
  check(
    "cooldown: first request retries 503 once, skips 404, then succeeds",
    callOrder.join(","),
    "gemini-3.1-flash-lite,gemini-3.1-flash-lite,gemini-3.5-flash,gemini-2.5-flash",
  );
  check("cooldown: first request still succeeds on the fallback", first.json.decision, "accept");

  callOrder.length = 0;
  const second = await runScan({ body: baseBody, fetchHandler: handler });
  check("cooldown: second request skips both cooled models", callOrder[0], "gemini-2.5-flash");
  check("cooldown: second request still accepted", second.json.decision, "accept");
  const listedModels = second.state.inserted[0].payload.ocr_data.gemini_models;
  check(
    "cooldown: cooled models kept but demoted to last resort",
    listedModels.indexOf("gemini-2.5-flash") < listedModels.indexOf("gemini-3.1-flash-lite") &&
      listedModels.indexOf("gemini-2.5-flash") < listedModels.indexOf("gemini-3.5-flash"),
    true,
  );
}

console.log("\n── التبديل بين النماذج (404 → 503 → نجاح) ──");
{
  const seen = [];
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-dead-1,gemini-dead-2,gemini-alive" },
    fetchHandler: async (url) => {
      const model = String(url).match(/\/models\/([^:]+):generateContent/)[1];
      seen.push(model);
      if (model === "gemini-dead-1") return httpResponse(404, { error: { message: "model not found" } });
      if (model === "gemini-dead-2") return httpResponse(503, { error: { message: "unavailable" } });
      return httpResponse(200, geminiTextResponse(validBankakText()));
    },
  });
  // 503 يُعاد مرة واحدة على نفس النموذج، و404 لا يُعاد (عطل دائم).
  check("503 retried once on the same model", seen.join(","), "gemini-dead-1,gemini-dead-2,gemini-dead-2,gemini-alive");
  check("404 is not retried", seen.filter((m) => m === "gemini-dead-1").length, 1);
  check("decision accept after failover", result.json.decision, "accept");
  const attempts = result.state.inserted[0].payload.ocr_data.models_tried;
  check("attempt diagnostics recorded", attempts.length, 4);
  check("failed attempts carry status", attempts[0].status, 404);
  check("order source is env", result.state.inserted[0].payload.ocr_data.model_order_source, "env");
}

console.log("\n── 400 INVALID_ARGUMENT يُعاد بلا thinkingConfig ──");
{
  const bodies = [];
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-picky" },
    fetchHandler: async (url, init) => {
      const payload = JSON.parse(init.body);
      bodies.push(payload);
      if (payload.generationConfig && payload.generationConfig.thinkingConfig) {
        return httpResponse(400, { error: { status: "INVALID_ARGUMENT", message: "thinkingConfig not supported" } });
      }
      return httpResponse(200, geminiTextResponse(validBankakText()));
    },
  });
  check("first attempt sent thinkingConfig", !!(bodies[0] && bodies[0].generationConfig.thinkingConfig), true);
  check("retry dropped thinkingConfig", bodies[1] && bodies[1].generationConfig.thinkingConfig === undefined, true);
  check("decision accept after retry", result.json.decision, "accept");
}

console.log("\n── انتهاء المهلة عبر AbortController حقيقي ──");
{
  let capturedSignal = null;
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-hangs" },
    fetchHandler: async (url, init) => {
      capturedSignal = init.signal;
      // طلب لا ينتهي أبداً: يبقى معلقاً حتى يُلغى من withTimeout.
      return new Promise((resolve, reject) => {
        init.signal.addEventListener("abort", () => reject(Object.assign(new Error("aborted"), { name: "AbortError" })));
      });
    },
  });
  check("request signal aborted by timeout", capturedSignal && capturedSignal.aborted, true);
  check("timeout → review (no crash)", result.json.decision, "review");
  check("timeout flag", result.json.riskFlags.includes("server_ocr_timeout"), true);
  // مسار متدهور مقصود: العميل يكمل طلبه ويراجعه الأدمن يدوياً، لكن لا يُوسم
  // الفحص أبداً كـ passed حتى لا يُقبل دفع تلقائياً بلا قراءة فعلية.
  check("timeout ocr_status is needs_review", result.state.inserted[0].payload.ocr_status, "needs_review");
  check("timeout decision stored as review", result.state.inserted[0].payload.decision, "review");
}

console.log("\n── فشل كل النماذج → review بلا انهيار ──");
{
  let calls = 0;
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-a,gemini-b" },
    fetchHandler: async () => { calls++; return httpResponse(503, { error: { message: "temporarily unavailable" } }); },
  });
  check("each failing model retried once (2 models × 2 attempts)", calls, 4);
  check("all models failing → ok:true", result.json.ok, true);
  check("all models failing → review", result.json.decision, "review");
  check("all models failing → server_ocr_failed", result.json.riskFlags.includes("server_ocr_failed"), true);
  check("diagnostic saved", typeof result.state.inserted[0].payload.ocr_data.server_error_code === "string", true);
}

console.log("\n── 429 حصة: إعادة محاولة بدل الفشل الفوري ──");
{
  let calls = 0;
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-quota" },
    fetchHandler: async () => {
      calls++;
      if (calls === 1) {
        return httpResponse(429, { error: { message: "You exceeded your current quota", status: "RESOURCE_EXHAUSTED" } });
      }
      return httpResponse(200, geminiTextResponse(validBankakText()));
    },
  });
  // قبل هذا التغيير كان 429 يُعامَل كخطأ قاتل فيسقط الإيصال إلى «مراجعة» فوراً.
  check("429 retried once then succeeded", calls, 2);
  check("429 retry produced accept", result.json.decision, "accept");
}

console.log("\n── منع إعادة الفحص (نفس البصمة والمدخلات) ──");
{
  const snapshot = {
    version: 4, decision: "accept", ocrStatus: "passed", message: "تم التحقق من الإيصال بنجاح",
    provider: "bankak", providerName: "بنكك (بنك الخرطوم)", amountVerified: true, refVerified: true,
    confidence: 90, passes: 1, riskFlags: [], textLength: 240, source: "edge",
    extracted: { txRef: "FT250719123456", amount: 125000 }, submissionAllowed: true,
    rawExcerpt: "بنكك\nرقم العملية: FT250719123456\nالمبلغ: 125,000.00 SDG",
  };
  const reusableRow = (overrides = {}) => ({
    id: "scan-reused-7",
    receipt_hash: "a".repeat(64),
    expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
    risk_flags: [],
    ocr_data: { expected_method_id: null, result_snapshot: snapshot },
    ...overrides,
  });

  const reuse = await runScan({
    body: baseBody,
    reusableScan: reusableRow(),
    fetchHandler: async () => httpResponse(500, { error: "gemini must not be called" }),
  });
  check("duplicate: zero Gemini calls made", fetchedUrls.length, 0);
  check("duplicate: no new scan row inserted", reuse.state.inserted.length, 0);
  check("duplicate: previous scanId returned", reuse.json.scanId, "scan-reused-7");
  check("duplicate: decision replayed exactly", reuse.json.decision, "accept");
  check("duplicate: flagged as reused for support", reuse.json.ocrReused, true);

  // فشل فني مخزّن لا يُعاد استخدامه، وإلا بقي المستخدم محتجزاً في نتيجة عطل
  // Google بعد زوال العطل.
  const afterOutage = await runScan({
    body: baseBody,
    reusableScan: reusableRow({ risk_flags: ["server_ocr_failed"] }),
    fetchHandler: async () => httpResponse(200, geminiTextResponse(validBankakText())),
  });
  check("technical failure row is not reused", fetchedUrls.length > 0, true);
  check("technical failure row re-scanned live", afterOutage.json.decision, "accept");

  // اختلاف وسيلة الدفع يعني قراراً مختلفاً محتملاً (BIN/الاسم) ⇒ لا إعادة استخدام.
  const otherMethod = await runScan({
    body: baseBody,
    reusableScan: reusableRow({ ocr_data: { expected_method_id: "de4cc79b-df0c-448b-8c97-b22f9e8d4b2a", result_snapshot: snapshot } }),
    fetchHandler: async () => httpResponse(200, geminiTextResponse(validBankakText())),
  });
  check("different payment method forces a fresh scan", fetchedUrls.length > 0, true);
  check("fresh scan still accepted", otherMethod.json.decision, "accept");
}

console.log("\n── فلاتر منع التكرار: IS NULL بدل eq.null ──");
{
  const named = await runScan({
    body: baseBody,
    fetchHandler: async () => httpResponse(200, geminiTextResponse(validBankakText())),
  });
  const amountFilter = named.state.filters.find((f) => f.table === "receipt_scan_results" && f.column === "expected_amount");
  const refFilter = named.state.filters.find((f) => f.table === "receipt_scan_results" && f.column === "manual_ref");
  check("dedup filter: amount compared with eq when present", amountFilter && amountFilter.op, "eq");
  check("dedup filter: ref compared with eq when present", refFilter && refFilter.op, "eq");

  // بلا مبلغ/رقم معلن: eq(null) يُرسل eq.null ⇒ PostgREST يردّ 400 على الأعمدة
  // الرقمية (invalid input syntax for type numeric: "null") ويتعطّل الكاش بصمت.
  // الصيغة الصحيحة هي IS NULL عبر is(column, null).
  const anonymous = await runScan({
    body: Object.assign({}, baseBody, { expectedAmount: 0, manualRef: "" }),
    fetchHandler: async () => httpResponse(200, geminiTextResponse(validBankakText())),
  });
  const amountNull = anonymous.state.filters.find((f) => f.table === "receipt_scan_results" && f.column === "expected_amount");
  const refNull = anonymous.state.filters.find((f) => f.table === "receipt_scan_results" && f.column === "manual_ref");
  check("dedup filter: empty amount uses is.null", amountNull && amountNull.op, "is");
  check("dedup filter: empty amount value is null", amountNull && amountNull.value, null);
  check("dedup filter: empty ref uses is.null", refNull && refNull.op, "is");
  check("dedup filter: empty ref value is null", refNull && refNull.value, null);
}

console.log("\n── تخزين رقم العملية الذي وثّقه القرار (إشعار RTL: القيمة قبل التسمية) ──");
{
  // نفس ترتيب الأسطر الذي أرجعه Gemini فعلاً لإيصال أوكاش في الإنتاج: القيمة
  // قبل التسمية، فيفوز التاريخ كمرشّح «موسوم» في حقل العرض بينما المطابقة
  // الحقيقية تجد رقم العميل داخل النص. تخزين التاريخ في tx_ref_ocr يجعل
  // claim_payment_receipt يعيد ref_verified=false ⇒ هبوط الطلب إلى مراجعة رغم
  // أن الفحص قبله (عطل حقيقي شوهد في الإنتاج).
  // نفس النص الذي أرجعه Gemini حرفياً لإيصال أوكاش في الإنتاج (rawExcerpt)،
  // مع تاريخ اليوم حتى يبقى الإيصال «حديثاً» ولا يعتمد الاختبار على يوم تشغيله.
  const today = new Date();
  const day = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  const ocashRtlText = [
    "أوكاش",
    "بنك أم درمان الوطني",
    "تفاصيل الحركة",
    "121004123456789 رقم الحركة",
    `${day} 09:15:22 تاريخ الحركة`,
    "تحويل نوع الحركة",
    "عبدالله محمد ابراهيم اسم العميل",
    "48,500.00 SDG قيمة الحركة",
    "0991234567 رقم الهاتف المحمول",
    "نادوسلالنيز مقدم الخدمة",
    "1234567890 التحويل الى حساب مصرفي",
    "1234567890 الحساب المحلي",
    "حركة ناجحة",
    "أ",
  ].join("\n");

  const verified = await runScan({
    body: Object.assign({}, baseBody, { expectedAmount: 48500, manualRef: "121004123456789" }),
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async () => httpResponse(200, geminiTextResponse(ocashRtlText)),
  });
  check("RTL ref: decision stays accept", verified.json.decision, "accept");
  check("RTL ref: refVerified true", verified.json.refVerified, true);
  // الواجهة لا تتغيّر: نفس القيمة المعروضة قبل الإصلاح (لا نلمس الرد).
  check("RTL ref: display value untouched", verified.json.extracted.txRef, day);
  // المخزَّن للربط = الرقم الذي وثّقه القرار، لا التاريخ.
  check("RTL ref: stored tx_ref_ocr is the verified ref", verified.state.inserted[0].payload.tx_ref_ocr, "121004123456789");

  // بلا توثيق للرقم (رقم لا وجود له في الإيصال) لا نُرقّي شيئاً: يُخزَّن
  // الاستخراج كما هو ولا يُكتب رقم العميل في القاعدة.
  const unverified = await runScan({
    body: Object.assign({}, baseBody, { expectedAmount: 48500, manualRef: "555555555555" }),
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async () => httpResponse(200, geminiTextResponse(ocashRtlText)),
  });
  check("RTL ref: unverified ref is not promoted", unverified.state.inserted[0].payload.tx_ref_ocr, day);
  check("RTL ref: manual ref never written without verification", unverified.state.inserted[0].payload.tx_ref_ocr === "555555555555", false);
}

console.log("\n── صورة بلا نص → reject ──");
{
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async () => httpResponse(200, geminiEmptyResponse()),
  });
  check("empty OCR → reject", result.json.decision, "reject");
  check("empty OCR flag", result.json.riskFlags.includes("not_a_receipt"), true);
  check("empty OCR not submittable", result.state.inserted[0].payload.submission_allowed, false);
}

console.log("\n── المصادقة والحدود ──");
{
  const noToken = await runScan({ body: baseBody, token: null, fetchHandler: async () => httpResponse(500, {}), expectStatus: 401 });
  check("no JWT → auth_required", noToken.json.error, "auth_required");

  const badToken = await runScan({ body: baseBody, token: "bad-token", fetchHandler: async () => httpResponse(500, {}), expectStatus: 401 });
  check("invalid JWT → auth_required", badToken.json.error, "auth_required");
  check("invalid JWT never reached Gemini", fetchedUrls.length, 0);

  const limited = await runScan({
    body: baseBody, scanCount: 99,
    fetchHandler: async () => httpResponse(500, {}),
    expectStatus: 429,
  });
  check("rate limited error", limited.json.error, "rate_limited");
}

console.log("\n── مدخلات غير صالحة ──");
{
  const badImage = await runScan({
    body: Object.assign({}, baseBody, { mimeType: "image/heic" }),
    fetchHandler: async () => httpResponse(500, {}),
  });
  check("unsupported mime → review", badImage.json.decision, "review");
  check("unsupported mime flag", badImage.json.riskFlags.includes("invalid_image_input"), true);

  const missing = await runScan({
    body: Object.assign({}, baseBody, { imageBase64: "" }),
    fetchHandler: async () => httpResponse(500, {}),
  });
  check("missing image → review", missing.json.decision, "review");
  // لا سجل فحص ولا scanId: لا يمكن للعميل إكمال الطلب بلا فحص موثّق.
  check("missing image created no scan row", missing.state.inserted.length, 0);
  check("missing image never reached Gemini", fetchedUrls.length, 0);
  check("missing image has no scanId", missing.json.scanId, undefined);
}

console.log("\n── تمرير بيانات وسيلة الدفع (مهمة 35) ──");
{
  const result = await runScan({
    body: Object.assign({}, baseBody, { expectedMethodId: "11111111-1111-1111-1111-111111111111" }),
    paymentMethod: {
      id: "11111111-1111-1111-1111-111111111111",
      name: "بنكك",
      account_name: "محمد الصادق",
      account_number: "2050123456789012",
      bin_prefixes: "2050123456789012",
      bank_key: "bankak",
    },
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async () => httpResponse(200, geminiTextResponse(validBankakText())),
  });
  check("method-aware decision accept", result.json.decision, "accept");
  check("expected method id saved", result.state.inserted[0].payload.ocr_data.expected_method_id, "11111111-1111-1111-1111-111111111111");
}

console.log("\n── الاستخراج المهيكل يُدمج عند عدم اليقين ──");
{
  let calls = 0;
  const result = await runScan({
    body: Object.assign({}, baseBody, { expectedAmount: 125000, expectedAccount: "" }),
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async (url, init) => {
      calls++;
      const isJson = String(url).includes(":generateContent") && JSON.parse(init.body).generationConfig.responseMimeType === "application/json";
      if (isJson) {
        return httpResponse(200, geminiTextResponse(JSON.stringify({
          bank: "بنك الخرطوم", transaction_type: "transfer", amount: "125000", currency: "SDG",
          sender_name: "محمد الصادق", receiver_name: "متجر رايزي", sender_account: "1234567890",
          receiver_account: "2050123456789012", phone: "0912345678",
          transaction_id: "FT250719123456", reference: "FT250719123456",
          date: new Date().toISOString().slice(0, 10), time: "14:30", status: "successful",
          raw_text: validBankakText(),
        })));
      }
      // أول مرور: نص ناقص بلا مبلغ/حالة ⇒ يحتاج استخراجاً مهيكلاً
      return httpResponse(200, geminiTextResponse("بنكك\nتحويلات\nرقم العملية: FT250719123456"));
    },
  });
  const ocrData = result.state.inserted[0].payload.ocr_data;
  check("structured pass ran", calls, 2);
  check("structured fields stored", ocrData.extracted_fields && ocrData.extracted_fields.transaction_id, "FT250719123456");
  check("second pass recorded", ocrData.passes, 2);
  check("decision improved to accept", result.json.decision, "accept");
}

console.log("\n── المهمة 37: تحكيم إضافي على رفض عدم تطابق المبلغ ──");
{
  let calls = 0;
  const wrongAmountText = validBankakText().replace("125,000.00 SDG", "99,500.00 SDG");
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-ok" },
    fetchHandler: async (url, init) => {
      calls++;
      const isJson = JSON.parse(init.body).generationConfig.responseMimeType === "application/json";
      if (isJson) {
        return httpResponse(200, geminiTextResponse(JSON.stringify({
          bank: "بنكك", transaction_type: "transfer", amount: "125000", currency: "SDG",
          sender_name: "محمد الصادق", receiver_name: "متجر رايزي", sender_account: "1234567890",
          receiver_account: "2050123456789012", phone: "0912345678",
          transaction_id: "FT250719123456", reference: "FT250719123456",
          date: new Date().toISOString().slice(0, 10), time: "14:30", status: "successful",
          raw_text: validBankakText(),
        })));
      }
      return httpResponse(200, geminiTextResponse(wrongAmountText));
    },
  });
  check("arbitration ran on amount_mismatch reject", calls, 2);
  check("arbitration_on_reject flag recorded", result.json.riskFlags.includes("arbitration_on_reject"), true);
  check("decision no longer a plain reject", result.json.decision === "reject", false);
  check("second pass improved to accept", result.json.decision, "accept");
}

// ── عقد الميزانية الزمنية (regression) ────────────────────────────────
// عطل حقيقي شوهد في الإنتاج بعد النشر: النموذج السليم يستغرق 11–20 ثانية،
// ونماذج Google الأحدث ترجع 503 "high demand" بشكل متقطع، فكانت مهلة 60 ثانية
// الكلية تنفد قبل الوصول إلى نموذج سليم فيُعاد server_ocr_timeout رغم سلامة
// الخدمة. هذه الفحوص تمنع تكرار ضبط ميزانية لا تتسع للنماذج البديلة.
const numConst = (source, name) => {
  const m = source.match(new RegExp(name + "\\s*=\\s*([0-9_]+)"));
  return m ? Number(m[1].replace(/_/g, "")) : NaN;
};
const rawIndexSrc = fs.readFileSync(indexPath, "utf8");
const reqTimeout = numConst(rawIndexSrc, "GEMINI_REQUEST_TIMEOUT_MS");
const jsonTimeout = numConst(rawIndexSrc, "GEMINI_JSON_TIMEOUT_MS");
const totalBudget = numConst(rawIndexSrc, "GEMINI_TOTAL_BUDGET_MS");
const maxModels = numConst(rawIndexSrc, "GEMINI_MAX_MODELS");
const pipelineSrc = fs.readFileSync(path.join(root, "assets/js/receipt-pipeline.js"), "utf8");
const clientTimeout = numConst(pipelineSrc, "EDGE_TIMEOUT_MS");

check("timing: per-attempt timeout parsed", reqTimeout > 0, true);
check("timing: at least 4 model attempts fit the total budget", totalBudget >= reqTimeout * 4, true);
check("timing: structured-pass timeout <= OCR attempt timeout", jsonTimeout <= reqTimeout, true);
check("timing: model fallback list has at least 4 entries", maxModels >= 4, true);
check(
  "timing: server budget leaves >=10s margin under client EDGE_TIMEOUT_MS",
  totalBudget + 10_000 <= clientTimeout,
  true,
);

fs.rmSync(tmpDir, { recursive: true, force: true });

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) {
  for (const failure of failures) console.log("  - " + failure);
  process.exit(1);
}
