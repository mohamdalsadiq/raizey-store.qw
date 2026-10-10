-- =============================================================================
-- RAIZEY STORE — أيقونة/صورة لكل وسيلة دفع (Payment method icons)
-- =============================================================================
-- كل وسيلة دفع يمكن أن تحمل أيقونة/شعاراً اختيارياً يظهر في بطاقات الاختيار
-- بصفحة الدفع. الصور تُرفع إلى حزمة Supabase Storage العامة "product-images"
-- تحت المسار payment-methods/ (نفس سياسات القراءة العامة وكتابة الأدمن).
-- عند غياب الأيقونة تعرض الواجهة أيقونة بنك افتراضية من Lucide.
-- =============================================================================

BEGIN;

ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS icon_url text;

COMMENT ON COLUMN public.payment_methods.icon_url IS
  'Optional public URL of the payment-method icon/logo (Supabase Storage: product-images/payment-methods/).';

COMMIT;
