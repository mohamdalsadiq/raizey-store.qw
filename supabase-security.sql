-- =====================================================================
-- ⛔ ملف مهجور (DEPRECATED) — للأرشيف والمراجعة فقط، ممنوع تشغيله
-- =====================================================================
-- RAIZ3Y STORE — Complete Secured SQL Script (نسخة قديمة)
--
-- لماذا مُعطّل؟ تشغيل هذا الملف اليوم يُعيد فتح ثغرات حرجة تم سدّها:
--   1) كل سياساته مكتوبة بدون "TO authenticated" → تُنشأ للدور public،
--      أي أن الزائر غير المسجّل (anon) يدخل في نطاقها. سياسات PERMISSIVE
--      تُجمع بـ OR، فسياسة واحدة فضفاضة تُبطل كل السياسات المحكمة.
--   2) يُعيد إنشاء نسخة قديمة من create_wallet_order بلا تحقق من الحظر
--      (is_banned) ولا من وضع الصيانة، وتعتمد أعمدة غير موجودة أصلاً
--      (products.price_sdg) فتفشل أو تُنتج أسعاراً خاطئة.
--   3) "Public Access Receipts" في نسخ سابقة سمحت لأي زائر بقراءة إيصال
--      دفع أي زبون (IDOR كامل على 51 إيصالاً).
--
-- ✅ الملف الساري الآن: supabase-critical-fixes-3.sql ثم -4.sql
--    (مُطبَّقان فعلياً على القاعدة ومُتحقَّق منهما باختبار اختراق حقيقي)
-- =====================================================================

-- حاجز تنفيذ: يوقف السكربت فوراً لو حاول أحد تشغيله بالخطأ.
DO $$
BEGIN
  RAISE EXCEPTION
    'ملف مهجور: supabase-security.sql — تشغيله يُعيد فتح ثغرات أمنية. استخدم supabase-critical-fixes-3.sql ثم -4.sql';
END $$;


-- ─────────────────────────────────────────────────────────────────────
-- PART 0: تحويل bucket الإيصالات من Public إلى Private (حماية IDOR)
-- ─────────────────────────────────────────────────────────────────────
UPDATE storage.buckets
SET public = false
WHERE id = 'receipts';

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
-- PART 4: حماية الأسعار وسجل الطلبات — جدول orders
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION verify_order_price_before_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_product_price NUMERIC;
    v_option_price NUMERIC;
    v_expected_price NUMERIC;
BEGIN
    SELECT price_sdg INTO v_product_price
    FROM products
    WHERE id = NEW.product_id;

    IF v_product_price IS NULL THEN
        RAISE EXCEPTION 'المنتج غير موجود';
    END IF;

    v_expected_price := v_product_price;

    IF NEW.selected_option IS NOT NULL AND (NEW.selected_option->>'price') IS NOT NULL THEN
        v_option_price := (NEW.selected_option->>'price')::NUMERIC;
        IF v_option_price > 0 THEN
            v_expected_price := v_option_price;
        END IF;
    END IF;

    -- السماح بالسعر المخفَّض (مع كوبون) لكن ليس بسعر أقل من 1% من المتوقع
    IF NEW.coupon_id IS NULL AND NEW.price_sdg_snapshot < (v_expected_price * 0.99) THEN
        RAISE EXCEPTION 'عذراً، تم التلاعب بسعر الطلب!';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_verify_order_price ON orders;
CREATE TRIGGER trg_verify_order_price
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION verify_order_price_before_insert();

-- سياسات RLS لجدول orders
DROP POLICY IF EXISTS "orders_select"        ON orders;
DROP POLICY IF EXISTS "orders_insert_own"    ON orders;
DROP POLICY IF EXISTS "orders_cancel_own"    ON orders;
DROP POLICY IF EXISTS "orders_admin_all"     ON orders;

CREATE POLICY "orders_select" ON orders
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "orders_insert_own" ON orders
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "orders_cancel_own" ON orders
  FOR UPDATE
  USING (user_id = auth.uid() AND status = 'pending_review')
  WITH CHECK (user_id = auth.uid() AND status = 'cancelled');

CREATE POLICY "orders_admin_all" ON orders
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 5: سياسات RLS — جدول wallets
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "wallets_select_own"  ON wallets;
DROP POLICY IF EXISTS "wallets_admin_all"   ON wallets;

