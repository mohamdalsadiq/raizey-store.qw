/*
 * RAIZEY STORE — اختبار receipt-pipeline (عقد الواجهة مع Edge Function)
 * =====================================================================
 * يشغّل assets/js/receipt-pipeline.js في Node داخل vm مع بدائل للشبكة
 * والجلسة، ويتحقق من:
 *   - قبول/رفض صيغ الصور والأحجام (العقد الأساسي)
 *   - وصول الصورة و expectedMethodId إلى السيرفر بصيغة صحيحة
 *   - إرسال ترويسة JWT وإرفاق apikey العام
 *   - تحويل 401 / 429 / انتهاء المهلة / غياب scanId إلى حالة مراجعة واضحة
 *   - عدم تسريب أي مفتاح أو رمز جلسة في النتيجة المعادة للواجهة
 *
 * التشغيل:  node scripts/test_receipt_pipeline.mjs
 */
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../assets/js/receipt-pipeline.js", import.meta.url), "utf8");

let passed = 0;
const failures = [];
function check(label, actual, expected) {
  if (actual === expected) {
    passed++;
    console.log(`PASS  ${label}`);
    return;
  }
  failures.push(`${label}: expected ${expected}, got ${actual}`);
  console.log(`FAIL  ${label}  → expected ${expected}, got ${actual}`);
}

const SUPABASE_URL = "https://test.supabase.co";
const ANON_KEY = "public-anon-key";
const JWT = "user-jwt-token";

class FileReaderStub {
  readAsDataURL() {
    Promise.resolve().then(() => {
      this.result = "data:image/png;base64," + Buffer.alloc(32, 7).toString("base64");
      if (this.onload) this.onload();
    });
  }
}

