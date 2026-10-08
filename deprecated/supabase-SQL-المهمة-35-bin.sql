-- RAIZEY STORE — المهمة 35: حقول BIN ومفتاح البنك في وسائل الدفع
-- شغّل هذا الملف في Supabase Dashboard ← SQL Editor ← New Query ← الصق ← Run
--
-- الهدف: ربط كل وسيلة دفع (بنك) برقم BIN الكامل الخاص بها،
-- ليتحقق محرك الفحص الذكي أولاً من: رقم BIN (ورقم الحساب المضمّن فيه)
-- + اسم صاحب الحساب، مقابل البنك الذي اختاره العميل، قبل المبلغ ورقم العملية.
--
-- صيغة الـ BIN: رقم كامل (17 خانة مثلاً: 57040290563000001) —
-- رقم الحساب (7 خانات: 2905630) مضمّن في وسطه، والأرقام الأولى والأخيرة
-- ثابتة لكل بنك وتختلف من بنك لآخر.

ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bin_prefixes text DEFAULT '';

ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS bank_key text DEFAULT '';

COMMENT ON COLUMN public.payment_methods.bin_prefixes IS
  'رقم BIN الكامل للبنك (17 خانة مثلاً) — رقم الحساب مضمّن في وسطه والأول/الأخير ثابت للبنك. يُطابَق مع رقم (الى حساب) في الإيصال. يمكن فصل عدة قيم بفواصل';

COMMENT ON COLUMN public.payment_methods.bank_key IS
  'مفتاح المزوّد في محرك الفحص (bankak / ocash / fawry / mbok / cashi / faisal / nilebank / alsalam) — يُستخدم لمطابقة البنك المكتشف في الإيصال مع البنك المختار';

-- تحقق سريع بعد التشغيل (يجب أن يرجع صفين جديدين بدون خطأ):
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'payment_methods' AND column_name IN ('bin_prefixes', 'bank_key');
