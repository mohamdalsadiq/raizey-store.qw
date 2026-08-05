-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — الجزء 2: أمان قاعدة البيانات (RLS + الصلاحيات)
-- شغّل هذا الملف كاملاً في Supabase SQL Editor
--
-- هذا الملف idempotent (آمن للتشغيل أكثر من مرة) ويُصلح الحالة الفعلية
-- لقاعدة البيانات كما هي الآن — وليس كما كانت مفترضة في الملفات السابقة.
--
-- ⚠️ سبب وجود هذا الملف: الملفات السابقة (supabase-security.sql و
-- supabase-critical-fixes.sql و -2.sql) تشير إلى أعمدة غير موجودة
-- فعلياً في قاعدة البيانات، لذلك فشلت عند التشغيل وتوقفت في منتصفها،
-- وبقيت جداول حسّاسة كثيرة بلا RLS إطلاقاً.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- PART 0: الأعمدة الناقصة (سبب فشل كل الملفات السابقة)
-- ═══════════════════════════════════════════════════════════════════
-- coupon_id: يستخدمه trigger التحقق من السعر و create_wallet_order
ALTER TABLE orders ADD COLUMN IF NOT EXISTS coupon_id uuid REFERENCES coupons(id) ON DELETE SET NULL;
-- field_labels: أسماء الحقول المقروءة في لوحة الأدمن
ALTER TABLE orders ADD COLUMN IF NOT EXISTS field_labels jsonb DEFAULT '{}'::jsonb;
-- referral_commission_paid: يمنع دفع عمولة الإحالة أكثر من مرة لنفس الطلب
ALTER TABLE orders ADD COLUMN IF NOT EXISTS referral_commission_paid boolean DEFAULT false;


-- ═══════════════════════════════════════════════════════════════════
-- PART 1: دوال مساعدة للتحقق من الهوية والدور
-- ═══════════════════════════════════════════════════════════════════
-- ملاحظة أمنية: is_admin() تقرأ الدور من قاعدة البيانات عبر auth.uid()
-- فقط — لا تقبل أي قيمة تُرسل من الكلينت إطلاقاً.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND COALESCE(is_banned, false) = false
  );
$$;

-- هل المستخدم الحالي أدمن أعلى (super admin)؟
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_permissions ap
    JOIN profiles p ON p.id = ap.profile_id
    WHERE ap.profile_id = auth.uid()
      AND ap.is_super_admin = true
      AND p.role = 'admin'
      AND COALESCE(p.is_banned, false) = false
  );
$$;

-- هل المستخدم الحالي محظور؟ (يُستخدم لمنع الشراء والشحن)
CREATE OR REPLACE FUNCTION public.is_banned()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT is_banned FROM profiles WHERE id = auth.uid()),
    false
  );
$$;

-- هذه الدوال تُستخدَم داخل سياسات RLS، فتحتاج EXECUTE للأدوار العادية.
-- (لا تكشف أي بيانات — ترجع boolean عن المستخدم الحالي نفسه فقط)
GRANT EXECUTE ON FUNCTION public.is_admin()       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_banned()      TO anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- PART 2: تفعيل RLS على كل جدول في schema public بدون استثناء
-- ═══════════════════════════════════════════════════════════════════
-- الملف السابق فعّل RLS على 11 جدول فقط وترك 6 جداول حسّاسة مكشوفة
-- تماماً: admin_permissions, admin_audit_logs, gift_cards,
-- store_settings, referral_milestones, referral_milestone_payouts.
-- هذه الحلقة تضمن التفعيل على كل جدول موجود وأي جدول يُضاف مستقبلاً.
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
  -- ملاحظة: لا نستخدم FORCE ROW LEVEL SECURITY عن قصد — لأنها تُطبّق RLS
  -- على مالك الجدول (postgres) أيضاً، فتكسر دوال SECURITY DEFINER
  -- (create_wallet_order, admin_confirm_topup, redeem_gift_card) و
  -- محرّر SQL في لوحة Supabase. الحماية المطلوبة تتحقق كاملة بـ ENABLE
  -- لأن anon و authenticated ليسا مالكَي الجداول.
