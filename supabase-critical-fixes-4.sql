-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — الجزء 2 (تكملة): تنظيف السياسات القديمة + الصلاحيات
-- شغّل هذا الملف بعد supabase-critical-fixes-3.sql
--
-- ⚠️ سبب وجود هذا الملف:
-- الفحص المباشر لقاعدة البيانات أظهر أن سياسات قديمة (بأسماء عربية أو
-- بأسماء Supabase الافتراضية) ما زالت موجودة جنباً إلى جنب مع السياسات
-- الجديدة. وبما أن سياسات RLS من نوع PERMISSIVE تُجمَع بعلاقة OR، فإن
-- سياسة واحدة فضفاضة مثل:
--     "Allow select for all users on orders"  USING (true)
-- تُبطل مفعول كل السياسات الصارمة الجديدة على نفس الجدول تماماً.
-- لذلك التنظيف هنا ليس تجميلاً — هو شرط أساسي لعمل الحماية.
--
-- هذا الملف idempotent (آمن للتشغيل أكثر من مرة) ولا يحذف أي ميزة:
-- كل ما يفعله هو إزالة المسارات المفتوحة وترك المسارات المصرَّح بها.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- PART 1: قائمة بيضاء للسياسات — حذف كل ما هو خارجها
-- ═══════════════════════════════════════════════════════════════════
-- المنطق: أي سياسة على schema public اسمها غير مذكور في القائمة أدناه
-- هي سياسة قديمة/متراكمة → تُحذف. القائمة تطابق تماماً السياسات التي
-- ينشئها supabase-critical-fixes-3.sql (والتي دُقّقت بندًا بندًا).
DO $$
DECLARE
  r RECORD;
  v_allowed text[] := ARRAY[
    -- profiles
    'profiles_select_own','profiles_insert_own','profiles_update_own','profiles_admin_all',
    -- orders
    'orders_select','orders_insert_own','orders_cancel_own','orders_admin_all',
    -- wallets
    'wallets_select_own','wallets_admin_all',
    -- wallet_topups
    'topups_select_own','topups_insert_own','topups_admin_all',
    -- كتالوج
    'products_select_active','products_admin_all',
    'categories_select','categories_admin',
    'payment_methods_select','payment_methods_admin',
    -- notifications
    'notifications_select_own','notifications_update_own','notifications_admin_all',
    -- إعدادات
    'settings_select','settings_admin',
    'store_settings_select','store_settings_admin',
    -- سجلات التدقيق
    'audit_logs_select_admin','audit_logs_insert_customer','audit_logs_admin',
    'admin_audit_select','admin_audit_insert',
    -- صلاحيات الأدمن
    'admin_perms_select','admin_perms_super_admin',
    -- كروت الهدايا والكوبونات
    'gift_cards_select_own','gift_cards_admin',
    'coupons_select_admin_only','coupons_admin',
    -- الإحالات
    'referral_milestones_select','referral_milestones_admin',
    'referral_payouts_select','referral_payouts_admin'
  ];
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND NOT (policyname = ANY (v_allowed))
  LOOP
    RAISE NOTICE 'حذف سياسة قديمة: %.% → %', r.schemaname, r.tablename, r.policyname;
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 2: RLS مفعّل على كل جدول + لا جدول بلا سياسة
-- ═══════════════════════════════════════════════════════════════════
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- شبكة أمان: أي جدول عليه RLS وبلا أي سياسة يكون محجوباً كلياً — نمنحه
-- سياسة "أدمن فقط" حتى لا تنكسر لوحة التحكم بصمت عند إضافة جدول جديد.
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity
      AND NOT EXISTS (
        SELECT 1 FROM pg_policies p
        WHERE p.schemaname = 'public' AND p.tablename = c.relname
      )
  LOOP
    RAISE NOTICE 'جدول بلا سياسات — إضافة سياسة أدمن فقط: %', t;
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
      'USING (public.is_admin()) WITH CHECK (public.is_admin())',
      t || '_admin_fallback', t);
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 3: صلاحيات الجداول (GRANT) — الطبقة الثانية بعد RLS
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 المشكلة المكتشفة: الدورين anon و authenticated كانا يملكان
--    DELETE, INSERT, UPDATE, TRUNCATE, TRIGGER, REFERENCES على كل جدول
--    في public. RLS يحجب معظم ذلك، لكن الاعتماد على طبقة واحدة خطر:
--    أي سياسة فضفاضة واحدة تتحول فوراً إلى حذف/تعديل كامل للجدول.
--    القاعدة الصحيحة: امنح أقل صلاحية ممكنة، ثم اترك RLS يفلتر الصفوف.

