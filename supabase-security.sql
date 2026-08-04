-- =====================================================================
-- RAIZEY STORE — أمان قاعدة البيانات (المصدر الوحيد للحقيقة)
-- =====================================================================
-- هذا الملف يدمج ويستبدل الملفات الثلاثة القديمة:
--   supabase-security.sql + supabase-critical-fixes.sql
--   + supabase-critical-fixes-2.sql   ← حُذف الأخيران
--
-- سبب الدمج ليس التنظيم فقط: الملفات الثلاثة كانت تعيد تعريف نفس
-- الدوال بنسخ مختلفة، وترتيب التشغيل هو اللي يحدد النسخة الفائزة.
-- تشغيل الملف الأول أخيراً كان يُرجّع نسخة process_referral_commission
-- المكشوفة (بلا فحص أدمن ولا منع تكرار) ويعيد فتح ثغرة شحن لا نهائي.
--
-- الملف آمن لإعادة التشغيل أكثر من مرة (idempotent).
-- شغّله كاملاً في Supabase → SQL Editor من الأعلى للأسفل.
-- =====================================================================


-- =====================================================================
-- PART 0: جعل bucket الإيصالات خاصاً (حماية IDOR)
-- =====================================================================
UPDATE storage.buckets SET public = false WHERE id = 'receipts';


-- =====================================================================
-- PART 1: تفعيل RLS على كل الجداول
-- =====================================================================
ALTER TABLE IF EXISTS profiles                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS orders                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS products                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS categories                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS wallets                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS wallet_topups              ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS payment_methods            ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS notifications              ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS settings                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS audit_logs                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS coupons                    ENABLE ROW LEVEL SECURITY;
-- ⚠️ الثلاثة التالية كانت مكشوفة تماماً بلا RLS — أخطر ما في هذا الجزء
ALTER TABLE IF EXISTS gift_cards                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS referral_milestones        ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS referral_milestone_payouts ENABLE ROW LEVEL SECURITY;


-- =====================================================================
-- PART 2: الأعمدة والجداول المطلوبة
-- =====================================================================
ALTER TABLE orders        ADD COLUMN IF NOT EXISTS field_labels             jsonb   DEFAULT '{}'::jsonb;
ALTER TABLE orders        ADD COLUMN IF NOT EXISTS referral_commission_paid boolean DEFAULT false;
ALTER TABLE orders        ADD COLUMN IF NOT EXISTS ocr_status               text    DEFAULT 'needs_review';
ALTER TABLE orders        ADD COLUMN IF NOT EXISTS amount_verified          boolean DEFAULT false;
ALTER TABLE orders        ADD COLUMN IF NOT EXISTS receipt_hash             text;
ALTER TABLE orders        ADD COLUMN IF NOT EXISTS refunded                 boolean DEFAULT false;
ALTER TABLE wallet_topups ADD COLUMN IF NOT EXISTS receipt_hash             text;
ALTER TABLE coupons       ADD COLUMN IF NOT EXISTS min_order_sdg            numeric DEFAULT 0;

ALTER TABLE gift_cards ADD COLUMN IF NOT EXISTS is_redeemed boolean     DEFAULT false;
ALTER TABLE gift_cards ADD COLUMN IF NOT EXISTS redeemed_by uuid;
ALTER TABLE gift_cards ADD COLUMN IF NOT EXISTS redeemed_at timestamptz;
ALTER TABLE gift_cards ADD COLUMN IF NOT EXISTS expires_at  timestamptz;

-- منع صرف نفس الكوبون مرتين من نفس المستخدم (القيد الفريد هو الحاجز)
CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id   uuid NOT NULL REFERENCES coupons(id)     ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id)  ON DELETE CASCADE,
  order_id    uuid,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (coupon_id, user_id)
);
ALTER TABLE coupon_redemptions ENABLE ROW LEVEL SECURITY;


