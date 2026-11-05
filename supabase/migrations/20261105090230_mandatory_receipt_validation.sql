-- Mandatory server verification; atomic split receipts. No historical rows are rewritten.
BEGIN;
CREATE OR REPLACE FUNCTION public.claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text DEFAULT NULL::text, p_provider text DEFAULT NULL::text, p_payment_method_id uuid DEFAULT NULL::uuid, p_amount_expected numeric DEFAULT NULL::numeric, p_amount_detected numeric DEFAULT NULL::numeric, p_tx_ref_ocr text DEFAULT NULL::text, p_ocr_status text DEFAULT 'needs_review'::text, p_ocr_confidence numeric DEFAULT NULL::numeric, p_risk_flags text[] DEFAULT '{}'::text[], p_ocr_data jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id uuid, ocr_status text, amount_verified boolean, ref_verified boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_attachment uuid;
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

  PERFORM private.assert_session_aal();
  IF p_amount_expected IS NULL OR p_amount_expected<=0 OR p_amount_expected::text IN ('NaN','Infinity','-Infinity') OR
     (p_purpose='topup' AND p_amount_expected>10000000) THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.payment_methods pm WHERE pm.id=p_payment_method_id AND pm.is_active) THEN RAISE EXCEPTION 'invalid_payment_method'; END IF;
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

  v_attachment:=private.assert_receipt_attachment(v_user_id,p_receipt_path,v_hash);
  v_scan_id   := NULLIF(p_ocr_data->>'edge_scan_id', '')::uuid;
  v_status_in := coalesce(p_ocr_status, 'needs_review');

  IF v_scan_id IS NULL THEN RAISE EXCEPTION 'automatic_check_required'; END IF;
  IF v_scan_id IS NOT NULL THEN
    SELECT * INTO v_scan
    FROM public.receipt_scan_results rs
    WHERE rs.id = v_scan_id
      AND rs.user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'receipt_scan_not_found';
    END IF;
    IF v_scan.ocr_data->>'receipt_path' IS DISTINCT FROM p_receipt_path OR
       v_scan.ocr_data->>'attachment_id' IS DISTINCT FROM v_attachment::text THEN RAISE EXCEPTION 'receipt_scan_attachment_mismatch'; END IF;
    IF public.normalize_tx_ref(v_scan.manual_ref) IS DISTINCT FROM v_norm THEN RAISE EXCEPTION 'receipt_scan_ref_mismatch'; END IF;
    IF v_scan.expires_at <= now() THEN
      RAISE EXCEPTION 'receipt_scan_expired';
    END IF;
    IF v_scan.ocr_data->>'receipt_policy' IS DISTINCT FROM 'mandatory-visual-v1' OR
       v_scan.ocr_data->>'automatic_check_complete' IS DISTINCT FROM 'true' OR
       v_scan.ocr_data->>'ref_verified' IS DISTINCT FROM 'true' OR
       v_scan.ocr_data->>'amount_verified' IS DISTINCT FROM 'true' OR
       v_scan.expected_account IS DISTINCT FROM (SELECT pm.account_number FROM public.payment_methods pm WHERE pm.id=p_payment_method_id)
    THEN RAISE EXCEPTION 'automatic_check_required'; END IF;
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

    IF p_payment_method_id IS NULL OR
       v_scan.ocr_data->>'expected_method_id' IS DISTINCT FROM p_payment_method_id::text THEN
      RAISE EXCEPTION 'receipt_scan_method_mismatch';
    END IF;
    IF v_scan.expected_amount IS NULL OR p_amount_expected IS NULL OR
       abs(v_scan.expected_amount-p_amount_expected)>0.01 THEN
      RAISE EXCEPTION 'receipt_scan_amount_mismatch';
    END IF;
    -- Preserve the server decision and diagnostics; client data may only downgrade it.
    v_status_in := v_scan.ocr_status;
    IF p_ocr_status IN ('needs_review','needs_admin_check') AND v_status_in='passed' THEN
      v_status_in:=p_ocr_status;
    END IF;
    p_risk_flags:=v_scan.risk_flags;
    p_ocr_data:=v_scan.ocr_data || jsonb_build_object('edge_scan_id',v_scan.id);
    p_provider:=v_scan.provider;
    p_amount_detected := v_scan.amount_detected;
    p_tx_ref_ocr      := v_scan.tx_ref_ocr;
    p_ocr_confidence  := v_scan.ocr_confidence;


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
    v_amount_v := abs(p_amount_detected - p_amount_expected) < 0.01;
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

  IF v_scan_id IS NOT NULL AND v_status_in <> 'passed' THEN
    v_status:=CASE WHEN v_status_in='needs_admin_check' THEN 'needs_admin_check' ELSE 'needs_review' END;
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
$function$;