-- 3.1 تصفير كل شيء عن anon و authenticated (نعيد المنح بدقة بعدها)
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated', t);
  END LOOP;
END $$;

-- 3.2 anon (زائر غير مسجّل): قراءة فقط، وعلى بيانات العرض العامة فقط
--     لا يقرأ الطلبات ولا المحافظ ولا الملفات ولا الكوبونات ولا الإيصالات.
GRANT SELECT ON public.products        TO anon;
GRANT SELECT ON public.categories      TO anon;
GRANT SELECT ON public.settings        TO anon;
GRANT SELECT ON public.store_settings  TO anon;

-- 3.3 authenticated: القراءة على كل الجداول (RLS يحدد أي صفوف فعلياً)
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
  END LOOP;
END $$;

-- 3.4 الكتابة للمستخدم المسجّل — فقط حيث يوجد مسار مصرَّح به
--     ملاحظة مهمة: الأدمن نفسه يعمل بدور authenticated، فسياسات
--     *_admin_all هي التي تمنحه الوصول الكامل داخل هذه الصلاحيات.
GRANT INSERT, UPDATE, DELETE ON public.products                    TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.categories                  TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.payment_methods             TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.coupons                     TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.gift_cards                  TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.settings                    TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.store_settings              TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.referral_milestones         TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.referral_milestone_payouts  TO authenticated; -- أدمن (RLS)
GRANT INSERT, UPDATE, DELETE ON public.notifications               TO authenticated; -- أدمن ينشئ / العميل is_read
GRANT INSERT, UPDATE, DELETE ON public.orders                      TO authenticated; -- العميل ينشئ/يلغي + أدمن
GRANT INSERT, UPDATE, DELETE ON public.wallet_topups               TO authenticated; -- العميل يطلب شحن + أدمن
GRANT INSERT, UPDATE, DELETE ON public.profiles                    TO authenticated; -- العميل ملفه + أدمن
GRANT INSERT, UPDATE, DELETE ON public.wallets                     TO authenticated; -- أدمن فقط (RLS)
GRANT INSERT, UPDATE, DELETE ON public.admin_permissions           TO authenticated; -- سوبر أدمن فقط (RLS)

-- 3.5 سجلات التدقيق: إضافة فقط (append-only) — لا تعديل ولا حذف لأي دور
--     حتى الأدمن لا يستطيع محو أثر عملية تمت. هذه نقطة أمان جوهرية.
GRANT INSERT ON public.audit_logs       TO authenticated;
GRANT INSERT ON public.admin_audit_logs TO authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON public.audit_logs       FROM anon, authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON public.admin_audit_logs FROM anon, authenticated;

-- 3.6 التتابعات (sequences) — لازمة لأعمدة serial إن وُجدت
DO $$
DECLARE
  s text;
BEGIN
  FOR s IN
    SELECT sequencename FROM pg_sequences WHERE schemaname = 'public'
  LOOP
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO authenticated', s);
  END LOOP;
END $$;

-- 3.7 منع إنشاء أي كائن جديد في public من الأدوار العامة
REVOKE CREATE ON SCHEMA public FROM anon, authenticated;
GRANT  USAGE  ON SCHEMA public TO   anon, authenticated;

-- 3.8 الجداول المستقبلية لا تُمنح تلقائياً لأي دور عام
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon;