-- =====================================================================
-- PART 3: منع تكرار الإيصال على مستوى القاعدة
-- =====================================================================
-- كان الفحص في المتصفح فقط (assets/js/supabase-client.js) وقابل للتخطي
-- بإرسال الطلب مباشرة إلى الـ API. الفهارس القديمة كانت عادية لا فريدة.
-- ملاحظة: partial index حتى لا تتعارض قيم NULL المتعددة.
-- ملاحظة: لو فشل إنشاء أحد هذه الفهارس فعندك صفوف مكرّرة بالفعل —
--         نظّفها أولاً ثم أعد تشغيل هذا الجزء.
-- =====================================================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_receipt_hash
  ON orders(receipt_hash) WHERE receipt_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_topups_receipt_hash
  ON wallet_topups(receipt_hash) WHERE receipt_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_gift_cards_code
  ON gift_cards(upper(code));


-- =====================================================================
-- PART 4: دالة التحقق من دور المدير
-- =====================================================================
-- SECURITY DEFINER لتفادي التكرار اللانهائي في سياسات profiles،
-- و search_path مثبّت لمنع اختطافها عبر schema مزيّف.
-- =====================================================================
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


-- =====================================================================
-- PART 5: سياسات RLS — profiles
-- =====================================================================
DROP POLICY IF EXISTS "profiles_select_own" ON profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
DROP POLICY IF EXISTS "profiles_admin_all"  ON profiles;

CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT USING (id = auth.uid() OR public.is_admin());

-- المستخدم لا يرفّع نفسه لأدمن ولا يغيّر مَن أحاله بعد التسجيل
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    AND role = (SELECT role FROM profiles WHERE id = auth.uid())
    AND referred_by IS NOT DISTINCT FROM
        (SELECT referred_by FROM profiles WHERE id = auth.uid())
  );

-- التسجيل مسموح، لكن ليس بدور أدمن
CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT WITH CHECK (
    id = auth.uid()
    AND COALESCE(role, 'customer') <> 'admin'
  );

CREATE POLICY "profiles_admin_all" ON profiles
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 6: حماية سعر الطلب (Trigger)
-- =====================================================================
-- الثغرة القديمة: الشرط كان
--     IF NEW.coupon_id IS NULL AND NEW.price_sdg_snapshot < ...
-- أي أن إرسال أي coupon_id (ولو عشوائياً) يتخطّى فحص السعر بالكامل،
-- فيقدر أي مستخدم يُدخل طلباً بسعر 1 جنيه. النسخة هنا:
--   • تحسب السعر المتوقع من القاعدة دائماً (price_usd × سعر الصرف × الهامش)
--   • تقرأ نسبة الخصم من جدول الكوبونات نفسه لا من المتصفح
--   • تُجبر status = 'pending_review' فلا يُدخل العميل طلباً "مكتملاً"
--   • تمنع payment_type = 'wallet' من المسار المباشر (RPC فقط)
--
-- ملاحظة تقنية: create_wallet_order هي SECURITY DEFINER لكن auth.uid()
-- يبقى للعميل، فلا يصح استخدام is_admin() لتخطّي الفحص. نستعمل علامة
-- جلسة مؤقتة (raizey.trusted_order) تضعها الدالة الموثوقة فقط.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product      RECORD;
  v_rate         numeric;
  v_margin       numeric;
  v_expected     numeric;
  v_option_usd   numeric;
  v_discount_pct numeric := 0;
  v_min_allowed  numeric;
