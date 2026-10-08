/*
 * RAIZEY STORE — اختبار نواة الحكم الحتمية (receipt-judge-core)
 * =====================================================================
 * يشغّل receipt-judge-core.ts في Node (بلا اعتماد على المتصفح أو الشبكة)
 * ويتحقق من قرارات accept / review / reject على إيصالات بنكك/أوكاش/فوري
 * وأرقام عربية وإنجليزية، مع اختبارات للمبلغ ورقم العملية والصورة غير الصالحة.
 *
 * التشغيل:  node scripts/test_receipt_judge.mjs
 */
import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const judgePath = fileURLToPath(new URL("../supabase/functions/process-receipt/receipt-judge-core.ts", import.meta.url));

function loadJudgeCore() {
  const raw = fs.readFileSync(judgePath, "utf8");
  // الملف JavaScript صرف بلا أنواع: نزيل سطر التصدير فقط ونشغّله في VM.
  const source = raw.replace(/export\s*\{\s*ReceiptJudgeCore\s*\};?\s*$/m, "") + "\n;globalThis.__ReceiptJudgeCore = ReceiptJudgeCore;";
  const context = { globalThis: {}, console };
  context.globalThis = context;
  vm.runInNewContext(source, context, { filename: "receipt-judge-core.ts" });
  const core = context.__ReceiptJudgeCore;
  if (!core || typeof core.judge !== "function") throw new Error("judge_core_not_loaded");
  return core;
}

const Core = loadJudgeCore();

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

function run(text, options) {
  const opts = Object.assign({
    expectedAmount: 0,
    manualRef: "",
    expectedAccount: "",
    expectedMethod: null,
    ocrSource: "server",
    trustedOcr: true,
  }, options || {});
  return Core.judge(Core.buildContext([text], opts), opts, Core.blankResult());
}

/** تاريخ اليوم بصيغة الإشعارات حتى لا يعتمد القبول على ساعة الجهاز. */
function todayStamp() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  const hh = String(now.getHours()).padStart(2, "0");
  const mm = String(now.getMinutes()).padStart(2, "0");
  return `${y}-${m}-${d} ${hh}:${mm}`;
}

const MERCHANT_ACCOUNT = "2050123456789012";
const AMOUNT = 125000;

// ── 1) بنكك — إيصال صحيح كامل (إنجليزي/عربي مختلط) ──
const bankakText = `
بنكك
تحويلات
تمت العملية بنجاح
رقم العملية: FT250719123456
المبلغ: 125,000.00 SDG
من حساب: 1234567890
الى حساب: ${MERCHANT_ACCOUNT}
اسم المرسل اليه: محمد الصادق
التاريخ و الزمن: ${todayStamp()}
رقم الموبايل: 0912345678
الرصيد المتاح: 500,000.00 SDG
`;

// ── 2) أوكاش — إيصال صحيح ──
const ocashText = `
أوكاش
بنك أم درمان الوطني
تفاصيل الحركة
حركة ناجحة
رقم الحركة: 20250719888777
قيمة الحركة: 125,000.00 SDG
اسم العميل: محمد الصادق
رقم الهاتف المحمول: 0912345678
التحويل إلى حساب مصرفي
الحساب المحلي: ${MERCHANT_ACCOUNT}
`;

// ── 3) فوري — إيصال صحيح ──
const fawryText = `
فوري
الرقم المرجعي: 554433221100
المبلغ: 125,000.00 SDG
اسم البنك: بنك فيصل الإسلامي
من الحساب: 111122223333
الى الحساب: ${MERCHANT_ACCOUNT}
ناجح
`;

// ── 4) أرقام عربية (٠-٩) وفواصل عربية ──
const arabicDigitsText = `
بنكك
تحويلات
تمت العملية بنجاح
رقم العملية: ٢٠٢٥٠٧١٩١٢٣٤٥٦
المبلغ: ١٢٥٬٠٠٠٫٠٠ ج.س
الى حساب: ٢٠٥٠١٢٣٤٥٦٧٨٩٠١٢
اسم المرسل اليه: محمد الصادق
التاريخ و الزمن: ${todayStamp()}
`;