-- Defence in depth: no other legacy routine can insert an unchecked receipt.
CREATE OR REPLACE FUNCTION private.require_automatic_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s public.receipt_scan_results%ROWTYPE;
BEGIN
 SELECT * INTO s FROM public.receipt_scan_results WHERE id=(NEW.ocr_data->>'edge_scan_id')::uuid FOR UPDATE;
 IF NOT FOUND OR s.user_id IS DISTINCT FROM NEW.user_id OR s.claimed_at IS NOT NULL OR s.expires_at<=now() OR
    s.submission_allowed IS DISTINCT FROM true OR s.decision<>'accept' OR s.ocr_status<>'passed' OR
    s.ocr_data->>'receipt_policy' IS DISTINCT FROM 'mandatory-visual-v1' OR
    s.ocr_data->>'automatic_check_complete' IS DISTINCT FROM 'true' OR
    s.ocr_data->>'ref_verified' IS DISTINCT FROM 'true' OR s.ocr_data->>'amount_verified' IS DISTINCT FROM 'true' OR
    s.ocr_data->>'receipt_path' IS DISTINCT FROM NEW.receipt_path OR s.receipt_hash IS DISTINCT FROM NEW.receipt_hash OR
    s.ocr_data->>'expected_method_id' IS DISTINCT FROM NEW.payment_method_id::text OR
    public.normalize_tx_ref(s.manual_ref) IS DISTINCT FROM NEW.tx_ref_norm OR
    s.expected_amount IS NULL OR abs(s.expected_amount-NEW.amount_expected)>=0.01
 THEN RAISE EXCEPTION 'automatic_check_required'; END IF;
 UPDATE public.receipt_scan_results SET claimed_at=now(),claimed_receipt_id=NEW.id WHERE id=s.id;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.require_automatic_receipt() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS require_automatic_receipt ON public.payment_receipts;
CREATE TRIGGER require_automatic_receipt AFTER INSERT ON public.payment_receipts FOR EACH ROW EXECUTE FUNCTION private.require_automatic_receipt();