BEGIN
  -- مسار موثوق (create_wallet_order) أو أدمن → السعر محسوب أصلاً بالسيرفر
  IF COALESCE(current_setting('raizey.trusted_order', true), '') = 'on'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product FROM products WHERE id = NEW.product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  -- السعر المتوقع من القاعدة — لا يُقبل أي رقم قادم من المتصفح
  IF NEW.selected_option IS NOT NULL
     AND (NEW.selected_option->>'price_usd') IS NOT NULL THEN
    v_option_usd := COALESCE((NEW.selected_option->>'price_usd')::numeric, 0);
    IF v_option_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_expected := v_option_usd * v_rate * (1 + v_margin / 100.0);
  ELSE
    v_expected := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
  END IF;

  IF v_expected IS NULL OR v_expected <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- نسبة الخصم من جدول الكوبونات، والكوبون المجهول يُرفض
  IF NEW.coupon_id IS NOT NULL THEN
    SELECT discount_percent INTO v_discount_pct
    FROM coupons WHERE id = NEW.coupon_id AND is_active = true;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_coupon';
    END IF;

    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 100);
  END IF;

  v_min_allowed := v_expected * (1.0 - v_discount_pct / 100.0) * 0.99; -- هامش تقريب 1%

  IF NEW.price_sdg_snapshot IS NULL OR NEW.price_sdg_snapshot < v_min_allowed THEN
    RAISE EXCEPTION 'price_tampered';
  END IF;

  -- طلبات المحفظة تمر عبر RPC فقط
  IF NEW.payment_type = 'wallet' THEN
    RAISE EXCEPTION 'use_create_wallet_order_rpc';
  END IF;

  -- إجبار الحالة الآمنة: العميل لا يعيّن حالة الطلب ولا يعلن التحقق
  NEW.status          := 'pending_review';
  NEW.amount_verified := false;
  NEW.refunded        := false;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_verify_order_price ON orders;
CREATE TRIGGER trg_verify_order_price
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION public.verify_order_price_before_insert();


-- =====================================================================
-- PART 7: سياسات RLS — orders
-- =====================================================================
DROP POLICY IF EXISTS "orders_select"     ON orders;
DROP POLICY IF EXISTS "orders_insert_own" ON orders;
DROP POLICY IF EXISTS "orders_cancel_own" ON orders;
DROP POLICY IF EXISTS "orders_admin_all"  ON orders;

CREATE POLICY "orders_select" ON orders
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "orders_insert_own" ON orders
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- الإلغاء فقط لطلب قيد المراجعة، ولا يمس السعر ولا حالة التحقق
CREATE POLICY "orders_cancel_own" ON orders
  FOR UPDATE USING (user_id = auth.uid() AND status = 'pending_review')
  WITH CHECK (user_id = auth.uid() AND status = 'cancelled');

CREATE POLICY "orders_admin_all" ON orders
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 8: سياسات RLS — wallets (قراءة فقط للمستخدم)
-- =====================================================================
-- لا سياسة INSERT/UPDATE للمستخدم إطلاقاً. كل تغيير في الرصيد يمر عبر
-- دوال SECURITY DEFINER في الأجزاء 14–19.
-- =====================================================================
DROP POLICY IF EXISTS "wallets_select_own" ON wallets;
DROP POLICY IF EXISTS "wallets_admin_all"  ON wallets;

CREATE POLICY "wallets_select_own" ON wallets
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "wallets_admin_all" ON wallets
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 9: سياسات RLS — المنتجات والتصنيفات وطرق الدفع
-- =====================================================================
DROP POLICY IF EXISTS "products_select_active" ON products;
DROP POLICY IF EXISTS "products_admin_all"     ON products;
CREATE POLICY "products_select_active" ON products
  FOR SELECT USING (is_active = true OR public.is_admin());
CREATE POLICY "products_admin_all" ON products
  FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "categories_select" ON categories;
DROP POLICY IF EXISTS "categories_admin"  ON categories;
CREATE POLICY "categories_select" ON categories FOR SELECT USING (true);
CREATE POLICY "categories_admin"  ON categories FOR ALL    USING (public.is_admin());

-- أرقام الحسابات البنكية للمسجّلين فقط — كانت مقروءة للزوار
DROP POLICY IF EXISTS "payment_methods_select" ON payment_methods;
DROP POLICY IF EXISTS "payment_methods_admin"  ON payment_methods;
CREATE POLICY "payment_methods_select" ON payment_methods
  FOR SELECT TO authenticated
  USING (is_active = true OR public.is_admin());
CREATE POLICY "payment_methods_admin" ON payment_methods
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 10: سياسات RLS — wallet_topups
-- =====================================================================
DROP POLICY IF EXISTS "topups_select_own" ON wallet_topups;
DROP POLICY IF EXISTS "topups_insert_own" ON wallet_topups;
DROP POLICY IF EXISTS "topups_admin_all"  ON wallet_topups;

