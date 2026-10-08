-- ============================================================================
-- RAIZEY STORE — Security & Financial-Integrity Hardening
-- File    : db/migrations/2026-10-08_security_hardening.sql
-- Author  : security audit 2026-10-08 (live DB rglbfizqolrenwfsndyv)
-- Scope   : DB objects only. Additive where possible; no destructive data ops.
-- Notes   : Apply exactly once, in one transaction, on top of the live schema.
--           Supersedes ALL files under deprecated/ (which must never be applied).
-- ============================================================================

-- ════════════════════════════════════════════════════════════════════════════
-- 1) C1 — WALLET LEDGER INTEGRITY
--    Every wallet insert/update must be accompanied, in the same transaction,
--    by a wallet_transactions row whose balance_after equals the new balance.
--    Deferred (checked at COMMIT) so callers may write the ledger row after
--    updating the wallet.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.assert_wallet_ledger_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  -- wallet creation with zero balance needs no ledger entry
  IF TG_OP = 'INSERT' AND NEW.balance = 0 THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.wallet_transactions t
    WHERE t.user_id = NEW.user_id
      AND t.balance_after = NEW.balance
      AND t.created_at >= transaction_timestamp()
  ) THEN
    RAISE EXCEPTION
      'wallet_ledger_entry_required: balance of % changed to % without a matching wallet_transactions row in the same transaction',
      NEW.user_id, NEW.balance;
  END IF;

  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_assert_wallet_ledger ON public.wallets;
CREATE CONSTRAINT TRIGGER trg_assert_wallet_ledger
  AFTER INSERT OR UPDATE ON public.wallets
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION public.assert_wallet_ledger_entry();

-- 1.2 Opening-balance reconciliation (additive only; for wallets that have NO
--     ledger history at all). Auditable source = opening_balance.
INSERT INTO public.wallet_transactions
  (user_id, amount, direction, balance_after, source, details)
SELECT w.user_id, w.balance, 'credit', w.balance, 'opening_balance',
       jsonb_build_object(
         'reason', 'ledger_reconciliation_2026-10-08',
         'note',   'Opening entry created by security hardening: this balance had no prior ledger rows.'
       )
FROM public.wallets w
WHERE w.balance <> 0
  AND NOT EXISTS (SELECT 1 FROM public.wallet_transactions t WHERE t.user_id = w.user_id);

-- ════════════════════════════════════════════════════════════════════════════
-- 2) C2 — NO WALLET FUNDING WITHOUT A RECEIPT
-- ════════════════════════════════════════════════════════════════════════════
-- 2.1 Only the SECURITY DEFINER RPC may create / mutate topups
REVOKE INSERT, UPDATE, DELETE ON public.wallet_topups FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.wallets        FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.wallet_transactions FROM authenticated;

-- 2.2 Defense in depth: server-side column protection on direct inserts
CREATE OR REPLACE FUNCTION public.protect_topup_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.receipt_id IS NULL
     OR NULLIF(btrim(COALESCE(NEW.transaction_reference, '')), '') IS NULL THEN
    RAISE EXCEPTION 'topup_requires_receipt';
  END IF;

  NEW.status          := 'pending';
  NEW.reviewed_at     := NULL;
  NEW.amount_verified := false;
  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS trg_protect_topup_insert ON public.wallet_topups;
CREATE TRIGGER trg_protect_topup_insert
  BEFORE INSERT ON public.wallet_topups
  FOR EACH ROW EXECUTE FUNCTION public.protect_topup_insert();

