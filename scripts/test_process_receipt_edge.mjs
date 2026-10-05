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
    const q = {
      select: () => q,
      eq: () => q,
      gte: () => q,
      order: () => q,
      limit: () => q,
      maybeSingle: async () => selectResult,
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

function geminiTextResponse(text) {
  return { candidates: [{ content: { parts: [{ text }] }, finishReason: "STOP" }] };
}
function geminiEmptyResponse() {
  return { candidates: [{ content: { parts: [] }, finishReason: "STOP" }] };
}
function httpResponse(status, body) {
  return new Response(typeof body === "string" ? body : JSON.stringify(body), { status });
}

const MODEL_LIST_BODY = {
  models: [
    { name: "models/gemini-3.5-flash", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-2.5-flash", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-4.0-flash-preview", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-embedding-001", supportedGenerationMethods: ["embedContent"] },
    { name: "models/imagen-3.0-generate", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemma-3-27b-it", supportedGenerationMethods: ["generateContent"] },
  ],
};

/** ينفّذ فحصاً واحداً ببديل Supabase/Gemini مخصّص ويعيد النتيجة والحالة. */
async function runScan({ body, token = GOOD_TOKEN, env = {}, scanCount = 0, paymentMethod = null, fetchHandler, expectStatus }) {
  const state = { inserted: [], scanCount, paymentMethod };
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
  check("chosen model is latest stable flash", generatedModels[0], "gemini-3.5-flash");
  const ocrData = result.state.inserted[0].payload.ocr_data;
  check("model order source", ocrData.model_order_source, "discovery");
  check("embedding/image/gemma excluded", ocrData.gemini_models.join("|"), "gemini-3.5-flash|gemini-2.5-flash|gemini-4.0-flash-preview");
  check("preview ranked below stable", ocrData.gemini_models.indexOf("gemini-3.5-flash") < ocrData.gemini_models.indexOf("gemini-4.0-flash-preview"), true);
  check("provider detected", result.json.provider, "bankak");
  check("api key not in any URL", fetchedUrls.some((u) => u.includes(API_KEY)), false);
  check("submission allowed", result.state.inserted[0].payload.submission_allowed, true);
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
  check("tried all three models", seen.join(","), "gemini-dead-1,gemini-dead-2,gemini-alive");
  check("decision accept after failover", result.json.decision, "accept");
  const attempts = result.state.inserted[0].payload.ocr_data.models_tried;
  check("attempt diagnostics recorded", attempts.length, 3);
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
  const result = await runScan({
    body: baseBody,
    env: { GEMINI_MODEL_ORDER: "gemini-a,gemini-b" },
    fetchHandler: async () => httpResponse(503, { error: { message: "temporarily unavailable" } }),
  });
  check("all models failing → ok:true", result.json.ok, true);
  check("all models failing → review", result.json.decision, "review");
  check("all models failing → server_ocr_failed", result.json.riskFlags.includes("server_ocr_failed"), true);
  check("diagnostic saved", typeof result.state.inserted[0].payload.ocr_data.server_error_code === "string", true);
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

fs.rmSync(tmpDir, { recursive: true, force: true });

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) {
  for (const failure of failures) console.log("  - " + failure);
  process.exit(1);
}
