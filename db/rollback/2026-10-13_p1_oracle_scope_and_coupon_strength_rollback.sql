-- ============================================================================
-- MEEM STORE — ROLLBACK لملف:
--   db/migrations/2026-10-13_p1_oracle_scope_and_coupon_strength.sql
-- Notes: يُعيد الكائنات إلى حالتها السابقة بالضبط (النسخ المأخوذة من القاعدة
--        الحية rglbfizqolrenwfsndyv). لا يمسّ أي صف بيانات زبون.
--        طبّقه داخل معاملة واحدة فقط.
-- ============================================================================

-- 1) check_tx_ref_available — النسخة السابقة (نطاق عالمي، بلا حد معدل)
CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
RETURNS TABLE(available boolean, reason text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_norm text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  v_norm := public.normalize_tx_ref(p_tx_ref);
  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RETURN QUERY SELECT false, 'invalid_tx_ref';
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.payment_receipts WHERE tx_ref_norm = v_norm)
       OR EXISTS (SELECT 1 FROM public.orders WHERE public.normalize_tx_ref(transaction_reference) = v_norm)
            OR EXISTS (SELECT 1 FROM public.wallet_topups WHERE public.normalize_tx_ref(transaction_reference) = v_norm) THEN
    RETURN QUERY SELECT false, 'duplicate_transaction_ref';
    RETURN;
  END IF;
  RETURN QUERY SELECT true, 'available';
END;
$function$;
GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(text) TO authenticated;

-- 2) validate_payment_code — حد الطول الأدنى السابق (4)
CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_code    RECORD;
  v_norm    text;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('paycode:' || v_user_id::text, 60, 3600);
  IF NOT v_rate.allowed THEN
    RETURN QUERY SELECT false, 'rate_limited'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  v_norm := upper(btrim(coalesce(p_code, '')));
  IF length(v_norm) < 4 THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'cancelled' THEN
    RETURN QUERY SELECT false, 'cancelled'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'used' OR v_code.used_by IS NOT NULL THEN
    RETURN QUERY SELECT false, 'already_used'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'expired'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id THEN
    RETURN QUERY SELECT false, 'not_your_code'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, v_code.amount, v_code.note;
END
$function$;

-- 3) إزالة تريجر قوة الكود ودالته
DROP TRIGGER IF EXISTS trg_enforce_coupon_code_strength ON public.coupons;
DROP FUNCTION IF EXISTS public.enforce_coupon_code_strength();