console.log("\n── إيصالات صحيحة: accept ──");
const bankak = run(bankakText, { expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT });
check("Bankak decision", bankak.decision, "accept");
check("Bankak provider", bankak.provider, "bankak");
check("Bankak refVerified", bankak.refVerified, true);
check("Bankak amountVerified", bankak.amountVerified, true);
check("Bankak extracted amount", bankak.extracted.amount, AMOUNT);
check("Bankak extracted txRef", Core.normalizeRef(bankak.extracted.txRef), "FT250719123456");
check("Bankak txRef keeps alphabetic prefix", String(bankak.extracted.txRef).toUpperCase().startsWith("FT"), true);
check("Bankak raw text preserved", typeof bankak.extracted.txRefCandidates !== "undefined", true);

const ocash = run(ocashText, { expectedAmount: AMOUNT, manualRef: "20250719888777", expectedAccount: MERCHANT_ACCOUNT });
check("OCash decision", ocash.decision, "accept");
check("OCash provider", ocash.provider, "ocash");
check("OCash amountVerified", ocash.amountVerified, true);

const fawry = run(fawryText, { expectedAmount: AMOUNT, manualRef: "554433221100", expectedAccount: MERCHANT_ACCOUNT });
check("Fawry decision", fawry.decision, "accept");
check("Fawry provider", fawry.provider, "fawry");
check("Fawry refVerified", fawry.refVerified, true);

const arabic = run(arabicDigitsText, { expectedAmount: AMOUNT, manualRef: "20250719123456" });
check("Arabic digits decision", arabic.decision, "accept");
check("Arabic digits amount", arabic.extracted.amount, AMOUNT);
check("Arabic digits ref normalized", Core.normalizeRef(arabic.extracted.txRef), "20250719123456");

console.log("\n── حالات الرفض: reject ──");
const wrongAmount = run(bankakText.replace("125,000.00 SDG", "99,500.00 SDG"), {
  expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT,
});
check("Wrong amount decision", wrongAmount.decision, "reject");
check("Wrong amount flag", (wrongAmount.riskFlags || []).includes("amount_mismatch"), true);
check("Wrong amount shortfall reported", wrongAmount.shortfall && wrongAmount.shortfall.remaining > 0, true);

// فرق صيغة ×10/×100 مقصود: لا يُرفض تلقائياً بل يُحوَّل لتدقيق بشري، حتى لا
// يُرفض إيصال سليم بسبب فقدان/إضافة فاصلة عشرية في القراءة الآلية.
const tenfoldAmount = run(bankakText.replace("125,000.00 SDG", "12,500.00 SDG"), {
  expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT,
});
check("Tenfold amount is not auto-accepted", tenfoldAmount.decision === "accept", false);
check("Tenfold amount → review", tenfoldAmount.decision, "review");
check("Tenfold amount flag", (tenfoldAmount.riskFlags || []).includes("amount_unverified"), true);

const wrongRef = run(bankakText, {
  expectedAmount: AMOUNT, manualRef: "FT999999999999", expectedAccount: MERCHANT_ACCOUNT,
});
check("Wrong ref decision", wrongRef.decision, "reject");
check("Wrong ref flag", (wrongRef.riskFlags || []).includes("ref_conflict"), true);

const notReceipt = run("مرحباً بكم في متجرنا، أسعار مناسبة للجميع، تواصل معنا", {
  expectedAmount: AMOUNT, manualRef: "FT250719123456",
});
check("Non-receipt decision", notReceipt.decision, "reject");
check("Non-receipt flag", (notReceipt.riskFlags || []).includes("not_a_receipt"), true);

const failedTx = run(bankakText.replace("تمت العملية بنجاح", "فشلت العملية"), {
  expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT,
});
check("Failed transaction decision", failedTx.decision, "reject");
check("Failed transaction flag starts with failed_", (failedTx.riskFlags || []).some((f) => String(f).startsWith("failed_transaction")), true);

console.log("\n── حالات المراجعة: review ──");
const weakOcr = run("رصيد", { expectedAmount: AMOUNT, manualRef: "FT250719123456" });
check("Weak OCR decision", weakOcr.decision, "review");
check("Weak OCR flag", (weakOcr.riskFlags || []).includes("low_ocr_confidence"), true);

// جزء يحمل تسمية حقل واحدة (لا مزوّد ولا مرجع) → مراجعة لا رفض.
const labelledFragment = run("المبلغ", { expectedAmount: AMOUNT, manualRef: "FT250719123456" });
check("Labelled fragment → review", labelledFragment.decision, "review");

const refOnly = run(bankakText.replace(/^المبلغ.*$/m, "").replace(/^الرصيد.*$/m, ""), {
  expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT,
});
check("Missing amount → review (not reject)", refOnly.decision, "review");