END $$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 3: profiles — تجميد الدور والحقول المالية عبر Trigger
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 المشكلة في الملف القديم: السياسة "profiles_update_own" كانت تعمل
--    SELECT role FROM profiles داخل سياسة على profiles نفسه، وهذا يسبب
--    خطأ infinite recursion (42P17) ويمنع المستخدم من تعديل ملفه أصلاً.
-- ✅ الحل الصحيح: سياسة بسيطة + Trigger يمنع تغيير الحقول الحسّاسة.
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- الأدمن يعدّل ما يشاء
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- المستخدم العادي: كل الحقول الحسّاسة تُجمَّد على قيمتها القديمة
  NEW.id                      := OLD.id;
  NEW.role                    := OLD.role;
  NEW.is_banned               := OLD.is_banned;
  NEW.referral_code           := OLD.referral_code;
  NEW.referred_by             := OLD.referred_by;
  NEW.referral_rewarded       := OLD.referral_rewarded;
  NEW.referral_discount_used  := OLD.referral_discount_used;
  NEW.milestone10_paid        := OLD.milestone10_paid;
  NEW.milestone25_paid        := OLD.milestone25_paid;
  NEW.loyalty_points          := OLD.loyalty_points;
  NEW.created_at              := OLD.created_at;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_fields ON profiles;
CREATE TRIGGER trg_protect_profile_fields
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_fields();

-- منع تسجيل مستخدم جديد بدور admin من جهة الكلينت
CREATE OR REPLACE FUNCTION public.protect_profile_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- أي حساب جديد يُنشأ من الكلينت يبدأ دائماً كعميل غير محظور بلا نقاط
  NEW.role           := 'customer';
  NEW.is_banned      := false;
  NEW.loyalty_points := 0;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_insert ON profiles;
CREATE TRIGGER trg_protect_profile_insert
BEFORE INSERT ON profiles
FOR EACH ROW EXECUTE FUNCTION public.protect_profile_insert();

DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_all"  ON profiles;

CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_admin());

CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

-- لا حاجة لفحص الدور هنا — الـ Trigger أعلاه يتولى التجميد بلا recursion
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 4: orders — تصحيح trigger السعر + تجميد الأعمدة الحسّاسة
-- ═══════════════════════════════════════════════════════════════════
-- السعر يُحسب دائماً من price_usd في قاعدة البيانات × سعر الصرف ×
-- هامش الربح (من جدول settings) — ولا يُقبل أي سعر من الكلينت.
CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_product_price_usd NUMERIC;
    v_rate              NUMERIC;
    v_margin            NUMERIC;
    v_option_price_usd  NUMERIC;
    v_expected_price    NUMERIC;
