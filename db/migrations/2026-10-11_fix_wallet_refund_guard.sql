-- ============================================================================
-- MEEM STORE — إصلاح عطل حقيقي في مسار استرداد المحفظة
-- File  : db/migrations/2026-10-11_fix_wallet_refund_guard.sql
-- Found : اختبار تدفقات المال 2026-10-11 (db/tests/live_money_flow_test.sql)
-- Symptom: admin_update_order_status('cancelled') و admin_reject_order كانا
--          يفشلان بالكامل لأي طلب محفظة:
--            ERROR: refund_not_allowed: status=cancelled (أو status=rejected)
--          السبب: كلاهما يُحدّث حالة الطلب أولاً ثم يستدعي admin_refund_wallet،
--          والدالة كانت تشترط status='completed' ⇒ الاسترداد يفشل ⇒ الرفض/الإلغاء
--          يفشل معه (لا إلغاء ولا استرداد ممكنان إطلاقاً).
-- Fix   : إزالة شرط الحالة واستبداله بدليل الدفتر — لا استرداد لطلب محفظة
--          إلا إذا وُجد قيد خصم موثّق لهذا الطلب (نفس منطق إثبات الدفع).
--          طلبات الدفع الخارجي (بنك/كود) تبقى قابلة للتعويض اليدوي كالسابق.
-- Rollback: db/rollback/2026-10-11_fix_wallet_refund_guard.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_refund_wallet(p_order_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_order   public.orders%ROWTYPE;
  v_new_balance numeric;
  v_admin   uuid := auth.uid();
  v_debited boolean := false;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'invalid_refund_input: order required';
  END IF;

  -- Lock the order; amount + user are server-derived from this row only.
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.refunded THEN
    RAISE EXCEPTION 'already_refunded';
  END IF;

  -- [FIX 2026-10-11] كان هنا: IF v_order.status <> 'completed' THEN RAISE …
  -- الشرط كان يجعل مساري الإلغاء والرفض مستحيلين (الحالة تكون قد تغيّرت بالفعل).
  -- البديل: إثبات مالي من دفتر المحفظة بدل شرط الحالة.
  IF v_order.price_sdg_snapshot IS NULL OR v_order.price_sdg_snapshot <= 0 THEN
    RAISE EXCEPTION 'invalid_refund_amount';
  END IF;

  v_debited := EXISTS (
    SELECT 1
    FROM public.wallet_transactions t
    WHERE t.user_id = v_order.user_id
      AND t.direction = 'debit'
      AND (t.reference_id = p_order_id OR t.details->'order_ids' ? p_order_id::text)
  );

  -- طلب محفظة بلا أي خصم موثّق = لا استرداد (منع تكوين رصيد من الهواء)
  IF v_order.payment_type = 'wallet' AND NOT v_debited THEN
    RAISE EXCEPTION 'refund_without_debit: no wallet debit recorded for order %', p_order_id;
  END IF;

  UPDATE public.wallets
  SET balance = balance + v_order.price_sdg_snapshot, updated_at = now()
  WHERE user_id = v_order.user_id
  RETURNING balance INTO v_new_balance;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found for user %', v_order.user_id;
  END IF;

  UPDATE public.orders SET refunded = true WHERE id = p_order_id;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_order.user_id, v_order.price_sdg_snapshot, 'credit', v_new_balance, 'admin_refund', p_order_id, v_admin);

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (v_admin, 'admin_refund_wallet',
          jsonb_build_object('order_id', p_order_id,
                             'amount', v_order.price_sdg_snapshot,
                             'order_user_id', v_order.user_id,
                             'order_status_at_refund', v_order.status,
                             'wallet_debit_evidence', v_debited,
                             'reason', NULLIF(trim(coalesce(p_reason, '')), '')),
          'admin_action');
END
$fn$;

SELECT 'migration_2026-10-11_fix_wallet_refund_guard_applied' AS status;
