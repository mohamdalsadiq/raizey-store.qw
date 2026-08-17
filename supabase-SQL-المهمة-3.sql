-- RAIZEY STORE — Task 3: unified wallet receipt claim
-- شغّل هذا الملف بعد supabase-critical-fixes-5.sql وsupabase-critical-fixes-7.sql.

ALTER TABLE public.wallet_topups
  ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES public.payment_receipts(id);
ALTER TABLE public.wallet_topups
  ADD COLUMN IF NOT EXISTS ocr_status text DEFAULT 'needs_review';
ALTER TABLE public.wallet_topups
  ADD COLUMN IF NOT EXISTS amount_verified boolean DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_wallet_topups_receipt_id
  ON public.wallet_topups(receipt_id);

CREATE OR REPLACE FUNCTION public.create_wallet_topup_from_receipt(
  p_amount            numeric,
  p_payment_method_id uuid,
  p_receipt_url       text,
  p_tx_ref            text,
  p_receipt_hash      text,
  p_receipt_path      text DEFAULT NULL,
  p_provider          text DEFAULT NULL,
  p_amount_detected   numeric DEFAULT NULL,
  p_tx_ref_ocr        text DEFAULT NULL,
  p_ocr_status        text DEFAULT 'needs_review',
  p_ocr_confidence    numeric DEFAULT NULL,
  p_risk_flags        text[] DEFAULT '{}',
  p_ocr_data          jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(
  id uuid,
  receipt_id uuid,
  ocr_status text,
  amount_verified boolean,
  ref_verified boolean
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_claim RECORD;
  v_topup_id uuid;
  v_status text := 'pending';
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_payment_method_id IS NULL THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'topup',
    p_tx_ref,
    p_receipt_hash,
    p_receipt_path,
    p_provider,
    p_payment_method_id,
    p_amount,
    p_amount_detected,
    p_tx_ref_ocr,
    COALESCE(NULLIF(p_ocr_status, ''), 'needs_review'),
    p_ocr_confidence,
    COALESCE(p_risk_flags, '{}'),
    COALESCE(p_ocr_data, '{}'::jsonb)
  ) c;

  IF v_claim.id IS NULL THEN RAISE EXCEPTION 'receipt_claim_failed'; END IF;

  INSERT INTO public.wallet_topups (
    user_id, amount, payment_method_id, receipt_id, receipt_url,
    receipt_hash, transaction_reference, status, ocr_status, amount_verified
  ) VALUES (
    v_user_id, p_amount, p_payment_method_id, v_claim.id, p_receipt_url,
    lower(trim(p_receipt_hash)), trim(p_tx_ref), v_status,
    v_claim.ocr_status, v_claim.amount_verified
  )
  RETURNING wallet_topups.id INTO v_topup_id;

  RETURN QUERY SELECT v_topup_id, v_claim.id, v_claim.ocr_status,
                      v_claim.amount_verified, v_claim.ref_verified;
END;
$$;

REVOKE ALL ON FUNCTION public.create_wallet_topup_from_receipt(
  numeric, uuid, text, text, text, text, text, numeric, text, text, numeric, text[], jsonb
) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.create_wallet_topup_from_receipt(
  numeric, uuid, text, text, text, text, text, numeric, text, text, numeric, text[], jsonb
) TO authenticated;

NOTIFY pgrst, 'reload schema';