-- 2.3 admin_confirm_topup: never credit without verified payment evidence
CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid, p_override_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_topup       public.wallet_topups%ROWTYPE;
  v_detected    numeric;
  v_diff        numeric;
  v_tolerance   numeric;
  v_overrode    boolean := false;
  v_new_balance numeric;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_wallets') THEN
    RAISE EXCEPTION 'access_denied: manage_wallets permission required';
  END IF;

  SELECT * INTO v_topup FROM public.wallet_topups WHERE id = p_topup_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'topup_not_found'; END IF;
  IF v_topup.status <> 'pending' THEN RAISE EXCEPTION 'already_processed'; END IF;

  IF v_topup.receipt_id IS NOT NULL THEN
    SELECT pr.amount_detected INTO v_detected
    FROM public.payment_receipts pr
    WHERE pr.id = v_topup.receipt_id;
  END IF;

  -- ── Hall #C2: no receipt / no detected amount ⇒ explicit override only ──
  IF v_topup.receipt_id IS NULL OR v_detected IS NULL THEN
    IF p_override_reason IS NULL OR btrim(p_override_reason) = '' THEN
      RAISE EXCEPTION 'topup_requires_verified_receipt: receipt_id=% amount_detected=%',
        v_topup.receipt_id, v_detected;
    END IF;
    v_overrode := true;
  ELSE
    v_diff      := abs(v_detected - v_topup.amount);
    v_tolerance := GREATEST(v_detected * 0.01, 2);
    IF v_diff > v_tolerance THEN
      IF p_override_reason IS NULL OR btrim(p_override_reason) = '' THEN
        RAISE EXCEPTION 'topup_amount_mismatch: receipt detected % but topup requests %',
          v_detected, v_topup.amount;
      END IF;
      v_overrode := true;
    END IF;
  END IF;

  UPDATE public.wallet_topups
  SET status = 'confirmed', reviewed_at = now()
  WHERE id = p_topup_id;

  INSERT INTO public.wallets (user_id, balance)
  VALUES (v_topup.user_id, v_topup.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = public.wallets.balance + EXCLUDED.balance, updated_at = now()
  RETURNING public.wallets.balance INTO v_new_balance;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_topup.user_id, v_topup.amount, 'credit', v_new_balance, 'topup', p_topup_id, auth.uid());

  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (v_topup.user_id, 'تم تأكيد شحن المحفظة', 'تمت إضافة مبلغ الشحن إلى محفظتك بنجاح.', 'wallet');

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (auth.uid(), 'تأكيد شحن محفظة',
    jsonb_build_object(
      'topup_id', p_topup_id,
      'user_id', v_topup.user_id,
      'amount', v_topup.amount,
      'amount_detected', v_detected,
      'amount_overridden', v_overrode,
      'override_reason', p_override_reason
    ),
    'admin_action');