console.log("\n── طبقة هوية البنك (مهمة 35) ──");
const methodMatching = {
  id: "11111111-1111-1111-1111-111111111111",
  name: "بنكك",
  account_name: "محمد الصادق",
  account_number: MERCHANT_ACCOUNT,
  bin_prefixes: MERCHANT_ACCOUNT,
  bank_key: "bankak",
};
const withMethod = run(bankakText, {
  expectedAmount: AMOUNT, manualRef: "FT250719123456",
  expectedAccount: MERCHANT_ACCOUNT, expectedMethod: methodMatching,
});
check("Matching method → accept", withMethod.decision, "accept");
check("Method bin matched", withMethod.extracted.binMatched, true);

const wrongBankMethod = Object.assign({}, methodMatching, { bank_key: "fawry" });
const withWrongBank = run(bankakText, {
  expectedAmount: AMOUNT, manualRef: "FT250719123456",
  expectedAccount: MERCHANT_ACCOUNT, expectedMethod: wrongBankMethod,
});
check("Provider/bank mismatch → review_admin", withWrongBank.decision, "review_admin");
check("Provider/bank mismatch flag", (withWrongBank.riskFlags || []).includes("bank_provider_mismatch"), true);

const wrongNameMethod = Object.assign({}, methodMatching, { account_name: "عبد الرحمن الفكي" });
const withWrongName = run(bankakText, {
  expectedAmount: AMOUNT, manualRef: "FT250719123456",
  expectedAccount: MERCHANT_ACCOUNT, expectedMethod: wrongNameMethod,
});
check("Beneficiary name mismatch → review_admin", withWrongName.decision, "review_admin");
check("Beneficiary name flag", (withWrongName.riskFlags || []).includes("beneficiary_name_unverified"), true);

// P2-RCP-001: BIN matching modes (exact / embedded / reverse-embedded / mismatch)
console.log("\n── مطابقة BIN (تامة/مضمّنة/عكسية/غير متطابقة) ──");
function binTest(binPrefixes, label) {
  const m = Object.assign({}, methodMatching, { bin_prefixes: binPrefixes });
  const r = run(bankakText, {
    expectedAmount: AMOUNT, manualRef: "FT250719123456",
    expectedAccount: MERCHANT_ACCOUNT, expectedMethod: m,
  });
  return r;
}
let r1 = binTest("2050123456789012", "exact");
check("BIN exact match", r1.extracted.binMatched, true);
let r2 = binTest("99205012345678901234", "embedded");
check("BIN embedded (toAcct inside BIN)", r2.extracted.binMatched, true);
let r3 = binTest("12345678", "reverse");
check("BIN reverse-embedded (BIN inside toAcct)", r3.extracted.binMatched, true);
let r4 = binTest("99999999999999999", "mismatch");
check("BIN mismatch flag", (r4.riskFlags || []).includes("bin_mismatch"), true);
check("BIN mismatch → binMatched false", r4.extracted.binMatched, false);
let r5 = binTest("57040290563000001, 2050123456789012", "multi");
check("BIN multi-value (one matches)", r5.extracted.binMatched, true);

console.log("\n── التطبيع (normalization) ──");
check("normalizeRef strips separators", Core.normalizeRef("ft2507-19123456"), Core.normalizeRef("FT250719123456"));
check("latinizeDigits ar-indic", Core.latinizeDigits("١٢٣٤٥"), "12345");
check("latinizeDigits extended", Core.latinizeDigits("۱۲۳۴۵"), "12345");
check("parseAmountToken arabic separators", Core.parseAmountToken(Core.normalizeText("١٢٥٬٠٠٠٫٠٠")), 125000);
check("parseAmountToken plain", Core.parseAmountToken("125,000.00"), 125000);
check("parseAmountToken spaces", Core.parseAmountToken("125 000"), 125000);
check("parseAmountToken european", Core.parseAmountToken("125.000,00"), 125000);

console.log("\n── حتمية القرار (نفس المدخل = نفس القرار) ──");
const repeatA = run(bankakText, { expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT });
const repeatB = run(bankakText, { expectedAmount: AMOUNT, manualRef: "FT250719123456", expectedAccount: MERCHANT_ACCOUNT });
check("Idempotent decision", repeatA.decision === repeatB.decision, true);
check("Idempotent amount flag", String(repeatA.riskFlags) === String(repeatB.riskFlags), true);

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length) {
  for (const failure of failures) console.log("  - " + failure);
  process.exit(1);
}