BEGIN
    -- الأدمن معفى (يُنشئ طلبات يدوية بأسعار خاصة)
    IF public.is_admin() THEN
        RETURN NEW;
    END IF;

    SELECT price_usd INTO v_product_price_usd
    FROM products WHERE id = NEW.product_id AND is_active = true;

    IF v_product_price_usd IS NULL THEN
        RAISE EXCEPTION 'المنتج غير موجود أو غير متاح';
    END IF;

    SELECT
      (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
      (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
    INTO v_rate, v_margin;

    v_rate   := COALESCE(v_rate,   0);
    v_margin := COALESCE(v_margin, 0);

    IF v_rate <= 0 THEN
        RAISE EXCEPTION 'سعر الصرف غير مضبوط — تعذّر التحقق من السعر';
    END IF;

    v_expected_price := v_product_price_usd * v_rate * (1 + v_margin / 100.0);

    -- المفتاح الصحيح في options هو price_usd
    IF NEW.selected_option IS NOT NULL
       AND (NEW.selected_option->>'price_usd') IS NOT NULL THEN
        v_option_price_usd := (NEW.selected_option->>'price_usd')::NUMERIC;
        IF v_option_price_usd > 0 THEN
            v_expected_price := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
        END IF;
    END IF;

    IF NEW.price_sdg_snapshot IS NULL OR NEW.price_sdg_snapshot <= 0 THEN
        RAISE EXCEPTION 'قيمة الطلب غير صالحة';
    END IF;

    -- بلا كوبون: يجب أن يطابق السعر المتوقع (بهامش تقريب 1%)
    IF NEW.coupon_id IS NULL
       AND NEW.price_sdg_snapshot < (v_expected_price * 0.99) THEN
        RAISE EXCEPTION 'عذراً، تم اكتشاف تلاعب في سعر الطلب!';
    END IF;

    -- مع كوبون: أقصى خصم مسموح 95% (يمنع تصفير السعر بكوبون وهمي)
    IF NEW.coupon_id IS NOT NULL
       AND NEW.price_sdg_snapshot < (v_expected_price * 0.05) THEN
        RAISE EXCEPTION 'عذراً، تم اكتشاف تلاعب في سعر الطلب!';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_verify_order_price ON orders;
CREATE TRIGGER trg_verify_order_price
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION public.verify_order_price_before_insert();

-- 🟠 المشكلة القديمة: سياسة "orders_cancel_own" كانت تسمح للعميل بتعديل
--    أي عمود أثناء الإلغاء (السعر، المنتج، الإيصال، حالة العمولة).
-- ✅ الحل: Trigger يجمّد كل شيء ما عدا status عند تعديل العميل.
CREATE OR REPLACE FUNCTION public.protect_order_fields()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- العميل لا يملك سوى تغيير الحالة (إلى cancelled فقط — تفرضه السياسة)
  NEW.id                       := OLD.id;
  NEW.user_id                  := OLD.user_id;
  NEW.product_id               := OLD.product_id;
  NEW.product_name_snapshot    := OLD.product_name_snapshot;
  NEW.price_sdg_snapshot       := OLD.price_sdg_snapshot;
  NEW.field_values             := OLD.field_values;
  NEW.field_labels             := OLD.field_labels;
  NEW.selected_option          := OLD.selected_option;
  NEW.payment_type             := OLD.payment_type;
  NEW.payment_method_id        := OLD.payment_method_id;
  NEW.receipt_url              := OLD.receipt_url;
  NEW.receipt_hash             := OLD.receipt_hash;
  NEW.transaction_reference    := OLD.transaction_reference;
  NEW.rejection_reason         := OLD.rejection_reason;
  NEW.ocr_status               := OLD.ocr_status;
  NEW.amount_verified          := OLD.amount_verified;
  NEW.coupon_id                := OLD.coupon_id;
  NEW.referral_commission_paid := OLD.referral_commission_paid;
  NEW.created_at               := OLD.created_at;
  NEW.updated_at               := now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_order_fields ON orders;
CREATE TRIGGER trg_protect_order_fields
BEFORE UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION public.protect_order_fields();

DROP POLICY IF EXISTS "orders_select"     ON orders;
DROP POLICY IF EXISTS "orders_insert_own" ON orders;
DROP POLICY IF EXISTS "orders_cancel_own" ON orders;
DROP POLICY IF EXISTS "orders_admin_all"  ON orders;
DROP POLICY IF EXISTS "orders_delete"     ON orders;

CREATE POLICY "orders_select" ON orders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- الإدراج: لنفسه فقط، غير محظور، وبحالة ابتدائية غير مؤكَّدة
CREATE POLICY "orders_insert_own" ON orders
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT public.is_banned()
    AND status IN ('pending_review', 'in_progress')
    AND COALESCE(referral_commission_paid, false) = false
  );

CREATE POLICY "orders_cancel_own" ON orders
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status = 'pending_review')
  WITH CHECK (user_id = auth.uid() AND status = 'cancelled');

CREATE POLICY "orders_admin_all" ON orders
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 5: wallets — قراءة فقط للمالك، لا كتابة من الكلينت إطلاقاً
-- ═══════════════════════════════════════════════════════════════════
-- ملاحظة: لا توجد سياسة INSERT/UPDATE/DELETE للعميل — كل تعديل على
-- الرصيد يمر عبر دوال SECURITY DEFINER فقط (شحن/خصم/عمولة).
DROP POLICY IF EXISTS "wallets_select_own" ON wallets;
DROP POLICY IF EXISTS "wallets_admin_all"  ON wallets;
DROP POLICY IF EXISTS "wallets_update_own" ON wallets;
DROP POLICY IF EXISTS "wallets_insert_own" ON wallets;

CREATE POLICY "wallets_select_own" ON wallets
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "wallets_admin_all" ON wallets
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 6: wallet_topups — فرض الحالة والمبلغ من جهة السيرفر
-- ═══════════════════════════════════════════════════════════════════
-- 🟠 المشكلة القديمة: السياسة كانت تتحقق من user_id فقط، فيستطيع العميل
--    إدراج شحنة بحالة 'confirmed' مباشرة أو بمبلغ سالب/ضخم.
DROP POLICY IF EXISTS "topups_select_own" ON wallet_topups;
DROP POLICY IF EXISTS "topups_insert_own" ON wallet_topups;
DROP POLICY IF EXISTS "topups_admin_all"  ON wallet_topups;
DROP POLICY IF EXISTS "topups_update_own" ON wallet_topups;