CREATE OR REPLACE FUNCTION public.create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_alloc_weight numeric := 0;
  v_alloc_charged numeric := 0;
  v_weight_total numeric;
  v_alloc_amount numeric;
  v_user_id      uuid := auth.uid();
  v_rate         numeric;
  v_margin       numeric;
  v_coupon_id    uuid;
  v_discount_pct numeric := 0;
  v_total        numeric := 0;
  v_item         jsonb;
  v_product      RECORD;
  v_option       jsonb;
  v_option_usd   numeric;
  v_unit         numeric;
  v_qty          int;
  v_name         text;
  v_order_id     uuid;
  v_lines        jsonb := '[]'::jsonb;
  v_line         jsonb;
  v_ids          uuid[] := '{}';
  v_claim        RECORD;
  v_secondary_claim RECORD;
  v_first_amount numeric;
  v_secondary jsonb;
  v_method_id    uuid;
  v_receipt_url  text;
  v_tx_ref_raw   text;
  v_receipt_hash text;
  v_ocr_in       text;
  v_ocr_final    text;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings ss WHERE ss.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN
    RAISE EXCEPTION 'cart_too_large';
  END IF;
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_method_id   := NULLIF(p_receipt->>'payment_method_id', '')::uuid;
  v_receipt_url := NULLIF(p_receipt->>'receipt_url', '');
  v_ocr_in      := COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_review');

  IF v_method_id IS NULL THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- ── المرور الأول: التحقق وحساب الأسعار من القاعدة فقط ──
  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN
      RAISE EXCEPTION 'invalid_quantity';
    END IF;

    SELECT p.* INTO v_product FROM products p
    WHERE p.id = (v_item->>'product_id')::uuid AND p.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    PERFORM private.assert_order_fields(v_product.required_fields,COALESCE(v_item->'field_values','{}'::jsonb));
    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(btrim(v_item->>'option_id'), '') = '' THEN
        RAISE EXCEPTION 'option_required';
      END IF;

      SELECT opt INTO v_option
      FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id')
      LIMIT 1;

      IF v_option IS NULL THEN
        RAISE EXCEPTION 'option_not_found';
      END IF;

      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN
        RAISE EXCEPTION 'price_calculation_error';
      END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;

    v_lines := v_lines || jsonb_build_object(
      'product_id',   v_product.id,
      'name',         v_name,
      'unit',         v_unit,
      'quantity',     v_qty,
      'option',       v_option,
      'field_values', COALESCE(v_item->'field_values', '{}'::jsonb),
      'field_labels', COALESCE(v_item->'field_labels', '{}'::jsonb)
    );

    v_total := v_total + (v_unit * v_qty);
  END LOOP;

  -- ── الكوبون: مرة واحدة فقط للسلة كاملة ──
  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  -- Preserve the existing rounded basket charge. Allocate it to orders to the cent.
  v_total := ROUND(v_total * (1.0-v_discount_pct/100.0));
  IF v_total <= 0 THEN v_total:=1; END IF;

  v_first_amount := v_total;
  v_secondary := p_receipt->'secondary_receipt';
  IF v_secondary IS NOT NULL AND v_secondary <> 'null'::jsonb THEN
    IF jsonb_typeof(v_secondary)<>'object' OR v_secondary->>'payment_method_id' IS DISTINCT FROM v_method_id::text THEN RAISE EXCEPTION 'invalid_split_payment'; END IF;
    SELECT rs.expected_amount INTO v_first_amount FROM public.receipt_scan_results rs
      WHERE rs.id=(p_receipt->'ocr_data'->>'edge_scan_id')::uuid AND rs.user_id=v_user_id;
    IF v_first_amount IS NULL OR v_first_amount<=0 OR v_first_amount>=v_total THEN RAISE EXCEPTION 'invalid_split_payment'; END IF;
  END IF;

  -- ── حجز الإيصال داخل نفس المعاملة (المبلغ المتوقع يُحسب هنا) ──
  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    v_method_id,
    v_first_amount,
    NULLIF(p_receipt->>'amount_detected', '')::numeric,
    NULLIF(p_receipt->>'tx_ref_ocr', ''),
    v_ocr_in,
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
  ) c;

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  IF v_secondary IS NOT NULL AND v_secondary <> 'null'::jsonb THEN
    SELECT c.* INTO v_secondary_claim FROM public.claim_payment_receipt(
      'order',v_secondary->>'tx_ref',v_secondary->>'receipt_hash',v_secondary->>'receipt_path',NULL,v_method_id,
      v_total-v_first_amount,NULL,NULL,'passed',NULL,'{}'::text[],coalesce(v_secondary->'ocr_data','{}'::jsonb)
    ) c;
    IF v_secondary_claim.id IS NULL THEN RAISE EXCEPTION 'receipt_claim_failed'; END IF;
    UPDATE public.payment_receipts SET parent_receipt_id=v_claim.id WHERE payment_receipts.id=v_secondary_claim.id;
    UPDATE public.payment_receipts pr SET ocr_data=pr.ocr_data || jsonb_build_object('split_payment',jsonb_build_object(
      'first_amount',v_first_amount,'second_amount',v_total-v_first_amount,'total',v_total,
      'second_tx_ref',(SELECT tx_ref_raw FROM public.payment_receipts WHERE payment_receipts.id=v_secondary_claim.id),
      'second_receipt_path',(SELECT receipt_path FROM public.payment_receipts WHERE payment_receipts.id=v_secondary_claim.id),
      'second_receipt_id',v_secondary_claim.id)) WHERE pr.id=v_claim.id;
  END IF;

  -- ── إيصال طلب الفحص الذكي تدقيقاً إدارياً لا يُرقّى إلى passed ──
  -- (مثال: إشعار قديم جداً — الرقم والمبلغ مطابقان لكنه يحتاج نظر الإدارة)
  v_ocr_final := v_claim.ocr_status;
  IF v_ocr_in IN ('needs_admin_check', 'needs_review') AND v_ocr_final = 'passed' THEN
    v_ocr_final := v_ocr_in;
    UPDATE payment_receipts pr SET ocr_status = v_ocr_final WHERE pr.id = v_claim.id;
  END IF;

  SELECT pr.tx_ref_raw, pr.receipt_hash
  INTO   v_tx_ref_raw, v_receipt_hash
  FROM   payment_receipts pr WHERE pr.id = v_claim.id;

  -- ── إدخال الطلبات (صف لكل قطعة) ──
  PERFORM set_config('raizey.trusted_order', 'on', true);

  SELECT SUM((line->>'unit')::numeric*(line->>'quantity')::integer)
    INTO v_weight_total FROM jsonb_array_elements(v_lines) line;
  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      v_alloc_weight := v_alloc_weight+(v_line->>'unit')::numeric;
      v_alloc_amount := ROUND(v_total*v_alloc_weight/v_weight_total,2)-v_alloc_charged;
      v_alloc_charged := v_alloc_charged+v_alloc_amount;
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id,
        payment_method_id, receipt_id, receipt_url, receipt_hash,
        transaction_reference, ocr_status, amount_verified, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        v_alloc_amount,
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'bank', 'pending_review', v_coupon_id,
        v_method_id, v_claim.id, v_receipt_url, v_receipt_hash,
        v_tx_ref_raw, v_ocr_final, v_claim.amount_verified, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;