-- ═══════════════════════════════════════════════════════════════════
-- PART 4: تثبيت search_path على كل دوال SECURITY DEFINER
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 الثغرة: دالة SECURITY DEFINER بلا "SET search_path" تُنفَّذ بصلاحيات
--    مالكها (postgres) لكن تحلّ أسماء الجداول حسب search_path المُرسَل من
--    المنادي. مستخدم يملك CREATE في أي schema يستطيع زرع جدول وهمي باسم
--    "profiles" وخداع الدالة لتقرأ منه → ترقية صلاحيات كاملة.
--    الفحص أظهر 5 دوال بلا تثبيت: award_loyalty_points, handle_new_user,
--    increment_coupon_usage, process_referral_commission, redeem_loyalty_points.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND (p.proconfig IS NULL
           OR NOT EXISTS (
             SELECT 1 FROM unnest(p.proconfig) cfg
             WHERE cfg LIKE 'search_path=%'
           ))
  LOOP
    RAISE NOTICE 'تثبيت search_path على: %', r.sig;
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 4.5: حذف النسخ القديمة (Overloads) من الدوال الحسّاسة
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 ثغرة تجاوز كاملة: الفحص أظهر بقاء نسخة قديمة بثلاثة معاملات
--    create_wallet_order(uuid, jsonb, text) جنباً إلى جنب مع النسخة
--    الآمنة الجديدة بخمسة معاملات. النسخة القديمة:
--      • لا تتحقق من الحظر (is_banned)
--      • لا تتحقق من وضع الصيانة
--      • لا تفرض اختيار الخيار الفرعي
--      • تستخدم أعمدة قديمة غير موجودة
--    وبما أن PostgREST يختار النسخة حسب المعاملات المُرسَلة، كان يكفي أن
--    ينادي المهاجم الدالة بثلاثة معاملات فقط لتجاوز كل الفحوصات الجديدة.
--    كما أن وجود نسختين يسبب خطأ 42725 (function is not unique).
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text);
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);


-- ═══════════════════════════════════════════════════════════════════
-- PART 5: صلاحيات تنفيذ الدوال (EXECUTE)
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 Postgres يمنح EXECUTE إلى PUBLIC تلقائياً على كل دالة جديدة، ما يعني
--    أن زائراً غير مسجّل كان يستطيع مناداة أي RPC مباشرة عبر REST API.
-- القاعدة: PUBLIC/anon لا يملك تنفيذ أي دالة، إلا الدوال البوليانية
-- الثلاث التي تحتاجها سياسات RLS نفسها (وهي لا تكشف أي بيانات).
DO $$
DECLARE
  r RECORD;
  v_anon_ok text[] := ARRAY['is_admin','is_super_admin','is_banned'];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon',   r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);

    IF r.proname = ANY (v_anon_ok) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', r.sig);
    END IF;
  END LOOP;
END $$;

-- دوال الأدمن الحسّاسة: الحاجز الحقيقي هو is_admin() داخلها، وهذا سحب
-- إضافي صريح لأي وصول من زائر غير مسجّل (طبقة ثانية).
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('process_referral_commission','admin_confirm_topup',
                        'admin_refund_wallet','bootstrap_super_admin',
                        'append_admin_audit_log')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, PUBLIC', r.sig);
  END LOOP;
END $$;

-- ⚠️ service_role: يتجاوز RLS بالكامل. لا يُستخدم في أي كود فرونت إند،
--    ولا يُذكر داخل أي سياسة، ولا يُخزَّن في أي ملف يُرسَل للمتصفح.
--    كل السياسات في هذا المشروع محدَّدة بـ TO anon / TO authenticated فقط.


-- ═══════════════════════════════════════════════════════════════════
-- PART 6: Storage — الإيصالات خاصة (إغلاق IDOR)
-- ═══════════════════════════════════════════════════════════════════
-- الفحص أظهر أن bucket "receipts" ما زال public = true، أي أن أي شخص
-- يملك (أو يخمّن) رابط الملف يقرأ إيصال دفع أي زبون آخر.
UPDATE storage.buckets SET public = false WHERE id = 'receipts';

-- product-images يبقى عاماً بشكل مقصود (صور المنتجات المعروضة للجميع)
-- لكن الكتابة فيه للأدمن فقط.
DROP POLICY IF EXISTS "product_images_public_read" ON storage.objects;
DROP POLICY IF EXISTS "product_images_admin_write" ON storage.objects;
DROP POLICY IF EXISTS "product_images_admin_update" ON storage.objects;
DROP POLICY IF EXISTS "product_images_admin_delete" ON storage.objects;

CREATE POLICY "product_images_public_read" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'product-images');

CREATE POLICY "product_images_admin_write" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'product-images' AND public.is_admin());

