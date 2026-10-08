-- ═══════════════════════════════════════════════════════════════════
-- RAIZEY STORE — إصلاحات حرجة (الدفعة 2 — يوليو 2026)
-- شغّل هذا الملف بعد supabase-critical-fixes.sql في Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────
-- 🔴 الأخطر في كل المراجعة: process_referral_commission بدون أي حماية
-- ─────────────────────────────────────────────────────────────────────
-- المشكلة: هذي الدالة كانت:
--   1) بدون أي تحقق من is_admin() — أي شخص مسجّل دخول (زبون عادي) يقدر
--      يناديها مباشرة من كونسول المتصفح بأي p_user_id و p_order_id.
--   2) بدون أي حماية من التكرار — نفس الطلب ممكن يُستخدم مرات لا نهائية
--      لإضافة عمولة لصاحب الإحالة في كل مرة تُستدعى فيها الدالة.
--   3) بدون تحقق أن الطلب (order) فعلاً يخص المستخدم p_user_id.
-- ← دمج الثلاثة يعني: أي شخص يعرف UUID لأي طلب مؤكَّد ومعرّف مستخدم
--   محاَل من شخص آخر، يقدر "يطبع" رصيد بلا حدود في محفظة أي محيل.
-- ─────────────────────────────────────────────────────────────────────

-- عمود لتتبّع الطلبات اللي دُفعت عمولتها فعلاً (يمنع الدفع المتكرر)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS referral_commission_paid boolean DEFAULT false;

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
  -- 1) للأدمن فقط — نفس فحص admin_refund_wallet
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  -- 2) نقفل صف الطلب ونتأكد إنه يخص نفس المستخدم المُمرَّر فعلاً
  --    ونتأكد إنه لم تُدفع عمولته من قبل (كل هذا داخل قفل واحد ذرّي)
  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN; -- الطلب غير موجود أو لا يخص هذا المستخدم — لا شيء يُدفع
  END IF;

  IF v_order.referral_commission_paid = true THEN
    RETURN; -- دُفعت العمولة من قبل لهذا الطلب — لا تكرار
  END IF;

  IF v_order.status NOT IN ('in_progress', 'completed') THEN
    RETURN; -- لا تُدفع عمولة لطلب لم يُؤكَّد فعلياً
  END IF;

  SELECT referred_by INTO v_referrer_id FROM profiles WHERE id = p_user_id;
  IF v_referrer_id IS NULL THEN
    RETURN;
  END IF;

  -- 3) نضع علامة الدفع أولاً (شرطياً) — إذا لم تتأثر أي صفوف يعني
  --    صف تاني سبقنا (سباق تزامن) فنتوقف فوراً دون دفع مضاعف
  UPDATE orders
  SET referral_commission_paid = true
  WHERE id = p_order_id AND referral_commission_paid = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RETURN;
  END IF;

  v_commission := ROUND(v_order.price_sdg_snapshot * 0.02, 2); -- 2% عمولة
  UPDATE wallets SET balance = balance + v_commission, updated_at = now() WHERE user_id = v_referrer_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 🟠 شحن المحفظة اليدوي (admin-topups.html) — كان غير ذرّي
-- ─────────────────────────────────────────────────────────────────────
-- المشكلة: الكود القديم كان يقرأ الرصيد من المتصفح، يحسب الرصيد الجديد،
-- ثم يكتبه — بدون قفل صف ولا تحقق من حالة الشحنة. نقرتان سريعتان على
-- زر "تأكيد" (شائع مع الإنترنت البطيء) ممكن تؤدي لشحن مزدوج أو ضياع شحن.
-- ─────────────────────────────────────────────────────────────────────
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

  -- قفل صف الشحنة نفسها لمنع أي تعامل متزامن معها
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

  -- إضافة ذرّية للرصيد (balance = balance + amount) بدل قراءة-ثم-كتابة
  UPDATE wallets
  SET balance = balance + v_topup.amount, updated_at = now()
  WHERE user_id = v_topup.user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found';
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- ✅ انتهى — الملف جاهز للتشغيل في Supabase SQL Editor
-- ─────────────────────────────────────────────────────────────────────