CREATE OR REPLACE FUNCTION public.attach_secondary_receipt(p_parent_tx_ref text,p_order_id uuid,p_receipt jsonb)
RETURNS TABLE(id uuid) LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'atomic_split_payment_required'; END $$;
REVOKE ALL ON FUNCTION public.attach_secondary_receipt(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_order_status(p_order_id uuid, p_status text, p_override_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  IF v_order.payment_type='bank' AND v_status IN ('in_progress','completed') AND NOT EXISTS(
    SELECT 1 FROM public.payment_receipts WHERE id=v_order.receipt_id AND user_id=v_order.user_id AND payment_verified
  ) THEN
    IF char_length(coalesce(v_reason,'')) NOT BETWEEN 6 AND 500 THEN RAISE EXCEPTION 'bank_review_required'; END IF;
    IF v_order.receipt_id IS NULL THEN RAISE EXCEPTION 'receipt_required'; END IF;
    UPDATE public.payment_receipts SET payment_verified=true,payment_verified_at=now(),payment_verified_by=auth.uid(),payment_verification_note=v_reason
    WHERE (id=v_order.receipt_id OR parent_receipt_id=v_order.receipt_id) AND user_id=v_order.user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'receipt_not_owned'; END IF;
  END IF;

  -- ── Payment evidence is mandatory to complete an order ──
  IF v_status = 'completed' THEN
    IF v_order.payment_type = 'bank' THEN
      v_evidence := v_order.receipt_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_receipts pr
        WHERE pr.id = v_order.receipt_id
          AND pr.user_id = v_order.user_id
          AND pr.payment_verified IS TRUE
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
$function$;
COMMIT;