CREATE POLICY "topups_select_own" ON wallet_topups
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "topups_insert_own" ON wallet_topups
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND NOT public.is_banned()
    AND status = 'pending'
    AND amount > 0
    AND amount <= 10000000
    AND reviewed_at IS NULL
    AND COALESCE(amount_verified, false) = false
  );

CREATE POLICY "topups_admin_all" ON wallet_topups
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 7: المنتجات والتصنيفات وطرق الدفع — قراءة عامة، كتابة للأدمن
-- ═══════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "products_select_active" ON products;
DROP POLICY IF EXISTS "products_admin_all"     ON products;
CREATE POLICY "products_select_active" ON products
  FOR SELECT TO anon, authenticated
  USING (is_active = true OR public.is_admin());
CREATE POLICY "products_admin_all" ON products
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "categories_select" ON categories;
DROP POLICY IF EXISTS "categories_admin"  ON categories;
CREATE POLICY "categories_select" ON categories
  FOR SELECT TO anon, authenticated
  USING (is_active = true OR public.is_admin());
CREATE POLICY "categories_admin" ON categories
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- طرق الدفع تحتوي أرقام حسابات → للمستخدمين المسجّلين فقط
DROP POLICY IF EXISTS "payment_methods_select" ON payment_methods;
DROP POLICY IF EXISTS "payment_methods_admin"  ON payment_methods;
CREATE POLICY "payment_methods_select" ON payment_methods
  FOR SELECT TO authenticated
  USING (is_active = true OR public.is_admin());
CREATE POLICY "payment_methods_admin" ON payment_methods
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 8: notifications — تعليم كمقروء فقط (كانت الميزة مكسورة صامتاً)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.protect_notification_fields()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- العميل يعدّل is_read فقط
  NEW.id         := OLD.id;
  NEW.user_id    := OLD.user_id;
  NEW.title      := OLD.title;
  NEW.message    := OLD.message;
  NEW.type       := OLD.type;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_notification_fields ON notifications;
CREATE TRIGGER trg_protect_notification_fields
BEFORE UPDATE ON notifications
FOR EACH ROW EXECUTE FUNCTION public.protect_notification_fields();

DROP POLICY IF EXISTS "notifications_select_own" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_own" ON notifications;
DROP POLICY IF EXISTS "notifications_admin_all"  ON notifications;
DROP POLICY IF EXISTS "notifications_update_own" ON notifications;

CREATE POLICY "notifications_select_own" ON notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "notifications_update_own" ON notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "notifications_admin_all" ON notifications
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 9: settings / store_settings
-- ═══════════════════════════════════════════════════════════════════
-- settings يحتوي سعر الصرف وهامش الربح — يحتاجه الفرونت لحساب العرض.
-- تم التحقق من المفاتيح الحالية: لا يوجد فيها أي سر أو مفتاح API.
-- ⚠️ قاعدة للمستقبل: أي مفتاح سري (توكن، API key) لا يُخزَّن هنا إطلاقاً
--    لأن الجدول مقروء من الفرونت إند.
DROP POLICY IF EXISTS "settings_select" ON settings;
DROP POLICY IF EXISTS "settings_admin"  ON settings;
CREATE POLICY "settings_select" ON settings
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "settings_admin" ON settings
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- store_settings: حالة الصيانة تُقرأ عاماً، والكتابة للأدمن فقط
DROP POLICY IF EXISTS "store_settings_select" ON store_settings;
DROP POLICY IF EXISTS "store_settings_admin"  ON store_settings;
CREATE POLICY "store_settings_select" ON store_settings
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "store_settings_admin" ON store_settings
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 10: سجلات التدقيق — audit_logs / admin_audit_logs
-- ═══════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "audit_logs_admin"           ON audit_logs;
DROP POLICY IF EXISTS "audit_logs_insert_customer" ON audit_logs;
DROP POLICY IF EXISTS "audit_logs_select_admin"    ON audit_logs;

-- القراءة للأدمن فقط
CREATE POLICY "audit_logs_select_admin" ON audit_logs
  FOR SELECT TO authenticated USING (public.is_admin());

-- إدراج تنبيهات الاحتيال من صفحة الدفع: مسموح للعميل بشرط admin_id = NULL
-- (يمنع انتحال هوية أدمن حقيقي داخل السجل)
CREATE POLICY "audit_logs_insert_customer" ON audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND admin_id IS NULL);