CREATE POLICY "topups_select_own" ON wallet_topups
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

-- العميل يطلب شحناً بحالة pending فقط وبمبلغ موجب — لا يعلنه مؤكداً
CREATE POLICY "topups_insert_own" ON wallet_topups
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND amount > 0
  );

CREATE POLICY "topups_admin_all" ON wallet_topups
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 11: سياسات RLS — الإشعارات والإعدادات والسجل
-- =====================================================================
-- الإشعارات: الإدراج للأدمن فقط (كان صحيحاً)، وأُضيفت سياسة UPDATE
-- ليقدر العميل يعلّم إشعاره مقروءاً دون سياسة ALL مفتوحة.
DROP POLICY IF EXISTS "notifications_select_own" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_own" ON notifications;
DROP POLICY IF EXISTS "notifications_update_own" ON notifications;
DROP POLICY IF EXISTS "notifications_admin_all"  ON notifications;

CREATE POLICY "notifications_select_own" ON notifications
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY "notifications_insert_own" ON notifications
  FOR INSERT WITH CHECK (public.is_admin());

CREATE POLICY "notifications_update_own" ON notifications
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "notifications_admin_all" ON notifications
  FOR ALL USING (public.is_admin());

-- الإعدادات: كانت USING (true) — أي زائر يقرأ profit_margin_percent،
-- يعني هامش ربحك بيانات عامة. الآن المفاتيح العامة فقط.
-- أضف أي مفتاح عام جديد إلى القائمة أدناه.
DROP POLICY IF EXISTS "settings_select"        ON settings;
DROP POLICY IF EXISTS "settings_select_public" ON settings;
DROP POLICY IF EXISTS "settings_admin"         ON settings;

CREATE POLICY "settings_select_public" ON settings
  FOR SELECT USING (
    public.is_admin()
    OR key IN (
      'site_name', 'site_logo', 'whatsapp_number', 'support_email',
      'facebook_url', 'instagram_url', 'telegram_url',
      'announcement_text', 'announcement_active',
      'maintenance_mode', 'min_topup_amount', 'usd_to_sdg_rate'
    )
  );

CREATE POLICY "settings_admin" ON settings
  FOR ALL USING (public.is_admin());

-- السجل: الأدمن يقرأ ويكتب. العميل يكتب تنبيهات الاحتيال التلقائية
-- (admin_id = NULL) فقط من صفحة الدفع، ولا يقرأ السجل ولا ينتحل أدمن.
DROP POLICY IF EXISTS "audit_logs_admin"           ON audit_logs;
DROP POLICY IF EXISTS "audit_logs_insert_customer" ON audit_logs;

CREATE POLICY "audit_logs_admin" ON audit_logs
  FOR ALL USING (public.is_admin());

CREATE POLICY "audit_logs_insert_customer" ON audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (admin_id IS NULL);


-- =====================================================================
-- PART 12: سياسات RLS — الكوبونات وبطاقات الهدايا
-- =====================================================================
-- الكوبونات مخفية تماماً: الفحص عبر RPC فقط حتى لا يُسحب الجدول كله.
DROP POLICY IF EXISTS "coupons_select_admin_only" ON coupons;
DROP POLICY IF EXISTS "coupons_admin"             ON coupons;
CREATE POLICY "coupons_admin" ON coupons
  FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "coupon_redemptions_select_own" ON coupon_redemptions;
DROP POLICY IF EXISTS "coupon_redemptions_admin"      ON coupon_redemptions;
CREATE POLICY "coupon_redemptions_select_own" ON coupon_redemptions
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());
CREATE POLICY "coupon_redemptions_admin" ON coupon_redemptions
  FOR ALL USING (public.is_admin());

