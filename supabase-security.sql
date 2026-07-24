-- =====================================================================
-- RAIZEY STORE — Security SQL Script
-- شغّل هذا الملف كاملاً في Supabase SQL Editor
-- =====================================================================

-- ─────────────────────────────────────────────────────────────────────
-- PART 1: تفعيل RLS على جميع الجداول
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS orders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS products        ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS categories      ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS wallets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS wallet_topups   ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS notifications   ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS settings        ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS audit_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS coupons         ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────
-- PART 2: دالة مساعدة للتحقق من دور المدير
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 3: سياسات RLS — جدول profiles
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "profiles_select_own"  ON profiles;
DROP POLICY IF EXISTS "profiles_update_own"  ON profiles;
DROP POLICY IF EXISTS "profiles_admin_all"   ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own"  ON profiles;

-- المستخدم يقرأ ملفه الشخصي فقط + الأدمن يقرأ الكل
CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT USING (id = auth.uid() OR public.is_admin());

-- المستخدم يعدّل ملفه دون تغيير الدور
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND role = (SELECT role FROM profiles WHERE id = auth.uid())
  );

-- إنشاء الملف عند التسجيل
CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT WITH CHECK (id = auth.uid());

-- الأدمن: صلاحيات كاملة
CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 4: سياسات RLS — جدول orders
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "orders_select"        ON orders;
DROP POLICY IF EXISTS "orders_insert_own"    ON orders;
DROP POLICY IF EXISTS "orders_cancel_own"    ON orders;
DROP POLICY IF EXISTS "orders_admin_all"     ON orders;

-- المستخدم يرى طلباته فقط + الأدمن يرى الكل
CREATE POLICY "orders_select" ON orders
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

-- المستخدم ينشئ طلباً باسمه فقط
CREATE POLICY "orders_insert_own" ON orders
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- المستخدم يلغي فقط طلباته التي بحالة pending_review
CREATE POLICY "orders_cancel_own" ON orders
  FOR UPDATE
  USING (user_id = auth.uid() AND status = 'pending_review')
  WITH CHECK (user_id = auth.uid() AND status = 'cancelled');

-- الأدمن: صلاحيات كاملة
CREATE POLICY "orders_admin_all" ON orders
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 5: سياسات RLS — جدول wallets
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "wallets_select_own"  ON wallets;
DROP POLICY IF EXISTS "wallets_admin_all"   ON wallets;

-- المستخدم يقرأ رصيده فقط — لا يعدّله مباشرة أبداً
CREATE POLICY "wallets_select_own" ON wallets
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

-- التعديل فقط عبر RPCs آمنة (SECURITY DEFINER)
CREATE POLICY "wallets_admin_all" ON wallets
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 6: سياسات RLS — جداول أخرى
-- ─────────────────────────────────────────────────────────────────────

-- products: قراءة عامة للمنتجات النشطة + أدمن كامل
DROP POLICY IF EXISTS "products_select_active" ON products;
DROP POLICY IF EXISTS "products_admin_all"     ON products;
CREATE POLICY "products_select_active" ON products
  FOR SELECT USING (is_active = true OR public.is_admin());
CREATE POLICY "products_admin_all" ON products
  FOR ALL USING (public.is_admin());

-- categories: قراءة عامة + أدمن
DROP POLICY IF EXISTS "categories_select" ON categories;
DROP POLICY IF EXISTS "categories_admin"  ON categories;
CREATE POLICY "categories_select" ON categories FOR SELECT USING (true);
CREATE POLICY "categories_admin"  ON categories FOR ALL USING (public.is_admin());

-- payment_methods: قراءة عامة للنشطة + أدمن
DROP POLICY IF EXISTS "payment_methods_select" ON payment_methods;
DROP POLICY IF EXISTS "payment_methods_admin"  ON payment_methods;
CREATE POLICY "payment_methods_select" ON payment_methods
  FOR SELECT USING (is_active = true OR public.is_admin());
CREATE POLICY "payment_methods_admin" ON payment_methods
  FOR ALL USING (public.is_admin());