CREATE POLICY "audit_logs_admin" ON audit_logs
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- admin_audit_logs: كان بلا RLS إطلاقاً. قراءة للأدمن، ولا تعديل/حذف لأحد
DROP POLICY IF EXISTS "admin_audit_select" ON admin_audit_logs;
DROP POLICY IF EXISTS "admin_audit_insert" ON admin_audit_logs;
CREATE POLICY "admin_audit_select" ON admin_audit_logs
  FOR SELECT TO authenticated USING (public.is_admin());
-- الأدمن يسجّل باسمه فقط — لا ينتحل أدمن آخر
CREATE POLICY "admin_audit_insert" ON admin_audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin() AND admin_id = auth.uid());
-- لا UPDATE ولا DELETE — السجل غير قابل للتلاعب (append-only)


-- ═══════════════════════════════════════════════════════════════════
-- PART 11: admin_permissions — أخطر جدول وكان بلا أي RLS
-- ═══════════════════════════════════════════════════════════════════
-- أي شخص كان يستطيع قراءة/تعديل صلاحيات الأدمن ورفع نفسه super admin.
DROP POLICY IF EXISTS "admin_perms_select"      ON admin_permissions;
DROP POLICY IF EXISTS "admin_perms_super_admin" ON admin_permissions;

-- الأدمن يقرأ صلاحياته فقط، والسوبر أدمن يقرأ الكل
CREATE POLICY "admin_perms_select" ON admin_permissions
  FOR SELECT TO authenticated
  USING (profile_id = auth.uid() OR public.is_super_admin());

-- التعديل/الإضافة/الحذف للسوبر أدمن فقط، ولا يعدّل صلاحيات نفسه
CREATE POLICY "admin_perms_super_admin" ON admin_permissions
  FOR ALL TO authenticated
  USING (public.is_super_admin() AND profile_id <> auth.uid())
  WITH CHECK (public.is_super_admin() AND profile_id <> auth.uid());


-- ═══════════════════════════════════════════════════════════════════
-- PART 12: gift_cards — أكواد الهدايا (كان بلا RLS = سرقة كاملة)
-- ═══════════════════════════════════════════════════════════════════
-- ⚠️ بدون RLS كان أي زائر يقرأ كل الأكواد غير المستهلكة ويستبدلها.
DROP POLICY IF EXISTS "gift_cards_admin"       ON gift_cards;
DROP POLICY IF EXISTS "gift_cards_select_own"  ON gift_cards;

-- العميل يرى فقط البطاقات التي استبدلها هو (لا يرى أي كود غير مستهلك)
CREATE POLICY "gift_cards_select_own" ON gift_cards
  FOR SELECT TO authenticated
  USING (redeemed_by = auth.uid() OR public.is_admin());

CREATE POLICY "gift_cards_admin" ON gift_cards
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- الاستبدال يتم عبر هذه الدالة فقط (ذرّي + بلا كشف الأكواد)
-- ملاحظة: النسخة القديمة في القاعدة ترجع نوعاً مختلفاً، و CREATE OR REPLACE
-- لا تستطيع تغيير نوع الإرجاع (خطأ 42P13) → نحذف التوقيع القديم أولاً.
DROP FUNCTION IF EXISTS public.redeem_gift_card(text);

CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code text)
RETURNS TABLE(amount numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_card    RECORD;
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT * INTO v_card FROM gift_cards
  WHERE upper(code) = upper(trim(p_code)) FOR UPDATE;

  IF NOT FOUND OR v_card.is_redeemed = true THEN
    RAISE EXCEPTION 'الكود غير صالح أو مستهلك';
  END IF;

  UPDATE gift_cards
  SET is_redeemed = true, redeemed_by = v_user_id, redeemed_at = now()
  WHERE id = v_card.id AND is_redeemed = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الكود غير صالح أو مستهلك';
  END IF;

  INSERT INTO wallets (user_id, balance)
  VALUES (v_user_id, v_card.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = wallets.balance + v_card.amount, updated_at = now();

  RETURN QUERY SELECT v_card.amount;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 13: الإحالات — referral_milestones / referral_milestone_payouts
-- ═══════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "referral_milestones_select" ON referral_milestones;
DROP POLICY IF EXISTS "referral_milestones_admin"  ON referral_milestones;
CREATE POLICY "referral_milestones_select" ON referral_milestones
  FOR SELECT TO authenticated USING (is_active = true OR public.is_admin());
CREATE POLICY "referral_milestones_admin" ON referral_milestones
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- سجل صرف المكافآت: قراءة للمُحيل نفسه، والكتابة للأدمن/الدوال فقط
DROP POLICY IF EXISTS "referral_payouts_select" ON referral_milestone_payouts;
DROP POLICY IF EXISTS "referral_payouts_admin"  ON referral_milestone_payouts;
CREATE POLICY "referral_payouts_select" ON referral_milestone_payouts
  FOR SELECT TO authenticated
  USING (referrer_id = auth.uid() OR public.is_admin());
CREATE POLICY "referral_payouts_admin" ON referral_milestone_payouts
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 14: coupons — تصحيح أسماء الأعمدة الفعلية
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 كل الملفات السابقة استخ��مت usage_limit / usage_count، والأعمدة
--    الحقيقية في قاعدة البيانات هي max_uses / uses_count → كل دوال
--    الكوبونات كانت تفشل بخطأ "column does not exist".
DROP POLICY IF EXISTS "coupons_select_admin_only" ON coupons;
DROP POLICY IF EXISTS "coupons_admin"             ON coupons;

-- الكوبونات لا تُقرأ من الكلينت إطلاقاً — الفحص عبر RPC فقط
-- (يمنع سحب قائمة كل الأكواد الصالحة)
CREATE POLICY "coupons_select_admin_only" ON coupons
  FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY "coupons_admin" ON coupons
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- فحص الكوبون للعرض فقط (لا يغيّر شيئاً في قاعدة البيانات)
CREATE OR REPLACE FUNCTION public.validate_coupon(p_code TEXT)
RETURNS TABLE(coupon_id UUID, discount_percent NUMERIC)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT id, discount_percent
  FROM coupons
  WHERE upper(code) = upper(trim(p_code))
    AND is_active = true
    AND (max_uses IS NULL OR uses_count < max_uses)
    AND (expires_at IS NULL OR expires_at > NOW())
  LIMIT 1;
$$;

-- استهلاك الكوبون ذرّياً (مع قفل الصف لمنع Race Condition)
CREATE OR REPLACE FUNCTION public.use_coupon_atomic(p_code TEXT)
RETURNS TABLE(coupon_id UUID, discount_percent NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_coupon RECORD;
BEGIN
    -- 🔴 كان أي زائر غير مسجّل يستطيع استهلاك الكوبونات
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
    END IF;
    IF public.is_banned() THEN
        RAISE EXCEPTION 'access_denied';
    END IF;

    SELECT * INTO v_coupon FROM coupons
    WHERE upper(code) = upper(trim(p_code))
      AND is_active = true
      AND (max_uses IS NULL OR uses_count < max_uses)
      AND (expires_at IS NULL OR expires_at > NOW())
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الكود غير صالح أو انتهت صلاحيته';
    END IF;

    UPDATE coupons SET uses_count = COALESCE(uses_count, 0) + 1
    WHERE id = v_coupon.id;

    RETURN QUERY SELECT v_coupon.id, v_coupon.discount_percent;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 15: create_wallet_order — تصحيح أعمدة الكوبون + حفظ coupon_id
-- ═══════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id         uuid,
  p_field_values       jsonb DEFAULT '{}',
  p_field_labels       jsonb DEFAULT '{}',
  p_coupon_code        text  DEFAULT NULL,
  p_selected_option_id text  DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id          uuid := auth.uid();
  v_product          RECORD;
  v_wallet_balance   NUMERIC;
  v_rate             NUMERIC;
  v_margin           NUMERIC;
  v_price_sdg        NUMERIC;
  v_option           jsonb := NULL;
  v_option_price_usd NUMERIC;
  v_coupon_id        uuid;
  v_discount_pct     numeric := 0;
  v_order_id         uuid;
  v_name_snapshot    text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  -- منع الشراء أثناء وضع الصيانة (للعملاء فقط)
  IF EXISTS (SELECT 1 FROM store_settings WHERE maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  SELECT * INTO v_product FROM products WHERE id = p_product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- المنتج له خيارات؟ الاختيار إجباري على مستوى السيرفر أيضاً
  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF p_selected_option_id IS NULL OR trim(p_selected_option_id) = '' THEN
      RAISE EXCEPTION 'option_required';
    END IF;

    SELECT opt INTO v_option
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = p_selected_option_id
    LIMIT 1;

    IF v_option IS NULL THEN
      RAISE EXCEPTION 'option_not_found';
    END IF;

    v_option_price_usd := COALESCE((v_option->>'price_usd')::NUMERIC, 0);
    IF v_option_price_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_price_sdg     := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
  ELSE
    v_price_sdg     := v_product.price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- الكوبون: أسماء الأعمدة الصحيحة max_uses / uses_count
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) != '' THEN
    SELECT c.id, c.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   coupons c
    WHERE  upper(c.code) = upper(trim(p_coupon_code))
      AND  c.is_active = true
      AND  (c.max_uses IS NULL OR c.uses_count < c.max_uses)
      AND  (c.expires_at IS NULL OR c.expires_at > NOW())
    FOR UPDATE;

    IF FOUND THEN
      -- سقف الخصم 95% حتى لو أُدخلت نسبة خاطئة في لوحة الأدمن
      v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
      v_price_sdg    := v_price_sdg * (1.0 - v_discount_pct / 100.0);
      UPDATE coupons SET uses_count = COALESCE(uses_count, 0) + 1
      WHERE id = v_coupon_id;
    END IF;
  END IF;

  v_price_sdg := ROUND(v_price_sdg);
  IF v_price_sdg <= 0 THEN
    v_price_sdg := 1;
  END IF;

  -- قفل صف المحفظة لمنع السحب المزدوج
  SELECT balance INTO v_wallet_balance
  FROM wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets SET balance = balance - v_price_sdg, updated_at = now()
  WHERE user_id = v_user_id;

  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id
  )
  VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'), COALESCE(p_field_labels, '{}'), v_option,
    'wallet', 'in_progress', v_coupon_id
  )
  RETURNING orders.id INTO v_order_id;

  RETURN QUERY SELECT v_order_id;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 16: عمولة الإحالة + تأكيد الشحن (أدمن فقط، بلا تكرا��)
-- ═══════════════════════════════════════════════════════════════════
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
  v_order       RECORD;
  v_commission  numeric;
  v_updated     uuid;
BEGIN
  -- 🔴 كانت مفتوحة لأي مستخدم مسجّل = طبع رصيد بلا حدود
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  SELECT * INTO v_order FROM orders
  WHERE id = p_order_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF COALESCE(v_order.referral_commission_paid, false) = true THEN RETURN; END IF;
  IF v_order.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  SELECT referred_by INTO v_referrer_id FROM profiles WHERE id = p_user_id;
  IF v_referrer_id IS NULL OR v_referrer_id = p_user_id THEN RETURN; END IF;

  -- نضع العلامة أولاً شرطياً — إن لم تتأثر صفوف فهناك سباق تزامن فنتوقف
  UPDATE orders SET referral_commission_paid = true
  WHERE id = p_order_id AND COALESCE(referral_commission_paid, false) = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN RETURN; END IF;

  v_commission := ROUND(COALESCE(v_order.price_sdg_snapshot, 0) * 0.02, 2);
  IF v_commission <= 0 THEN RETURN; END IF;

  INSERT INTO wallets (user_id, balance) VALUES (v_referrer_id, v_commission)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = wallets.balance + v_commission, updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_topup RECORD;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  SELECT * INTO v_topup FROM wallet_topups WHERE id = p_topup_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'topup_not_found';
  END IF;

  IF v_topup.status != 'pending' THEN
    RAISE EXCEPTION 'already_processed';
  END IF;

  UPDATE wallet_topups
  SET status = 'confirmed', reviewed_at = now()
  WHERE id = p_topup_id;

  -- إضافة ذرّية للرصيد (وإنشاء المحفظة إن لم تكن موجودة)
  INSERT INTO wallets (user_id, balance) VALUES (v_topup.user_id, v_topup.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = wallets.balance + v_topup.amount, updated_at = now();
END;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- PART 17: الصلاحيات — سحب EXECUTE من anon/public عن الدوال الحسّاسة
-- ═══════════════════════════════════════════════════════════════════
-- 🔴 Postgres يمنح EXECUTE لـ PUBLIC تلقائياً على كل دالة جديدة، أي أن
--    زائراً غير مسجّل كان يستطيع مناداة كل هذه الدوال مباشرة عبر REST.
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.use_coupon_atomic(text)',
    'public.validate_coupon(text)',
    'public.create_wallet_order(uuid, jsonb, jsonb, text, text)',
    'public.process_referral_commission(uuid, uuid)',
    'public.admin_confirm_topup(uuid)',
    'public.redeem_gift_card(text)'
  ]
  LOOP
    BEGIN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon',   fn);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', fn);
    EXCEPTION WHEN undefined_function THEN
      RAISE NOTICE 'skipped (not found): %', fn;
    END;
  END LOOP;
