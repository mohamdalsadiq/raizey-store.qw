#!/usr/bin/env node
/*
 * RAIZEY STORE — تشغيل اختبارات الإيصالات الحقيقية على الدالة المنشورة
 * =====================================================================
 * يمرّر صور الاختبار عبر نفس المسار الذي يستخدمه المتصفح:
 *   صورة → process-receipt (Edge) → Gemini (OCR حقيقي) → receipt-judge-core
 *   → receipt_scan_results → القرار الراجع للواجهة
 *
 * لا يقرأ أي مفتاح سري: يستقبل JWT مستخدم اختباري عبر ملف، ويطبع فقط
 * الحقول غير الحساسة (القرار، المزوّد، المبلغ، رقم العملية، الأعلام).
 *
 * الاستخدام:
 *   node scripts/live_receipt_e2e.mjs --jwt-file /tmp/jwt.txt --cases bankak,fawry
 *   node scripts/live_receipt_e2e.mjs --jwt-file /tmp/jwt.txt --cases auth
 *   node scripts/live_receipt_e2e.mjs --jwt-file /tmp/jwt.txt --cases invalid \
 *        --fixtures /tmp/livecheck/fixtures --out /tmp/livecheck
 */
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
function arg(name, fallback) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}

const JWT_FILE = arg("jwt-file", "/tmp/livecheck/jwt.txt");
const FIXTURES = arg("fixtures", "/tmp/livecheck/fixtures");
const OUT = arg("out", "/tmp/livecheck");
const FN_URL = arg(
  "fn-url",
  "https://rglbfizqolrenwfsndyv.supabase.co/functions/v1/process-receipt",
);
const WANTED = arg("cases", "bankak,ocash,fawry,ocash_variant,wrong_amount,wrong_ref,invalid,auth").split(",");

// معرّفات وسائل الدفع الحقيقية في القاعدة (تُجلب من payment_methods)
const METHOD_BANKAK = "b53c0263-8286-4ca9-98a7-2bd9bc668e79";
const METHOD_OCASH = "de4cc79b-df0c-448b-8c97-b22f9e8d4b2a";

const CASES = {
  bankak: { file: "bankak.png", amount: 125000, ref: "FT250719123456", method: METHOD_BANKAK, expect: "accept" },
  ocash: { file: "ocash.png", amount: 48500, ref: "121004123456789", method: METHOD_OCASH, expect: "accept" },
  // نفس حقول إيصال أوكاش لكن ببصمة صورة مختلفة: يفرض فحصاً كاملاً جديداً
  // (منع إعادة الاستخدام يمنع إعادة فحص نفس البصمة) فيقيس المسار الحقيقي.
  ocash_variant: { file: "ocash_variant.png", amount: 48500, ref: "121004123456789", method: METHOD_OCASH, expect: "accept" },
  // ترتيب أسطر يفرض ظهور التاريخ كمرشّح موسوم (نفس ما حدث في الإنتاج): يجب أن
  // يُخزَّن رقم العملية الموثّق في tx_ref_ocr، لا التاريخ.
  ocash_split: { file: "ocash_split.png", amount: 48500, ref: "121004123456789", method: METHOD_OCASH, expect: "accept" },
  fawry: { file: "fawry.png", amount: 23750, ref: "987654321012", method: null, expect: "accept" },
  // صورة إيصال سليمة لكن المبلغ المعلن مختلف ⇒ يجب الرفض (لا يمرر كما لو كان مدفوعاً)
  wrong_amount: { file: "bankak.png", amount: 999, ref: "FT250719123456", method: METHOD_BANKAK, expect: "reject" },
  // نفس الصورة والمبلغ لكن رقم عملية لا وجود له ⇒ يجب الرفض
  wrong_ref: { file: "ocash.png", amount: 48500, ref: "999999999999", method: METHOD_OCASH, expect: "reject" },
  // صورة بلا أي نص ⇒ يجب الرفض (ليست إيصالاً)
  invalid: { file: "not_receipt.png", amount: 50000, ref: "123456789", method: null, expect: "reject" },
  // بلا JWT ⇒ 401 من البوابة قبل أي OCR
  auth: { noAuth: true, expect: 401 },
};

// لا نحتاج JWT لحالة "auth" (وهي تتحقق من رفض الطلب بلا توثيق)، لكن بقية
// الحالات تحتاجه. يُقرأ من ملف خارجي حتى لا يلمس أي مفتاح سري هنا.
const needsJwt = WANTED.some((name) => name !== "auth");
const jwt = needsJwt ? fs.readFileSync(JWT_FILE, "utf8").trim() : "";

let failures = 0;
const summary = [];

for (const name of WANTED) {
  const spec = CASES[name];
  if (!spec) {
    console.log(`SKIP  unknown case "${name}"`);
    failures++;
    continue;
  }
  const headers = { "Content-Type": "application/json" };
  if (!spec.noAuth) headers.Authorization = `Bearer ${jwt}`;

  const body = spec.noAuth
    ? { imageBase64: Buffer.from("not-an-image").toString("base64"), mimeType: "image/png" }
    : {
        imageBase64: fs.readFileSync(path.join(FIXTURES, spec.file)).toString("base64"),
        mimeType: "image/png",
        expectedAmount: spec.amount,
        manualRef: spec.ref,
        expectedAccount: "",
        expectedMethodId: spec.method,
      };

  const t0 = Date.now();
  let status = 0;
  let json = null;
  try {
    const res = await fetch(FN_URL, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(150_000),
    });
    status = res.status;
    json = await res.json();
  } catch (error) {
    json = { transport_error: `${error.name}: ${error.message}` };
  }
  const ms = Date.now() - t0;
  const outFile = path.join(OUT, `live_${name}.json`);
  fs.writeFileSync(outFile, JSON.stringify({ status, ms, ...json }, null, 1));

  const got = json?.decision ?? status;
  const ok = got === spec.expect;
  if (!ok) failures++;

  const flags = (json?.riskFlags || []).join(",");
  console.log(`${ok ? "PASS" : "FAIL"}  ${name.padEnd(13)} http=${status} ${String(ms).padStart(6)}ms decision=${String(json?.decision ?? "-").padEnd(7)} expect=${spec.expect}`);
  if (!spec.noAuth) {
    console.log(
      `      provider=${json?.provider || "-"} amount=${json?.amountDetected ?? json?.extracted?.amount ?? "-"} ` +
        `ref=${json?.extracted?.txRef ?? json?.txRefOcr ?? "null"} model=${json?.model || "-"} ` +
        `rawExcerpt=${(json?.rawExcerpt || "").length}ch flags=[${flags}] reused=${json?.ocrReused === true}`,
    );
  } else {
    console.log(`      body=${JSON.stringify(json)}`);
  }
  console.log(`      scanId=${json?.scanId || "-"} evidence=${outFile}`);
  summary.push({ name, status, ms, got, expect: spec.expect, ok, scanId: json?.scanId ?? null });
}

fs.writeFileSync(path.join(OUT, "live_summary.json"), JSON.stringify(summary, null, 1));
console.log(`\n${summary.filter((s) => s.ok).length}/${summary.length} live cases matched expectation`);
process.exit(failures ? 1 : 0);