CREATE POLICY "wallets_select_own" ON wallets
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "wallets_admin_all" ON wallets
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 6: سياسات RLS — باقي الجداول
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

-- wallet_topups: كل مستخدم يرى طلباته + أدمن
DROP POLICY IF EXISTS "topups_select_own"  ON wallet_topups;
DROP POLICY IF EXISTS "topups_insert_own"  ON wallet_topups;
DROP POLICY IF EXISTS "topups_admin_all"   ON wallet_topups;
CREATE POLICY "topups_select_own" ON wallet_topups
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());
CREATE POLICY "topups_insert_own" ON wallet_topups
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "topups_admin_all" ON wallet_topups
  FOR ALL USING (public.is_admin());

-- notifications: كل مستخدم يرى إشعاراته فقط
DROP POLICY IF EXISTS "notifications_select_own" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_own" ON notifications;
DROP POLICY IF EXISTS "notifications_admin_all"  ON notifications;
CREATE POLICY "notifications_select_own" ON notifications
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "notifications_insert_own" ON notifications
  FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY "notifications_admin_all" ON notifications
  FOR ALL USING (public.is_admin());

-- settings: قراءة عامة (أسعار الصرف) + كتابة للأدمن فقط
DROP POLICY IF EXISTS "settings_select" ON settings;
DROP POLICY IF EXISTS "settings_admin"  ON settings;
CREATE POLICY "settings_select" ON settings FOR SELECT USING (true);
CREATE POLICY "settings_admin"  ON settings FOR ALL USING (public.is_admin());

-- audit_logs: الأدمن فقط
DROP POLICY IF EXISTS "audit_logs_admin" ON audit_logs;
CREATE POLICY "audit_logs_admin" ON audit_logs
  FOR ALL USING (public.is_admin());

-- coupons: الكوبونات للأدمن فقط (الفحص يتم عبر RPC)
DROP POLICY IF EXISTS "coupons_select_admin_only" ON coupons;
DROP POLICY IF EXISTS "coupons_admin"             ON coupons;
CREATE POLICY "coupons_select_admin_only" ON coupons
  FOR SELECT USING (public.is_admin());
CREATE POLICY "coupons_admin" ON coupons
  FOR ALL USING (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────
-- PART 7: RPC آمنة — create_wallet_order (خصم المحفظة ذرياً)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id       uuid,
  p_field_values     jsonb    DEFAULT '{}',
  p_coupon_code      text     DEFAULT NULL,
  p_selected_option_id text   DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id        uuid := auth.uid();
  v_product        RECORD;
  v_wallet_balance NUMERIC;
  v_price_sdg      NUMERIC;
  v_option_price   NUMERIC;
  v_coupon_id      uuid;
  v_discount_pct   numeric := 0;
  v_order_id       uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
  END IF;

  SELECT * INTO v_product FROM products WHERE id = p_product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  -- حساب السعر من قاعدة البيانات (لا من الفرونت إند)
  v_price_sdg := v_product.price_sdg;

  IF p_selected_option_id IS NOT NULL AND p_selected_option_id != '' THEN
    SELECT (opt->>'price_sdg')::NUMERIC INTO v_option_price
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = p_selected_option_id;

    IF v_option_price IS NOT NULL AND v_option_price > 0 THEN
      v_price_sdg := v_option_price;
    END IF;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- تطبيق كوبون الخصم (ذرياً مع قفل الصف)
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) != '' THEN
    SELECT c.id, c.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   coupons c
    WHERE  upper(c.code) = upper(trim(p_coupon_code))
      AND  c.is_active = true
      AND  (c.usage_limit IS NULL OR c.usage_count < c.usage_limit)
      AND  (c.expires_at IS NULL OR c.expires_at > NOW())
    FOR UPDATE;

    IF FOUND THEN
      v_price_sdg := v_price_sdg * (1.0 - v_discount_pct / 100.0);
      UPDATE coupons SET usage_count = usage_count + 1 WHERE id = v_coupon_id;
    END IF;
  END IF;

  -- التحقق من رصيد المحفظة (مع قفل لمنع السحب المزدوج)
  SELECT balance INTO v_wallet_balance
  FROM wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  -- خصم الرصيد
  UPDATE wallets SET balance = balance - v_price_sdg WHERE user_id = v_user_id;

  -- إنشاء الطلب
  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, selected_option,
    payment_type, status, coupon_id
  )
  VALUES (
    v_user_id, p_product_id, v_product.name,
    ROUND(v_price_sdg), p_field_values, NULL,
    'wallet', 'in_progress', v_coupon_id
  )
  RETURNING orders.id INTO v_order_id;

  RETURN QUERY SELECT v_order_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 8: RPC آمنة — use_coupon_atomic (للتحويل البنكي — منع Race Condition)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.use_coupon_atomic(p_code TEXT)