END $$;

-- دوال الأدمن: لا تُمنح لـ anon إطلاقاً (الفحص الداخلي is_admin() هو الحاجز)
REVOKE ALL ON FUNCTION public.process_referral_commission(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_confirm_topup(uuid)               FROM anon;

-- منع أي إنشاء كائنات جديدة في public من الأدوار العامة
REVOKE CREATE ON SCHEMA public FROM anon, authenticated;

-- ⚠️ service_role: مفتاحه سيرفر-سايد فقط ويتجاوز RLS بالكامل.
--    لا يُستخدم في أي كود فرونت إند ولا يُذكر في أي سياسة.
--    كل السياسات أعلاه محدَّدة بـ TO anon/authenticated فقط.


-- ═══════════════════════════════════════════════════════════════════
-- PART 18: Storage — bucket الإيصالات خاص (حماية IDOR)
-- ═══════════════════════════════════════════════════════════════════
UPDATE storage.buckets SET public = false WHERE id = 'receipts';

DROP POLICY IF EXISTS "receipts_upload_own"   ON storage.objects;
DROP POLICY IF EXISTS "receipts_read_own"     ON storage.objects;
DROP POLICY IF EXISTS "receipts_admin_read"   ON storage.objects;
DROP POLICY IF EXISTS "receipts_admin_manage" ON storage.objects;

-- كل مستخدم يرفع في مجلده الخاص فقط: receipts/<uid>/...
CREATE POLICY "receipts_upload_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "receipts_read_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'receipts'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "receipts_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'receipts' AND public.is_admin());

-- الأدمن فقط يحذف/يعدّل الإيصالات (العميل لا يحذف دليل دفعه)
CREATE POLICY "receipts_admin_manage" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'receipts' AND public.is_admin());


