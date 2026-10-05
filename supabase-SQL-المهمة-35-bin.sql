-- RAIZEY STORE — المهمة 35: حقول BIN ومفتاح البنك في وسائل الدفع
-- شغّل هذا الملف في Supabase Dashboard ← SQL Editor ← New Query ← الصق ← Run
--
-- الهدف: ربط كل وسيلة دفع (بنك) ببادئات BIN الخاصة بها + مفتاح المزوّد،
-- ليتحقق محرك الفحص الذكي أولاً من: BIN حساب المستلم + اسم صاحب الحساب
-- مقابل البنك الذي اختاره العميل، قبل المبلغ ورقم العملية.

ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bin_prefixes text DEFAULT '';

ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bank_key text DEFAULT '';

COMMENT ON COLUMN public.payment_methods.bin_prefixes IS
  'بادئات BIN لحسابات هذا البنك (مفصولة بفواصل أو مسافات) — مثال: 1234,5678. تُستخدم للتحقق من أن حساب المستلم في الإيصال يتبع البنك المختار';

COMMENT ON COLUMN public.payment_methods.bank_key IS
  'مفتاح المزوّد في محرك الفحص (bankak / ocash / fawry / mbok / cashi / faisal / nilebank / alsalam) — يُستخدم لمطابقة البنك المكتشف في الإيصال مع البنك المختار';

-- تحقق سريع بعد التشغيل (يجب أن يرجع صفين جديدين بدون خطأ):
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'payment_methods' AND column_name IN ('bin_prefixes', 'bank_key');