/** ينشئ سياق vm جديداً مع fetch مراقَب وسياق جلسة قابل للتحكم. */
function loadPipeline({ fetchImpl, session = { access_token: JWT } } = {}) {
  const requests = [];
  const context = {
    Blob,
    FileReader: FileReaderStub,
    Image: class ImageStub {},
    URL: { createObjectURL: () => "blob:stub", revokeObjectURL: () => {} },
    AbortController,
    setTimeout,
    clearTimeout,
    console,
    fetch: async (url, init) => {
      requests.push({ url: String(url), init });
      return fetchImpl(String(url), init);
    },
    supabaseClient: { auth: { getSession: async () => ({ data: { session }, error: null }) } },
    SUPABASE_URL,
    SUPABASE_ANON_KEY: ANON_KEY,
  };
  context.globalThis = context;
  context.window = context;
  vm.runInNewContext(source, context, { filename: "receipt-pipeline.js" });
  return { pipeline: context.RaizeyReceiptPipeline, requests };
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function pngFile(bytes = 32) {
  return new Blob([new Uint8Array(bytes)], { type: "image/png" });
}

console.log("\n── عقد الصور (validation) ──");
{
  const { pipeline } = loadPipeline({ fetchImpl: async () => jsonResponse(500, {}) });
  const cases = [
    ["jpg accepted", new Blob([new Uint8Array(32)], { type: "image/jpeg" }), true],
    ["png accepted", new Blob([new Uint8Array(32)], { type: "image/png" }), true],
    ["webp accepted", new Blob([new Uint8Array(32)], { type: "image/webp" }), true],
    ["heic rejected", new Blob([new Uint8Array(32)], { type: "image/heic" }), false],
    ["oversized rejected", new Blob([new Uint8Array(5 * 1024 * 1024 + 1)], { type: "image/png" }), false],
  ];
  for (const [label, file, expected] of cases) {
    let actual = true;
    try { pipeline.validateImageFile(file); } catch (_) { actual = false; }
    check(label, actual, expected);
  }
}

console.log("\n── شكل الطلب المرسل للسيرفر ──");
{
  const { pipeline, requests } = loadPipeline({
    fetchImpl: async () => jsonResponse(200, { ok: true, scanId: "scan-1", receiptHash: "a".repeat(64), decision: "accept" }),
  });
  const result = await pipeline.serverVerify(pngFile(), {
    expectedAmount: 125000,
    manualRef: "FT250719123456",
    expectedAccount: "2050123456789012",
    expectedMethodId: "11111111-1111-1111-1111-111111111111",
  });
  check("single request sent", requests.length, 1);
  check("endpoint is the edge function", requests[0].url, `${SUPABASE_URL}/functions/v1/process-receipt`);
  check("method is POST", requests[0].init.method, "POST");
  check("bearer jwt attached", requests[0].init.headers.Authorization, `Bearer ${JWT}`);
  check("public anon key attached", requests[0].init.headers.apikey, ANON_KEY);
  const payload = JSON.parse(requests[0].init.body);
  check("image base64 present", typeof payload.imageBase64 === "string" && payload.imageBase64.length > 0, true);
  check("mime type sent", payload.mimeType, "image/png");
  check("expectedAmount sent", payload.expectedAmount, 125000);
  check("manualRef sent", payload.manualRef, "FT250719123456");
  check("expectedAccount sent", payload.expectedAccount, "2050123456789012");
  check("expectedMethodId sent", payload.expectedMethodId, "11111111-1111-1111-1111-111111111111");
  check("scanId returned to caller", result.scanId, "scan-1");
  check("request body has no api key", /GEMINI|service_role/i.test(requests[0].init.body), false);
}

console.log("\n── تحويل الأخطاء إلى حالات واجهة ──");
async function analyzeWith(fetchImpl, extraOptions = {}) {
  const { pipeline } = loadPipeline({ fetchImpl });
  return pipeline.analyze(pngFile(), Object.assign({ expectedAmount: 125000, manualRef: "FT250719123456" }, extraOptions));
}
{
  const unauthorized = await analyzeWith(async () => jsonResponse(401, { ok: false, error: "auth_required" }));
  check("401 → auth_required flag", unauthorized.riskFlags[0], "auth_required");
  check("401 → review decision", unauthorized.decision, "review");

  const forbidden = await analyzeWith(async () => jsonResponse(403, { ok: false, error: "forbidden" }));
  check("403 → auth_required flag", forbidden.riskFlags[0], "auth_required");

  const rateLimited = await analyzeWith(async () => jsonResponse(429, { ok: false, error: "rate_limited" }));
  check("429 → rate limited flag", rateLimited.riskFlags[0], "server_rate_limited");
  check("429 → message is user-facing", typeof rateLimited.message === "string" && rateLimited.message.length > 0, true);

  const serverError = await analyzeWith(async () => jsonResponse(500, { ok: false, error: "receipt_processing_failed" }));
  check("500 → server_ocr_failed flag", serverError.riskFlags[0], "server_ocr_failed");
  check("500 → never auto-accepts", serverError.decision === "accept", false);

  // استجابة ناقصة العقد (بلا scanId) يجب أن تُرفض محلياً — لا يُدخل الطلب بلا فحص مرتبط.
  const malformed = await analyzeWith(async () => jsonResponse(200, { ok: true, decision: "accept" }));
  check("missing scanId → not accepted", malformed.decision === "accept", false);
  check("missing scanId → server_ocr_failed", malformed.riskFlags[0], "server_ocr_failed");

  // انتهاء المهلة: fetch يبقى معلقاً حتى يُلغى من AbortController الخاص بالعميل.
  const timedOut = await analyzeWith(async (url, init) => new Promise((_, reject) => {
    init.signal.addEventListener("abort", () => reject(Object.assign(new Error("aborted"), { name: "AbortError" })));
  }), { serverTimeoutMs: 40 });
  check("client timeout → server_ocr_timeout", timedOut.riskFlags[0], "server_ocr_timeout");
  check("client timeout → review", timedOut.decision, "review");
}

console.log("\n── عدم تسريب الأسرار إلى الواجهة ──");
{
  const { pipeline } = loadPipeline({ fetchImpl: async () => jsonResponse(200, { ok: true, scanId: "s", receiptHash: "b".repeat(64) }) });
  const soft = pipeline.softReview("server_ocr_failed");
  const serialized = JSON.stringify(soft);
  check("soft review has no jwt", serialized.includes(JWT), false);
  check("soft review has no api key", serialized.includes(ANON_KEY), false);
  check("soft review has no token/key fields", /"(token|apiKey|api_key|secret)"/i.test(serialized), false);
  check("fallback flags exposed for the UI", Array.isArray(pipeline.fallbackFlags) && pipeline.fallbackFlags.length > 0, true);
}

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) {
  for (const failure of failures) console.log("  - " + failure);
  process.exit(1);
}