-- ═══════════════════════════════════════════════════════════════════
-- PART 19: فهارس الأداء
-- ═══════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_orders_status       ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id      ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at   ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_coupon_id    ON orders(coupon_id) WHERE coupon_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_receipt_hash ON orders(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_topups_receipt_hash ON wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_topups_user_status  ON wallet_topups(user_id, status);
CREATE INDEX IF NOT EXISTS idx_profiles_role       ON profiles(role);
CREATE INDEX IF NOT EXISTS idx_notif_user_unread   ON notifications(user_id) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_coupons_code        ON coupons(upper(code)) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_gift_cards_code     ON gift_cards(upper(code)) WHERE is_redeemed = false;


-- ═══════════════��═══════════════════════════════════════════════════
-- PART 20: تحقق نهائي — شغّل هذه الاستعلامات وراجع النتائج
-- ═══════════════════════════════════════════════════════════════════

-- 20.1 أي جدول بلا RLS؟ (يجب أن تكون النتيجة فارغة)
SELECT tablename AS "جدول بلا RLS"
FROM pg_tables t
WHERE schemaname = 'public'
  AND NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = t.tablename AND c.relrowsecurity
  );

-- 20.2 أي جدول عليه RLS لكن بلا أي سياسة؟ (محجوب كلياً — يجب أن تكون فارغة)
SELECT c.relname AS "جدول بلا سياسات"
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity
  AND NOT EXISTS (SELECT 1 FROM pg_policies p
                  WHERE p.schemaname = 'public' AND p.tablename = c.relname);

-- 20.3 🔴 الأهم: أي سياسة تسمح بوصول عام (anon/public) على جدول حسّاس؟
--      يجب أن تكون النتيجة فارغة تماماً
SELECT tablename, policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('orders','wallets','wallet_topups','profiles','coupons',
                    'gift_cards','admin_permissions','admin_audit_logs',
                    'audit_logs','referral_milestone_payouts')
  AND (roles = '{public}' OR 'anon' = ANY(roles));

-- 20.4 دوال SECURITY DEFINER ما زال anon يستطيع تنفيذها
--      (يجب أن تظهر is_admin/is_super_admin/is_banned فقط — وهي آمنة)
SELECT p.proname AS "دالة قابلة للتنفيذ من anon"
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY p.proname;

-- 20.5 عرض شامل لكل السياسات الحالية للمراجعة اليدوية
SELECT tablename, policyname, cmd, roles
FROM pg_policies WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ انتهى
-- ═══════════════════════════════════════════════════════════════════