-- ⚠️ أخطر ثغرة في هذا الجزء: gift_cards كان بلا RLS إطلاقاً، أي أن
-- select * from gift_cards من المتصفح يرجّع كل الأكواد لأي مستخدم
-- مسجّل — شحن مجاني بلا حدود. الآن: أدمن فقط، والصرف عبر RPC.
DROP POLICY IF EXISTS "gift_cards_admin"      ON gift_cards;
DROP POLICY IF EXISTS "gift_cards_select_own" ON gift_cards;
CREATE POLICY "gift_cards_admin" ON gift_cards
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 13: سياسات RLS — مكافآت الإحالة
-- =====================================================================
-- كان الجدولان بلا RLS: المستخدم يقدر يعدّل عتبات المكافآت، ويُدخل
-- سجل صرف وهمي لنفسه، ويقرأ إحالات الآخرين.
DROP POLICY IF EXISTS "milestones_select" ON referral_milestones;
DROP POLICY IF EXISTS "milestones_admin"  ON referral_milestones;
CREATE POLICY "milestones_select" ON referral_milestones
  FOR SELECT USING (is_active = true OR public.is_admin());
CREATE POLICY "milestones_admin" ON referral_milestones
  FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "milestone_payouts_select_own" ON referral_milestone_payouts;
DROP POLICY IF EXISTS "milestone_payouts_admin"      ON referral_milestone_payouts;
CREATE POLICY "milestone_payouts_select_own" ON referral_milestone_payouts
  FOR SELECT USING (referrer_id = auth.uid() OR public.is_admin());
CREATE POLICY "milestone_payouts_admin" ON referral_milestone_payouts
  FOR ALL USING (public.is_admin());


-- =====================================================================
-- PART 14: RPC — create_wallet_order (خصم المحفظة ذرياً)
-- =====================================================================
-- حذف النسخة القديمة ذات الأربعة معاملات: كان الاثنان موجودين معاً
-- فيصير الاستدعاء غامضاً، والنسخة القديمة تعتمد products.price_sdg.
DROP FUNCTION IF EXISTS public.create_wallet_order(uuid, jsonb, text, text);

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
  v_coupon           RECORD;
  v_wallet_balance   numeric;
  v_rate             numeric;
  v_margin           numeric;
  v_gross_sdg        numeric;
  v_price_sdg        numeric;
  v_option           jsonb := NULL;
  v_option_price_usd numeric;
  v_coupon_id        uuid  := NULL;
  v_order_id         uuid;
  v_name_snapshot    text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
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

  -- المنتج له خيارات فرعية؟ الاختيار إجباري على السيرفر أيضاً
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

    v_option_price_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
    IF v_option_price_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;

    v_gross_sdg     := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || (v_option->>'label');
  ELSE
    v_gross_sdg     := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
  END IF;

  IF v_gross_sdg IS NULL OR v_gross_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  v_price_sdg := v_gross_sdg;

  -- الكوبون: يُرفض صريحاً إن كان فاسداً. النسخة القديمة كانت تستعمل
  -- IF FOUND فتتجاهل الكوبون غير الصالح بصمت، فيُخصم من المستخدم سعر
  -- مختلف عن اللي شافه في الواجهة دون أي رسالة.
  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) != '' THEN
    SELECT * INTO v_coupon
    FROM coupons
    WHERE upper(code) = upper(trim(p_coupon_code))
      AND is_active = true
      AND (usage_limit IS NULL OR usage_count < usage_limit)
      AND (expires_at  IS NULL OR expires_at > now())
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_coupon';
    END IF;

    IF v_gross_sdg < COALESCE(v_coupon.min_order_sdg, 0) THEN
      RAISE EXCEPTION 'coupon_min_order_not_met';
    END IF;

    -- استخدام واحد لكل مستخدم
    BEGIN
      INSERT INTO coupon_redemptions (coupon_id, user_id)
      VALUES (v_coupon.id, v_user_id);
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'coupon_already_used';
    END;

    v_coupon_id := v_coupon.id;
    v_price_sdg := v_gross_sdg
                   * (1.0 - LEAST(GREATEST(COALESCE(v_coupon.discount_percent, 0), 0), 100) / 100.0);

    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = v_coupon.id;
  END IF;

  v_price_sdg := GREATEST(ROUND(v_price_sdg), 0);

  -- قفل صف المحفظة لمنع السحب المزدوج من نقرتين متزامنتين
  SELECT balance INTO v_wallet_balance
  FROM wallets WHERE user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  IF v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets
  SET balance = balance - v_price_sdg, updated_at = now()
  WHERE user_id = v_user_id;

  -- علامة مسار موثوق: السعر محسوب بالسيرفر فوق، فلا يعيد الـ trigger
  -- حسابه ولا يُجبر الحالة. العلامة محلية للمعاملة (true) وتزول تلقائياً.
  PERFORM set_config('raizey.trusted_order', 'on', true);

  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id, amount_verified
  )
  VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'), COALESCE(p_field_labels, '{}'), v_option,
    'wallet', 'in_progress', v_coupon_id, true
  )
  RETURNING orders.id INTO v_order_id;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  IF v_coupon_id IS NOT NULL THEN
    UPDATE coupon_redemptions
    SET order_id = v_order_id
    WHERE coupon_id = v_coupon_id AND user_id = v_user_id AND order_id IS NULL;
  END IF;

  RETURN QUERY SELECT v_order_id;