-- settings: قراءة للمستخدمين المسجلين + أدمن كامل
DROP POLICY IF EXISTS "settings_select" ON settings;
DROP POLICY IF EXISTS "settings_admin"  ON settings;
CREATE POLICY "settings_select" ON settings
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "settings_admin" ON settings
  FOR ALL USING (public.is_admin());

-- notifications
DROP POLICY IF EXISTS "notifications_select"       ON notifications;
DROP POLICY IF EXISTS "notifications_insert_admin" ON notifications;
DROP POLICY IF EXISTS "notifications_update_own"   ON notifications;
CREATE POLICY "notifications_select" ON notifications
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());
CREATE POLICY "notifications_insert_admin" ON notifications
  FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY "notifications_update_own" ON notifications
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- wallet_topups
DROP POLICY IF EXISTS "topups_select" ON wallet_topups;
DROP POLICY IF EXISTS "topups_insert" ON wallet_topups;
DROP POLICY IF EXISTS "topups_admin"  ON wallet_topups;
CREATE POLICY "topups_select" ON wallet_topups
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());
CREATE POLICY "topups_insert" ON wallet_topups
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "topups_admin" ON wallet_topups
  FOR ALL USING (public.is_admin());

-- audit_logs
DROP POLICY IF EXISTS "audit_logs_admin"  ON audit_logs;
DROP POLICY IF EXISTS "audit_logs_insert" ON audit_logs;
CREATE POLICY "audit_logs_admin"  ON audit_logs FOR ALL USING (public.is_admin());
CREATE POLICY "audit_logs_insert" ON audit_logs
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- coupons
DROP POLICY IF EXISTS "coupons_select" ON coupons;
DROP POLICY IF EXISTS "coupons_admin"  ON coupons;
CREATE POLICY "coupons_select" ON coupons
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "coupons_admin" ON coupons
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 7: RPC آمنة — create_wallet_order (atomic transaction)
-- السعر يُحسب من قاعدة البيانات مع إضافة سعر الخيار الفرعي المختار
-- FOR UPDATE يمنع race conditions على رصيد المحفظة
-- ─────────────────────────────────────────────────────────────────────
-- تحديث أعمدة الجداول لدعم الخيارات الفرعية
ALTER TABLE products ADD COLUMN IF NOT EXISTS has_options BOOLEAN DEFAULT FALSE;
ALTER TABLE products ADD COLUMN IF NOT EXISTS options JSONB DEFAULT '[]'::jsonb;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS selected_option JSONB DEFAULT NULL;

CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id         uuid,
  p_field_values       jsonb DEFAULT '{}',
  p_coupon_code        text  DEFAULT NULL,
  p_selected_option_id text  DEFAULT NULL
)
RETURNS TABLE(id uuid, status text, price_sdg_snapshot numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        uuid    := auth.uid();
  v_product        products%ROWTYPE;
  v_wallet_balance numeric;
  v_rate           numeric;
  v_margin         numeric;
  v_base_price_usd numeric;
  v_opt_price_usd  numeric := 0;
  v_opt_item       jsonb;
  v_selected_opt   jsonb   := NULL;
  v_price_sdg      numeric;
  v_coupon_id      uuid;
  v_discount_pct   numeric := 0;
  v_order_id       uuid;
  v_order_status   text    := 'pending_review';
BEGIN
  -- التحقق من تسجيل الدخول
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- جلب بيانات المنتج من قاعدة البيانات
  SELECT * INTO v_product
  FROM products
  WHERE products.id = p_product_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  v_base_price_usd := COALESCE(v_product.price_usd, 0);

  -- إذا تم اختيار خيار فرعي، البحث عنه وحساب سعره
  IF p_selected_option_id IS NOT NULL AND v_product.options IS NOT NULL THEN
    FOR v_opt_item IN SELECT * FROM jsonb_array_elements(v_product.options)
    LOOP
      IF (v_opt_item->>'id') = p_selected_option_id THEN
        v_opt_price_usd := COALESCE((v_opt_item->>'price_usd')::numeric, (v_opt_item->>'price')::numeric, 0);
        v_selected_opt  := jsonb_build_object(
          'id', v_opt_item->>'id',
          'label', v_opt_item->>'label',
          'price_usd', v_opt_price_usd
        );
        EXIT;
      END IF;
    END LOOP;
  END IF;

  -- حساب السعر بالجنيه السوداني من إعدادات المتجر
  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'      LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  -- السعر الإجمالي بالدولار = السعر الأساسي للمنتج + سعر الخيار الفرعي
  v_price_sdg := (v_base_price_usd + v_opt_price_usd) * v_rate * (1 + v_margin / 100.0);

  IF v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- تطبيق كوبون الخصم إن وُجد
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) != '' THEN
    SELECT c.id, c.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   coupons c
    WHERE  upper(c.code) = upper(trim(p_coupon_code))
      AND  c.is_active = true
      AND  (c.expires_at IS NULL OR c.expires_at > now())
      AND  (c.max_uses   IS NULL OR c.current_uses < c.max_uses);

    IF FOUND THEN
      v_price_sdg := v_price_sdg * (1.0 - v_discount_pct / 100.0);
    END IF;
  END IF;

  v_price_sdg := round(v_price_sdg);

  -- قفل رصيد المحفظة لمنع السحب المزدوج (FOR UPDATE)
  SELECT balance INTO v_wallet_balance
  FROM   wallets
  WHERE  user_id = v_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  IF v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  -- خصم الرصيد
  UPDATE wallets
  SET    balance    = balance - v_price_sdg,
         updated_at = now()
  WHERE  user_id = v_user_id;

  -- إنشاء الطلب بحالة pending_review ليظهر في لوحة الأدمن
  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, selected_option, payment_type, status
  )
  VALUES (
    v_user_id, p_product_id, v_product.name,
    v_price_sdg, COALESCE(p_field_values, '{}'), v_selected_opt, 'wallet', v_order_status
  )
  RETURNING orders.id INTO v_order_id;

  -- تحديث عداد الكوبون
  IF v_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET current_uses = current_uses + 1
    WHERE id = v_coupon_id;
  END IF;

  RETURN QUERY SELECT v_order_id, v_order_status, v_price_sdg;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 8: RPC آمنة — admin_refund_wallet
-- تُستخدَم عند رفض طلب محفظة لإعادة الرصيد للمستخدم
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_refund_wallet(
  p_user_id  uuid,
  p_amount   numeric,
  p_order_id uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  UPDATE wallets
  SET    balance    = balance + p_amount,
         updated_at = now()
  WHERE  user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found for user %', p_user_id;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 9: سياسات Storage Bucket — receipts
-- تأكد أن bucket باسم "receipts" موجود في Storage > Buckets
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "receipts_upload_own" ON storage.objects;
DROP POLICY IF EXISTS "receipts_read_own"   ON storage.objects;
DROP POLICY IF EXISTS "receipts_admin_read" ON storage.objects;

-- المستخدم يرفع فقط في مجلده الخاص
CREATE POLICY "receipts_upload_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- المستخدم يقرأ ملفاته فقط
CREATE POLICY "receipts_read_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- الأدمن يقرأ جميع الإيصالات
CREATE POLICY "receipts_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'receipts'
    AND public.is_admin()
  );

-- ─────────────────────────────────────────────────────────────────────
-- PART 10: إضافة عمود receipt_hash لـ wallet_topups إن لم يكن موجوداً
-- ─────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'wallet_topups' AND column_name = 'receipt_hash'
  ) THEN
    ALTER TABLE wallet_topups ADD COLUMN receipt_hash text;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 11: Indexes لتحسين أداء استعلامات الأدمن
-- ─────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_status      ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id     ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_receipt_hash
  ON orders(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_topups_receipt_hash
  ON wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────
-- ✅ انتهى — الملف جاهز للتشغيل في Supabase SQL Editor
-- ─────────────────────────────────────────────────────────────────────