END
$fn$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3) H1 — RECEIPT CLAIM HARDENING (quarantine + rate limit + release tool)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.claim_payment_receipt(
  p_purpose text,
  p_tx_ref text,
  p_receipt_hash text,
  p_receipt_path text DEFAULT NULL::text,
  p_provider text DEFAULT NULL::text,
  p_payment_method_id uuid DEFAULT NULL::uuid,
  p_amount_expected numeric DEFAULT NULL::numeric,
  p_amount_detected numeric DEFAULT NULL::numeric,
  p_tx_ref_ocr text DEFAULT NULL::text,
  p_ocr_status text DEFAULT 'needs_review'::text,
  p_ocr_confidence numeric DEFAULT NULL::numeric,
  p_risk_flags text[] DEFAULT '{}'::text[],
  p_ocr_data jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(id uuid, ocr_status text, amount_verified boolean, ref_verified boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_user_id   uuid := auth.uid();
  v_norm      text;
  v_hash      text;
  v_amount_v  boolean := false;
  v_ref_v     boolean := false;
  v_status    text;
  v_id        uuid;
  v_scan_id   uuid;
  v_scan      public.receipt_scan_results%ROWTYPE;
  v_status_in text;
  v_rate      RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  -- ── Anti-abuse: bounded claim attempts per user ──
  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('claim:' || v_user_id::text, 30, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'receipt_rate_limited';
  END IF;

  IF p_purpose NOT IN ('order', 'topup') THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  v_hash := lower(trim(coalesce(p_receipt_hash, '')));

  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;
  IF v_hash = '' OR v_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  IF coalesce(p_ocr_status, '') = 'rejected' THEN
    RAISE EXCEPTION 'receipt_rejected';
  END IF;

  v_scan_id   := NULLIF(p_ocr_data->>'edge_scan_id', '')::uuid;
  v_status_in := coalesce(p_ocr_status, 'needs_review');

  IF v_scan_id IS NOT NULL THEN
    SELECT * INTO v_scan
    FROM public.receipt_scan_results rs
    WHERE rs.id = v_scan_id
      AND rs.user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'receipt_scan_not_found';
    END IF;
    IF v_scan.expires_at <= now() THEN
      RAISE EXCEPTION 'receipt_scan_expired';
    END IF;
    IF NOT v_scan.submission_allowed
       OR v_scan.decision = 'reject'
       OR v_scan.ocr_status = 'rejected' THEN
      RAISE EXCEPTION 'receipt_rejected';
    END IF;
    IF lower(trim(coalesce(v_scan.receipt_hash, ''))) <> v_hash THEN
      RAISE EXCEPTION 'receipt_scan_hash_mismatch';
    END IF;
    IF v_scan.claimed_at IS NOT NULL THEN
      RAISE EXCEPTION 'receipt_scan_already_used';
    END IF;

    p_amount_detected := v_scan.amount_detected;
    p_tx_ref_ocr      := v_scan.tx_ref_ocr;
    p_ocr_confidence  := v_scan.ocr_confidence;
    p_provider        := COALESCE(NULLIF(trim(coalesce(p_provider, '')), ''), v_scan.provider);
  ELSE
    -- ⛔ FIX (H1): without a server-side scan the client may NOT choose any
    -- elevated status. Everything lands in quarantine (needs_review) and no
    -- server-derived values are accepted.
    p_amount_detected := NULL;
    p_tx_ref_ocr      := NULL;
    p_ocr_confidence  := NULL;
    p_provider        := NULLIF(trim(coalesce(p_provider, '')), '');
    v_status_in       := 'needs_review';
  END IF;

  -- Historical duplicate protection (legacy rows included)
  IF EXISTS (SELECT 1 FROM orders WHERE public.normalize_tx_ref(transaction_reference) = v_norm)
     OR EXISTS (SELECT 1 FROM wallet_topups WHERE public.normalize_tx_ref(transaction_reference) = v_norm) THEN
    RAISE EXCEPTION 'duplicate_transaction_ref';
  END IF;

  IF EXISTS (SELECT 1 FROM orders        WHERE lower(receipt_hash) = v_hash)
     OR EXISTS (SELECT 1 FROM wallet_topups WHERE lower(receipt_hash) = v_hash) THEN
    RAISE EXCEPTION 'duplicate_receipt_image';
  END IF;

  IF p_amount_expected IS NOT NULL AND p_amount_detected IS NOT NULL
     AND p_amount_expected > 0 THEN
    v_amount_v := abs(p_amount_detected - p_amount_expected) <= GREATEST(p_amount_expected * 0.01, 2);
  END IF;

  v_ref_v := public.normalize_tx_ref(p_tx_ref_ocr) IS NOT NULL
             AND public.normalize_tx_ref(p_tx_ref_ocr) = v_norm;

  IF v_amount_v AND v_ref_v THEN
    IF v_status_in = 'needs_admin_check' THEN
      v_status := 'needs_admin_check';
    ELSE
      v_status := 'passed';
    END IF;
  ELSIF v_status_in = 'needs_admin_check' AND v_scan_id IS NOT NULL THEN
    v_status := 'needs_admin_check';
  ELSE
    v_status := 'needs_review';
  END IF;

  BEGIN
    INSERT INTO payment_receipts (
      user_id, purpose, provider, payment_method_id,
      tx_ref_raw, tx_ref_norm, tx_ref_ocr,
      receipt_hash, receipt_path,
      amount_expected, amount_detected,
      amount_verified, ref_verified,
      ocr_status, ocr_confidence, risk_flags, ocr_data
    ) VALUES (
      v_user_id, p_purpose, nullif(trim(coalesce(p_provider,'')),''), p_payment_method_id,
      trim(p_tx_ref), v_norm, nullif(trim(coalesce(p_tx_ref_ocr,'')),''),
      v_hash, p_receipt_path,
      p_amount_expected, p_amount_detected,
      v_amount_v, v_ref_v,
      v_status, p_ocr_confidence, coalesce(p_risk_flags, '{}'), coalesce(p_ocr_data, '{}'::jsonb)
    )
    RETURNING payment_receipts.id INTO v_id;
  EXCEPTION
    WHEN unique_violation THEN
      IF EXISTS (SELECT 1 FROM payment_receipts WHERE tx_ref_norm = v_norm) THEN
        RAISE EXCEPTION 'duplicate_transaction_ref';
      ELSE
        RAISE EXCEPTION 'duplicate_receipt_image';
      END IF;
  END;

  IF v_scan_id IS NOT NULL THEN
    UPDATE public.receipt_scan_results rs
    SET claimed_at         = COALESCE(rs.claimed_at, now()),
        claimed_receipt_id = COALESCE(rs.claimed_receipt_id, v_id)
    WHERE rs.id = v_scan_id;
  END IF;

  RETURN QUERY SELECT v_id, v_status, v_amount_v, v_ref_v;
END
$fn$;

-- 3.2 Ops tool: release a tx_ref burned by a junk / unverified claim
CREATE OR REPLACE FUNCTION public.admin_release_receipt(p_receipt_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_r      public.payment_receipts%ROWTYPE;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION 'reason_required'; END IF;

  SELECT * INTO v_r FROM public.payment_receipts WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'receipt_not_found'; END IF;

  IF EXISTS (SELECT 1 FROM public.orders        o WHERE o.receipt_id = p_receipt_id)
     OR EXISTS (SELECT 1 FROM public.wallet_topups t WHERE t.receipt_id = p_receipt_id) THEN
    RAISE EXCEPTION 'receipt_in_use: linked to an order or topup';
  END IF;
  IF v_r.ocr_status <> 'needs_review' THEN
    RAISE EXCEPTION 'receipt_not_releasable: only unverified (needs_review) claims can be released';
  END IF;

  DELETE FROM public.payment_receipts WHERE id = p_receipt_id;

  PERFORM public.append_admin_audit_log(
    'release_receipt', 'payment_receipts', p_receipt_id::text,
    jsonb_build_object('reason', v_reason,
                       'tx_ref_norm', v_r.tx_ref_norm,
                       'receipt_path', v_r.receipt_path,
                       'user_id', v_r.user_id));
END
$fn$;

REVOKE EXECUTE ON FUNCTION public.admin_release_receipt(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_release_receipt(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 4) H3 — ORDER PRICE / RECEIPT TRIGGER: fix dead column references
--     (was: NEW.payment_method / NEW.tx_ref — columns do not exist ⇒ 42703)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_product      RECORD;
  v_receipt      RECORD;
  v_rate         numeric;
  v_margin       numeric;
  v_expected     numeric;
  v_option_usd   numeric;
  v_discount_pct numeric := 0;
  v_min_allowed  numeric;
  v_option       jsonb;
  v_option_id    text;
BEGIN
  IF COALESCE(current_setting('raizey.trusted_order', true), '') = 'on'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product
  FROM products
  WHERE products.id = NEW.product_id AND products.is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'product_not_found'; END IF;

  -- ── Bank orders must reference the caller's own, server-verified receipt ──
  IF NEW.payment_type = 'bank' THEN
    IF NEW.receipt_id IS NULL THEN
      RAISE EXCEPTION 'receipt_required';
    END IF;
    SELECT * INTO v_receipt
    FROM public.payment_receipts pr
    WHERE pr.id = NEW.receipt_id
      AND pr.user_id = auth.uid()
      AND pr.ocr_status IN ('passed', 'needs_admin_check')
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'receipt_not_verified';
    END IF;
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF NEW.selected_option IS NULL
       OR COALESCE(btrim(NEW.selected_option->>'id'), '') = '' THEN
      RAISE EXCEPTION 'option_required';
    END IF;

    v_option_id := NEW.selected_option->>'id';
    SELECT opt INTO v_option
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = v_option_id
    LIMIT 1;
    IF v_option IS NULL THEN RAISE EXCEPTION 'option_not_found'; END IF;

    v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
    IF v_option_usd <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;
    v_expected := v_option_usd * v_rate * (1 + v_margin / 100.0);
  ELSE
    v_expected := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
  END IF;

  IF v_expected <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;

  IF NEW.coupon_id IS NOT NULL THEN
    SELECT discount_percent INTO v_discount_pct
    FROM coupons
    WHERE id = NEW.coupon_id AND is_active = true
      AND (valid_from IS NULL OR now() >= valid_from)
      AND (valid_until IS NULL OR now() <= valid_until);
    IF NOT FOUND OR COALESCE(v_discount_pct, 0) <= 0 THEN
      RAISE EXCEPTION 'coupon_invalid';
    END IF;
  END IF;

  v_min_allowed := v_expected * (1 - COALESCE(v_discount_pct, 0) / 100.0) * 0.99;

  IF NEW.price_sdg_snapshot < v_min_allowed THEN
    RAISE EXCEPTION 'price_tampered';
  END IF;

  RETURN NEW;
END
$fn$;

-- 4.2 Orders are written exclusively through SECURITY DEFINER RPCs
REVOKE INSERT, UPDATE, DELETE ON public.orders FROM authenticated;

-- 4.3 Protect the payment-code link on updates
CREATE OR REPLACE FUNCTION public.protect_order_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

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
  NEW.payment_code_id          := OLD.payment_code_id;
  NEW.receipt_id               := OLD.receipt_id;
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
END
$fn$;

-- ════════════════════════════════════════════════════════════════════════════
-- 5) H2 — PAYMENT-EVIDENCE MODEL + COMPLETION GUARD
--    Every order now carries a verifiable payment link:
--      bank  → receipt_id (server-verified)
--      wallet→ wallet_transactions debit
--      code  → payment_code_id (used code of the same user)
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_code_id uuid REFERENCES public.payment_codes(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS orders_payment_code_id_idx ON public.orders (payment_code_id);

-- 5.1 Auto-link code orders to the code consumed in the same transaction
--     (the RPCs mark the code as used after inserting the orders).
CREATE OR REPLACE FUNCTION public.link_order_payment_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_code uuid;
BEGIN
  IF NEW.payment_type <> 'code' OR NEW.payment_code_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  SELECT pc.id INTO v_code
  FROM public.payment_codes pc
  WHERE pc.used_by = NEW.user_id
    AND pc.status = 'used'
    AND pc.used_at >= transaction_timestamp()
  ORDER BY pc.used_at DESC
  LIMIT 1;

  IF v_code IS NOT NULL THEN
    UPDATE public.orders SET payment_code_id = v_code WHERE id = NEW.id;
  END IF;
  RETURN NULL;
END
$fn$;

DROP TRIGGER IF EXISTS trg_link_order_payment_code ON public.orders;
CREATE CONSTRAINT TRIGGER trg_link_order_payment_code
  AFTER INSERT ON public.orders
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.link_order_payment_code();

-- 5.2 Backfill the single historical code order
UPDATE public.orders o
SET payment_code_id = pc.id
FROM public.payment_codes pc
WHERE o.payment_type = 'code'
  AND o.payment_code_id IS NULL
  AND pc.order_id = o.id;

-- 5.3 Completion guard with auditable override
DROP FUNCTION IF EXISTS public.admin_update_order_status(uuid, text);
CREATE OR REPLACE FUNCTION public.admin_update_order_status(
  p_order_id uuid,
  p_status text,
  p_override_reason text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_order    public.orders%ROWTYPE;
  v_status   text := lower(btrim(COALESCE(p_status, '')));
  v_reason   text := NULLIF(btrim(COALESCE(p_override_reason, '')), '');
  v_evidence boolean := false;
  v_overrode boolean := false;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;

  IF v_status NOT IN ('in_progress', 'completed', 'cancelled') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF v_status = 'in_progress' AND v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  IF v_status = 'completed' AND v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  IF v_status = 'cancelled' AND v_order.status NOT IN ('pending_review', 'in_progress') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  -- ── Payment evidence is mandatory to complete an order ──
  IF v_status = 'completed' THEN
    IF v_order.payment_type = 'bank' THEN
      v_evidence := v_order.receipt_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_receipts pr
        WHERE pr.id = v_order.receipt_id
          AND pr.user_id = v_order.user_id
          AND (pr.amount_verified IS TRUE OR pr.ocr_status = 'needs_admin_check')
      );
    ELSIF v_order.payment_type = 'wallet' THEN
      v_evidence := EXISTS (
        SELECT 1 FROM public.wallet_transactions t
        WHERE t.direction = 'debit'
          AND t.user_id = v_order.user_id
          AND (t.reference_id = v_order.id OR t.details->'order_ids' ? v_order.id::text)
      );
    ELSIF v_order.payment_type = 'code' THEN
      v_evidence := v_order.payment_code_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_codes pc
        WHERE pc.id = v_order.payment_code_id
          AND pc.status = 'used'
          AND pc.used_by = v_order.user_id
      );
    END IF;

    IF NOT v_evidence THEN
      IF v_reason IS NULL THEN
        RAISE EXCEPTION 'unverified_payment_evidence: order % (%) has no verifiable payment evidence', p_order_id, v_order.payment_type;
      END IF;
      v_overrode := true;
    END IF;
  END IF;

  UPDATE public.orders
  SET status = v_status, updated_at = now()
  WHERE id = p_order_id;

  IF v_status = 'cancelled'
     AND v_order.payment_type = 'wallet'
     AND COALESCE(v_order.refunded, false) = false THEN
    PERFORM public.admin_refund_wallet(p_order_id, 'order_cancelled');
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (
    auth.uid(),
    'تغيير حالة طلب',
    jsonb_build_object('order_id', p_order_id, 'from', v_order.status, 'to', v_status,
                       'payment_type', v_order.payment_type,
                       'evidence_ok', v_evidence, 'overridden', v_overrode,
                       'override_reason', v_reason)
  );
END
$fn$;

REVOKE EXECUTE ON FUNCTION public.admin_update_order_status(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_update_order_status(uuid, text, text) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6) M1/M2/L1 — EXPOSURE & GRANT HYGIENE
-- ════════════════════════════════════════════════════════════════════════════
-- 6.1 pg_stat_statements was readable by anonymous visitors (recon leak)
REVOKE SELECT ON extensions.pg_stat_statements FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements(boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements_info() FROM PUBLIC;

-- 6.2 Wallet history was unusable (policy existed, table grant was missing)
GRANT SELECT ON public.wallet_transactions TO authenticated;

-- 6.3 No PUBLIC (anon) execution on administrative / internal helpers
REVOKE EXECUTE ON FUNCTION public.admin_confirm_topup(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_refund_wallet(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_privilege_model() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.generate_order_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_order_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.touch_subcategories_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.normalize_tx_ref(text) FROM PUBLIC, anon;

-- ════════════════════════════════════════════════════════════════════════════
-- 7) M3/M4 — RATE LIMITS ON ORACLES & LOG SINKS
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.validate_coupon(p_code text, p_order_total numeric DEFAULT NULL::numeric)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('coupon:' || v_user_id::text, 60, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'coupon_rate_limited';
  END IF;

  SELECT c.id, c.discount_percent AS pct, COALESCE(c.min_order_sdg, 0) AS min_order_sdg
  INTO v_coupon
  FROM coupons c
  WHERE upper(c.code) = upper(btrim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM coupon_redemptions cr
    WHERE cr.coupon_id = v_coupon.id AND cr.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'coupon_already_used';
  END IF;

  IF p_order_total IS NOT NULL AND v_coupon.min_order_sdg > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  RETURN QUERY SELECT v_coupon.id, LEAST(GREATEST(COALESCE(v_coupon.pct, 0), 0), 95);
END
$fn$;

CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
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
$fn$;

CREATE OR REPLACE FUNCTION public.report_fraud_alert(p_details jsonb DEFAULT '{}'::jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_id   uuid;
  v_rate RECORD;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('fraudrep:' || auth.uid()::text, 20, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (
    NULL,
    'fraud_alert_duplicate_receipt',
    COALESCE(p_details, '{}'::jsonb) || jsonb_build_object('reporter_id', auth.uid()),
    'customer_report'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END
$fn$;

CREATE OR REPLACE FUNCTION public.log_receipt_fraud_attempt(
  p_entered_reference text,
  p_reason text,
  p_provider text DEFAULT NULL::text,
  p_ocr_excerpt text DEFAULT NULL::text,
  p_order_amount numeric DEFAULT NULL::numeric,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- best-effort telemetry: throttle hard, never fail the caller
  BEGIN
    SELECT * INTO v_rate FROM public.consume_chat_rate_limit('fraudlog:' || v_user_id::text, 60, 3600);
    IF NOT v_rate.allowed THEN
      RETURN;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN;
  END;

  INSERT INTO receipt_fraud_attempts (
    user_id, entered_reference, normalized_reference, reason,
    provider, ocr_excerpt, order_amount, metadata
  ) VALUES (
    v_user_id,
    left(coalesce(p_entered_reference, ''), 100),
    public.normalize_tx_ref(p_entered_reference),
    left(coalesce(p_reason, 'unknown'), 60),
    left(coalesce(p_provider, ''), 40),
    left(coalesce(p_ocr_excerpt, ''), 500),
    p_order_amount,
    coalesce(p_metadata, '{}'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  NULL;
END
$fn$;

-- ════════════════════════════════════════════════════════════════════════════
-- 8) H4 — REFERRAL CODE ENTROPY
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_referral_short_code_format;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_referral_short_code_format
  CHECK (referral_short_code IS NULL OR referral_short_code ~ '^[A-Z0-9]{5,12}$');

CREATE UNIQUE INDEX IF NOT EXISTS profiles_referral_code_uniq
  ON public.profiles (upper(referral_code)) WHERE referral_code IS NOT NULL;

CREATE OR REPLACE FUNCTION public.generate_referral_short_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_code     text;
  v_attempt  integer := 0;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    v_code := 'RZY';
    FOR i IN 1..8 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_short_code = v_code);
    IF v_attempt > 25 THEN
      RAISE EXCEPTION 'referral_code_generation_failed';
    END IF;
  END LOOP;
  RETURN v_code;
END
$fn$;

-- ════════════════════════════════════════════════════════════════════════════
-- 9) FINALISERS — allow the deferred payment-code linker to persist its link
--    (trusted order GUC is transaction-local and can only be set from inside
--     SECURITY DEFINER routines — same escape hatch the price trigger uses)
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.protect_order_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF public.is_admin()
     OR COALESCE(current_setting('raizey.trusted_order', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

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
  NEW.payment_code_id          := OLD.payment_code_id;
  NEW.receipt_id               := OLD.receipt_id;
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
END
$fn$;

CREATE OR REPLACE FUNCTION public.link_order_payment_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_code uuid;
BEGIN
  IF NEW.payment_type <> 'code' OR NEW.payment_code_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  SELECT pc.id INTO v_code
  FROM public.payment_codes pc
  WHERE pc.used_by = NEW.user_id
    AND pc.status = 'used'
    AND pc.used_at >= transaction_timestamp()
  ORDER BY pc.used_at DESC
  LIMIT 1;

  IF v_code IS NOT NULL THEN
    PERFORM set_config('raizey.trusted_order', 'on', true);
    UPDATE public.orders SET payment_code_id = v_code WHERE id = NEW.id;
    PERFORM set_config('raizey.trusted_order', 'off', true);
  END IF;
  RETURN NULL;
END
$fn$;

SELECT 'migration_2026-10-08_security_hardening_applied' AS status;