END;
$$;


-- =====================================================================
-- PART 15: RPC — الكوبونات
-- =====================================================================
-- p_amount_sdg مضاف بقيمة افتراضية حتى تعمل الاستدعاءات الحالية
-- ({ p_code }) كما هي دون تعديل صفحات الواجهة.
CREATE OR REPLACE FUNCTION public.validate_coupon(
  p_code       text,
  p_amount_sdg numeric DEFAULT 0
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_coupon
  FROM coupons
  WHERE upper(code) = upper(trim(p_code))
    AND is_active = true
    AND (usage_limit IS NULL OR usage_count < usage_limit)
    AND (expires_at  IS NULL OR expires_at > now());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_coupon';
  END IF;

  IF COALESCE(p_amount_sdg, 0) > 0
     AND p_amount_sdg < COALESCE(v_coupon.min_order_sdg, 0) THEN
    RAISE EXCEPTION 'coupon_min_order_not_met';
  END IF;

  IF EXISTS (
    SELECT 1 FROM coupon_redemptions
    WHERE coupon_id = v_coupon.id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'coupon_already_used';
  END IF;

  RETURN QUERY SELECT v_coupon.id, v_coupon.discount_percent;
END;
$$;

-- للتحويل البنكي: صرف ذرّي مع تسجيل الاستخدام لكل مستخدم
CREATE OR REPLACE FUNCTION public.use_coupon_atomic(
  p_code       text,
  p_amount_sdg numeric DEFAULT 0
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_coupon
  FROM coupons
  WHERE upper(code) = upper(trim(p_code))
    AND is_active = true
    AND (usage_limit IS NULL OR usage_count < usage_limit)
    AND (expires_at  IS NULL OR expires_at > now())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_coupon';
  END IF;

  IF COALESCE(p_amount_sdg, 0) > 0
     AND p_amount_sdg < COALESCE(v_coupon.min_order_sdg, 0) THEN
    RAISE EXCEPTION 'coupon_min_order_not_met';
  END IF;

  BEGIN
    INSERT INTO coupon_redemptions (coupon_id, user_id)
    VALUES (v_coupon.id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'coupon_already_used';
  END;

  UPDATE coupons SET usage_count = usage_count + 1 WHERE id = v_coupon.id;

  RETURN QUERY SELECT v_coupon.id, v_coupon.discount_percent;
END;
$$;


-- =====================================================================
-- PART 16: RPC — عمولة الإحالة
-- =====================================================================
-- ⚠️ النسخة في الملف القديم كانت SECURITY DEFINER بلا أي فحص أدمن وبلا
-- منع تكرار: أي مستخدم يستدعيها في حلقة على نفس الطلب ويشحن محفظة مَن
-- يريد بلا حدود. هذه هي النسخة الوحيدة الباقية الآن.
-- =====================================================================
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
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  -- قفل صف الطلب والتأكد أنه يخص نفس المستخدم المُمرَّر فعلاً
  SELECT * INTO v_order
  FROM orders WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_order.referral_commission_paid = true THEN
    RETURN;
  END IF;

  IF v_order.status NOT IN ('in_progress', 'completed') THEN
    RETURN;
  END IF;

  SELECT referred_by INTO v_referrer_id FROM profiles WHERE id = p_user_id;
  IF v_referrer_id IS NULL THEN
    RETURN;
  END IF;

  -- نضع العلامة أولاً شرطياً — إن لم يتأثر صف فقد سبقنا غيرنا
  UPDATE orders
  SET referral_commission_paid = true
  WHERE id = p_order_id AND referral_commission_paid = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RETURN;
  END IF;

  v_commission := ROUND(v_order.price_sdg_snapshot * 0.02, 2); -- 2% عمولة

  UPDATE wallets
  SET balance = balance + v_commission, updated_at = now()
  WHERE user_id = v_referrer_id;
END;
$$;


-- =====================================================================
-- PART 17: RPC — تأكيد الشحن اليدوي (أدمن)
-- =====================================================================
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

  -- إضافة ذرّية (balance = balance + amount) بدل قراءة-ثم-كتابة
  UPDATE wallets
  SET balance = balance + v_topup.amount, updated_at = now()
  WHERE user_id = v_topup.user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;
END;
$$;


-- =====================================================================
-- PART 18: RPC — admin_refund_wallet  (كانت مفقودة تماماً)
-- =====================================================================
-- ⚠️ admin-orders.html:136 يستدعي هذه الدالة عند رفض طلب مدفوع من
-- المحفظة، لكنها لم تكن معرّفة في أي ملف SQL. النتيجة: الاسترجاع يفشل
-- بصمت، والواجهة تخبر العميل "تم إرجاع رصيدك" وهو لم يُرجَع أبداً.
-- المبلغ يُقرأ من الطلب نفسه لا من الواجهة، فلا يصح استرجاع متضخّم.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.admin_refund_wallet(
  p_user_id  uuid,
  p_amount   numeric,
  p_order_id uuid
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order   RECORD;
  v_updated uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  SELECT * INTO v_order
  FROM orders WHERE id = p_order_id AND user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;

  IF v_order.payment_type != 'wallet' THEN
    RAISE EXCEPTION 'not_a_wallet_order';
  END IF;

  IF COALESCE(v_order.refunded, false) = true THEN
    RAISE EXCEPTION 'already_refunded';
  END IF;

  UPDATE orders
  SET refunded = true
  WHERE id = p_order_id AND COALESCE(refunded, false) = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RETURN; -- سباق تزامن: صف آخر سبقنا
  END IF;

  UPDATE wallets
  SET balance = balance + v_order.price_sdg_snapshot, updated_at = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;
END;
$$;


-- =====================================================================
-- PART 19: RPC — redeem_gift_card  (كانت مفقودة تماماً)
-- =====================================================================
-- ⚠️ wallet.html:169 يستدعيها ولم تكن معرّفة — بطاقات الهدايا معطّلة
-- بالكامل. الصرف ذرّي: علامة الاستخدام تُوضع شرطياً قبل إضافة الرصيد،
-- فلا يصح صرف نفس البطاقة مرتين ولو ضُغط الزر مرتين في نفس اللحظة.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code text)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_card    RECORD;
  v_updated uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  IF p_code IS NULL OR trim(p_code) = '' THEN
    RAISE EXCEPTION 'invalid_code';
  END IF;

  SELECT * INTO v_card
  FROM gift_cards
  WHERE upper(code) = upper(trim(p_code))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_code';
  END IF;

  IF COALESCE(v_card.is_redeemed, false) = true THEN
    RAISE EXCEPTION 'already_redeemed';
  END IF;

  IF v_card.expires_at IS NOT NULL AND v_card.expires_at <= now() THEN
    RAISE EXCEPTION 'expired_code';
  END IF;

  IF COALESCE(v_card.amount, 0) <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  UPDATE gift_cards
  SET is_redeemed = true, redeemed_by = v_user_id, redeemed_at = now()
  WHERE id = v_card.id AND COALESCE(is_redeemed, false) = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'already_redeemed';
  END IF;

  UPDATE wallets
  SET balance = balance + v_card.amount, updated_at = now()
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;

  RETURN v_card.amount;
END;
$$;


-- =====================================================================
-- PART 20: سياسات Storage — bucket «receipts» (خاص)
-- =====================================================================
DROP POLICY IF EXISTS "receipts_upload_own" ON storage.objects;
DROP POLICY IF EXISTS "receipts_read_own"   ON storage.objects;
DROP POLICY IF EXISTS "receipts_admin_read" ON storage.objects;

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


-- =====================================================================
-- PART 21: صلاحيات تنفيذ الدوال (منع استدعاء anon)
-- =====================================================================
-- كان الزائر غير المسجّل يقدر ينفّذ كل الدوال. is_admin() يحمي
-- الحساسة منها، لكن validate_coupon كانت تسمح لأي زائر بتخمين
-- الأكواد بلا حساب ولا أي أثر.
-- =====================================================================
REVOKE ALL ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text) FROM anon, public;
REVOKE ALL ON FUNCTION public.validate_coupon(text, numeric)                      FROM anon, public;
REVOKE ALL ON FUNCTION public.use_coupon_atomic(text, numeric)                    FROM anon, public;
REVOKE ALL ON FUNCTION public.redeem_gift_card(text)                              FROM anon, public;
REVOKE ALL ON FUNCTION public.process_referral_commission(uuid, uuid)             FROM anon, public;
REVOKE ALL ON FUNCTION public.admin_confirm_topup(uuid)                           FROM anon, public;
REVOKE ALL ON FUNCTION public.admin_refund_wallet(uuid, numeric, uuid)            FROM anon, public;

GRANT EXECUTE ON FUNCTION public.create_wallet_order(uuid, jsonb, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_coupon(text, numeric)                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(text, numeric)                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_gift_card(text)                              TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_commission(uuid, uuid)             TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_topup(uuid)                           TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_refund_wallet(uuid, numeric, uuid)            TO authenticated;


-- =====================================================================
-- PART 22: الفهارس (أداء)
-- =====================================================================
CREATE INDEX IF NOT EXISTS idx_orders_status      ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id     ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_topups_user_id     ON wallet_topups(user_id);
CREATE INDEX IF NOT EXISTS idx_topups_status      ON wallet_topups(status);
CREATE INDEX IF NOT EXISTS idx_profiles_role      ON profiles(role)        WHERE role = 'admin';
CREATE INDEX IF NOT EXISTS idx_profiles_referred  ON profiles(referred_by) WHERE referred_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_coupons_code       ON coupons(upper(code));
CREATE INDEX IF NOT EXISTS idx_notifs_user_unread ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_payouts_referrer   ON referral_milestone_payouts(referrer_id);


-- =====================================================================
-- PART 23: فحص ذاتي — شغّل هذه الاستعلامات بعد التنفيذ
-- =====================================================================
-- 1) جداول بلا RLS (يجب أن تكون النتيجة صفر صفوف):
--    SELECT tablename FROM pg_tables
--    WHERE schemaname = 'public' AND rowsecurity = false;
--
-- 2) جداول عليها RLS لكن بلا أي سياسة (حجب كامل — راجعها):
--    SELECT t.tablename FROM pg_tables t
--    LEFT JOIN pg_policies p ON p.tablename = t.tablename
--    WHERE t.schemaname = 'public' AND p.policyname IS NULL;
--
-- 3) دوال SECURITY DEFINER بلا search_path مثبّت (خطر اختطاف):
--    SELECT proname FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND prosecdef = true
--      AND (proconfig IS NULL OR NOT proconfig::text LIKE '%search_path%');
--
-- 4) دوال يستدعيها الموقع — يجب أن ترجّع 7 صفوف:
--    SELECT proname FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND proname IN (
--      'create_wallet_order','validate_coupon','use_coupon_atomic',
--      'redeem_gift_card','process_referral_commission',
--      'admin_confirm_topup','admin_refund_wallet');
-- =====================================================================