RETURNS TABLE(coupon_id UUID, discount_percent NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_coupon RECORD;
BEGIN
    -- قفل الصف لمنع الاستخدام المتزامن من أكثر من جلسة
    SELECT * INTO v_coupon
    FROM coupons
    WHERE upper(code) = upper(trim(p_code))
      AND is_active = true
      AND (usage_limit IS NULL OR usage_count < usage_limit)
      AND (expires_at IS NULL OR expires_at > NOW())
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الكود غير صالح أو انتهت صلاحيته';
    END IF;

    UPDATE coupons
    SET usage_count = usage_count + 1
    WHERE id = v_coupon.id;

    RETURN QUERY SELECT
        v_coupon.id AS coupon_id,
        v_coupon.discount_percent AS discount_percent;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 9: RPC آمنة — validate_coupon (للعرض فقط — لا تغيير في DB)
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_coupon(p_code TEXT)
RETURNS TABLE(coupon_id UUID, discount_percent NUMERIC)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT id AS coupon_id, discount_percent
  FROM coupons
  WHERE upper(code) = upper(trim(p_code))
    AND is_active = true
    AND (usage_limit IS NULL OR usage_count < usage_limit)
    AND (expires_at IS NULL OR expires_at > NOW());
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 10: RPC — process_referral_commission
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_referral_commission(
  p_user_id  uuid,
  p_order_id uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_referrer_id uuid;
  v_order_price numeric;
  v_commission  numeric;
BEGIN
  SELECT referred_by INTO v_referrer_id FROM profiles WHERE id = p_user_id;
  IF v_referrer_id IS NULL THEN RETURN; END IF;

  SELECT price_sdg_snapshot INTO v_order_price FROM orders WHERE id = p_order_id;
  IF v_order_price IS NULL THEN RETURN; END IF;

  v_commission := ROUND(v_order_price * 0.02, 2); -- 2% عمولة
  UPDATE wallets SET balance = balance + v_commission WHERE user_id = v_referrer_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 11: سياسات Storage Bucket — receipts (PRIVATE)
-- ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "receipts_upload_own" ON storage.objects;
DROP POLICY IF EXISTS "receipts_read_own"   ON storage.objects;
DROP POLICY IF EXISTS "receipts_admin_read" ON storage.objects;

-- رفع: كل مستخدم يرفع في مجلده الخاص فقط
CREATE POLICY "receipts_upload_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- قراءة: كل مستخدم يقرأ ملفاته فقط
CREATE POLICY "receipts_read_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- قراءة الأدمن: يقرأ كل الإيصالات
CREATE POLICY "receipts_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'receipts'
    AND public.is_admin()
  );

-- ─────────────────────────────────────────────────────────────────────
-- PART 12: إضافة الأعمدة الناقصة
-- ─────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'wallet_topups' AND column_name = 'receipt_hash'
  ) THEN
    ALTER TABLE wallet_topups ADD COLUMN receipt_hash text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'ocr_status'
  ) THEN
    ALTER TABLE orders ADD COLUMN ocr_status text DEFAULT 'needs_review';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'amount_verified'
  ) THEN
    ALTER TABLE orders ADD COLUMN amount_verified boolean DEFAULT false;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- PART 13: Indexes لتحسين الأداء
-- ─────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_status      ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id     ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_receipt_hash
  ON orders(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_topups_receipt_hash
  ON wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_role
  ON profiles(role);
CREATE INDEX IF NOT EXISTS idx_coupons_code
  ON coupons(upper(code)) WHERE is_active = true;
