-- =====================================================================
-- المهمة 7 — إصلاح فعلي شامل للوحة تحكم الأدمن
-- إصلاح البند 4 (أولوية قصوى): فشل حفظ/تعديل المنتجات بالكامل
-- =====================================================================
--
-- السبب الجذري (تم تأكيده بالاتصال المباشر بقاعدة البيانات):
--   جدول public.products مفعّل عليه RLS، لكنه يملك سياسة واحدة فقط
--   للقراءة (products_select_active). لا توجد أي سياسة INSERT / UPDATE /
--   DELETE للأدمن، لذلك كل محاولة حفظ أو تعديل منتج من لوحة الأدمن
--   (التي تستخدم مفتاح anon + جلسة المستخدم) تُرفَض من RLS وتظهر رسالة
--   "فشل حفظ المنتج، يرجى المحاولة مجدداً".
--
--   المقارنة مع الجداول المشابهة (categories / coupons / settings) أظهرت
--   أنها كلها تملك سياسة "ALL" للأدمن باسم <table>_admin_all، بينما
--   جدول products يفتقدها — وهو ما كسر الحفظ بعد تعديلات إعادة الهيكلة.
--
-- الإصلاح: إضافة سياسة ALL للأدمن على جدول products بنفس نمط
--          categories_admin_all تماماً (is_admin + صلاحية manage_products).
--
-- هذا الملف تم تنفيذه فعلياً على القاعدة الحية عبر الاتصال المباشر
-- (Session Pooler / IPv4). محفوظ هنا للتوثيق والمرجعية.
-- =====================================================================

-- تأكيد تفعيل RLS (موجود أصلاً، للتحصين فقط)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- إزالة أي نسخة قديمة بنفس الاسم لضمان إعادة التشغيل الآمنة (idempotent)
DROP POLICY IF EXISTS products_admin_all ON public.products;

-- سياسة الأدمن الكاملة (INSERT / UPDATE / DELETE / SELECT)
CREATE POLICY products_admin_all ON public.products
  FOR ALL
  USING (is_admin() AND has_admin_permission('manage_products'))
  WITH CHECK (is_admin() AND has_admin_permission('manage_products'));

-- =====================================================================
-- تحقق سريع بعد التشغيل (اختياري):
--   SELECT policyname, cmd FROM pg_policies
--   WHERE schemaname='public' AND tablename='products' ORDER BY policyname;
-- المفروض تشوف: products_admin_all (ALL) + products_select_active (SELECT)
-- =====================================================================


-- =====================================================================
-- إصلاح البند 1: عداد تنبيهات خاطئ في تبويب "الطلبات"
-- =====================================================================
--
-- السبب الجذري (تم تأكيده بالاتصال المباشر بقاعدة البيانات):
--   دالة get_admin_notification_counts كانت تحسب needs_admin_check لكل
--   الطلبات التي عليها علامة فحص (ocr_status='needs_admin_check' أو
--   review_reason غير فارغ) بغض النظر عن حالة الطلب. فوجود طلب واحد
--   حالته 'cancelled' (ملغي/محسوم) وما زال يحمل ocr_status='needs_admin_check'
--   كان يرفع العداد بـ 1 زائفة رغم أنه لا يحتاج أي انتباه.
--   كما أن الطلبات في حالة 'pending_review' كانت تُحسب مرتين (ضمن
--   pending_orders وضمن needs_admin_check معاً).
--
-- الإصلاح: قصر عدّاد needs_admin_check على الطلبات النشطة فقط —
--   استبعاد الحالات المحسومة (cancelled/completed/rejected) واستبعاد
--   pending_review (المحسوبة أصلاً) لمنع العدّ المزدوج.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_admin_notification_counts()
 RETURNS TABLE(pending_orders bigint, needs_admin_check bigint, pending_topups bigint, total_alerts bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pending_orders bigint := 0;
  v_needs_check bigint := 0;
  v_pending_topups bigint := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  IF public.has_admin_permission('manage_orders') THEN
    SELECT COUNT(*) INTO v_pending_orders
    FROM public.orders
    WHERE status = 'pending_review';

    -- طلبات نشطة عليها علامة فحص إداري، مع استبعاد الحالات المحسومة
    -- واستبعاد pending_review (محسوبة أصلاً) لمنع العدّ المزدوج والتنبيهات الزائفة.
    SELECT COUNT(*) INTO v_needs_check
    FROM public.orders
    WHERE status NOT IN ('cancelled', 'completed', 'rejected', 'pending_review')
      AND (
        ocr_status = 'needs_admin_check'
        OR NULLIF(btrim(COALESCE(review_reason, '')), '') IS NOT NULL
      );
  END IF;

  IF public.has_admin_permission('manage_wallets') THEN
    SELECT COUNT(*) INTO v_pending_topups
    FROM public.wallet_topups
    WHERE status = 'pending';
  END IF;

  RETURN QUERY SELECT
    v_pending_orders,
    v_needs_check,
    v_pending_topups,
    v_pending_orders + v_needs_check + v_pending_topups;
END;
$function$;