CREATE POLICY "product_images_admin_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'product-images' AND public.is_admin())
  WITH CHECK (bucket_id = 'product-images' AND public.is_admin());

CREATE POLICY "product_images_admin_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'product-images' AND public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- 6.1 تنظيف سياسات storage.objects القديمة (نفس منطق القائمة البيضاء)
-- ─────────────────────────────────────────────────────────────────────
-- 🔴 أخطر ما تبقّى: سياسة قديمة اسمها "Public Access Receipts" من نوع
--    SELECT TO public على storage.objects. تحويل الـ bucket إلى private
--    وحده لا يكفي إطلاقاً — قراءة الملفات عبر Storage API تخضع لسياسات
--    RLS على storage.objects، وهذه السياسة كانت تسمح لأي زائر بقراءة
--    إيصال دفع أي زبون (IDOR كامل) رغم أن الـ bucket صار خاصاً.
DO $$
DECLARE
  r RECORD;
  v_allowed text[] := ARRAY[
    'receipts_upload_own','receipts_read_own','receipts_admin_read','receipts_admin_manage',
    'product_images_public_read','product_images_admin_write',
    'product_images_admin_update','product_images_admin_delete'
  ];
BEGIN
  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND NOT (policyname = ANY (v_allowed))
  LOOP
    RAISE NOTICE 'حذف سياسة storage قديمة: %', r.policyname;
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
  END LOOP;
END $$;

-- storage.objects: لا كتابة مباشرة لزائر غير مسجّل بأي حال
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON storage.objects FROM anon;


-- ═══════════════════════════════════════════════════════════════════
-- PART 7: تحقق نهائي — كل استعلام يجب أن يرجع نتيجة فارغة
-- ═══════════════════════════════════════════════════════════════════

-- 7.1 جدول بلا RLS
SELECT tablename AS "❌ جدول بلا RLS"
FROM pg_tables t
WHERE schemaname = 'public'
  AND NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = t.tablename AND c.relrowsecurity);

-- 7.2 جدول عليه RLS وبلا أي سياسة (محجوب كلياً)
SELECT c.relname AS "❌ جدول بلا سياسات"
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity
  AND NOT EXISTS (SELECT 1 FROM pg_policies p
                  WHERE p.schemaname = 'public' AND p.tablename = c.relname);

-- 7.3 🔴 الأهم: أي سياسة تمنح وصولاً عاماً على جدول حسّاس
SELECT tablename, policyname, cmd, roles::text AS roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('orders','wallets','wallet_topups','profiles','coupons',
                    'gift_cards','admin_permissions','admin_audit_logs',
                    'audit_logs','referral_milestone_payouts','notifications')
  AND ('anon' = ANY(roles) OR 'public' = ANY(roles));

-- 7.4 سياسة كتابة بلا WITH CHECK (تسمح بتعديل أي عمود لأي قيمة)
SELECT tablename, policyname, cmd AS "❌ كتابة بلا WITH CHECK"
FROM pg_policies
WHERE schemaname = 'public'
  AND cmd IN ('INSERT','UPDATE','ALL')
  AND with_check IS NULL
  AND qual IS DISTINCT FROM 'is_admin()';

-- 7.5 anon يملك أي صلاحية كتابة على أي جدول
SELECT table_name, privilege_type AS "❌ كتابة متاحة لـ anon"
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee = 'anon'
  AND privilege_type <> 'SELECT';

-- 7.6 دالة SECURITY DEFINER بلا search_path مثبّت
SELECT p.proname AS "❌ دالة بلا search_path"
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef
  AND (p.proconfig IS NULL
       OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'));

-- 7.7 دالة ما زال anon ينفّذها (المسموح فقط: is_admin/is_super_admin/is_banned)
SELECT p.proname AS "⚠️ دالة قابلة للتنفيذ من anon"
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND p.proname NOT IN ('is_admin','is_super_admin','is_banned');

-- 7.8 bucket خاص يجب أن يكون public = false
SELECT id, public AS "⚠️ حالة bucket" FROM storage.buckets WHERE id = 'receipts';

-- ═══════════════════════════════════════════════════════════════════
-- ✅ انتهى
-- ═══════════════════════════════════════════════════════════════════
