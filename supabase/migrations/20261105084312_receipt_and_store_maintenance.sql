-- MEEM maintenance. Deploy this migration, Edge Function and frontend together.
-- CLI creation was unavailable in the offline executor (see maintenance report).
BEGIN;

CREATE TABLE IF NOT EXISTS public.receipt_attachments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 bucket_id text NOT NULL DEFAULT 'receipts' CHECK(bucket_id='receipts'),
 object_path text NOT NULL UNIQUE,
 object_id uuid NOT NULL,
 receipt_hash text NOT NULL CHECK(receipt_hash ~ '^[0-9a-f]{64}$'),
 image_bytes integer NOT NULL CHECK(image_bytes BETWEEN 1 AND 5242880),
 mime_type text NOT NULL CHECK(mime_type IN ('image/png','image/jpeg','image/webp')),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.receipt_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.receipt_attachments FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,DELETE ON public.receipt_attachments TO service_role;
CREATE INDEX IF NOT EXISTS receipt_attachments_user_hash ON public.receipt_attachments(user_id,receipt_hash);

CREATE OR REPLACE FUNCTION private.bind_receipt_attachment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE obj storage.objects%ROWTYPE;
BEGIN
 IF NEW.object_path !~ ('^'||NEW.user_id::text||'/verified/[0-9a-f-]{36}\.(png|jpg|webp)$') THEN
  RAISE EXCEPTION 'receipt_path_not_owned';
 END IF;
 SELECT * INTO obj FROM storage.objects WHERE bucket_id='receipts' AND name=NEW.object_path FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'receipt_object_missing'; END IF;
 IF (obj.metadata->>'size')::bigint IS DISTINCT FROM NEW.image_bytes::bigint OR
    obj.metadata->>'mimetype' IS DISTINCT FROM NEW.mime_type THEN RAISE EXCEPTION 'receipt_object_invalid'; END IF;
 NEW.object_id:=obj.id;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.bind_receipt_attachment() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS bind_receipt_attachment ON public.receipt_attachments;
CREATE TRIGGER bind_receipt_attachment BEFORE INSERT ON public.receipt_attachments
FOR EACH ROW EXECUTE FUNCTION private.bind_receipt_attachment();

-- Receipt uploads now originate in process-receipt. Client updates/deletes must
-- never replace evidence after it has been checked, including by limited staff.
DROP POLICY IF EXISTS receipts_server_insert_only ON storage.objects;
CREATE POLICY receipts_server_insert_only ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(bucket_id<>'receipts');
DROP POLICY IF EXISTS receipts_immutable_update ON storage.objects;
CREATE POLICY receipts_immutable_update ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated
USING(bucket_id<>'receipts') WITH CHECK(bucket_id<>'receipts');
DROP POLICY IF EXISTS receipts_immutable_delete ON storage.objects;
CREATE POLICY receipts_immutable_delete ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated
USING(bucket_id<>'receipts');
DROP POLICY IF EXISTS receipts_admin_read ON storage.objects;
CREATE POLICY receipts_admin_read ON storage.objects FOR SELECT TO authenticated USING(
 bucket_id='receipts' AND public.is_admin() AND
 (public.has_admin_permission('manage_orders') OR public.has_admin_permission('manage_wallets'))
);
DROP POLICY IF EXISTS receipts_not_banned ON storage.objects;
CREATE POLICY receipts_not_banned ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
USING(bucket_id<>'receipts' OR NOT public.is_banned());
UPDATE storage.buckets SET public=false,file_size_limit=5242880,
 allowed_mime_types=ARRAY['image/png','image/jpeg','image/webp'] WHERE id='receipts';

REVOKE INSERT,UPDATE,DELETE ON public.payment_receipts FROM authenticated;
DROP POLICY IF EXISTS receipts_admin_all ON public.payment_receipts;
DROP POLICY IF EXISTS receipts_select_own ON public.payment_receipts;
CREATE POLICY receipts_select_own ON public.payment_receipts FOR SELECT TO authenticated USING(
 NOT public.is_banned() AND (user_id=auth.uid() OR
 (public.is_admin() AND ((purpose='order' AND public.has_admin_permission('manage_orders')) OR
                        (purpose='topup' AND public.has_admin_permission('manage_wallets')))))
);

CREATE OR REPLACE FUNCTION private.assert_receipt_attachment(p_user uuid,p_path text,p_hash text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a public.receipt_attachments%ROWTYPE; obj storage.objects%ROWTYPE;
BEGIN
 IF p_path IS NULL OR length(p_path)>512 OR p_path ~ '(^|/)\.\.(/|$)' THEN RAISE EXCEPTION 'receipt_object_missing'; END IF;
 SELECT * INTO a FROM public.receipt_attachments WHERE user_id=p_user AND object_path=p_path FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'receipt_attachment_not_found'; END IF;
 IF a.receipt_hash IS DISTINCT FROM lower(btrim(p_hash)) THEN RAISE EXCEPTION 'receipt_attachment_hash_mismatch'; END IF;
 SELECT * INTO obj FROM storage.objects WHERE id=a.object_id AND bucket_id=a.bucket_id AND name=a.object_path FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'receipt_object_missing'; END IF;
 IF (obj.metadata->>'size')::bigint IS DISTINCT FROM a.image_bytes::bigint OR
    obj.metadata->>'mimetype' IS DISTINCT FROM a.mime_type THEN RAISE EXCEPTION 'receipt_object_invalid'; END IF;
 RETURN a.id;
END $$;
REVOKE ALL ON FUNCTION private.assert_receipt_attachment(uuid,text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.validate_receipt_path()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM private.assert_receipt_attachment(NEW.user_id,NEW.receipt_path,NEW.receipt_hash);
 IF TG_OP='UPDATE' AND (NEW.receipt_path IS DISTINCT FROM OLD.receipt_path OR NEW.user_id IS DISTINCT FROM OLD.user_id OR NEW.receipt_hash IS DISTINCT FROM OLD.receipt_hash) THEN
  RAISE EXCEPTION 'receipt_attachment_immutable';
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_validate_receipt_path ON public.payment_receipts;
CREATE TRIGGER trg_validate_receipt_path BEFORE INSERT OR UPDATE OF receipt_path,user_id,receipt_hash
ON public.payment_receipts FOR EACH ROW EXECUTE FUNCTION public.validate_receipt_path();

-- This is a separate settlement state. OCR matches never set it.
ALTER TABLE public.payment_receipts ADD COLUMN IF NOT EXISTS payment_verified boolean NOT NULL DEFAULT false;
ALTER TABLE public.payment_receipts ADD COLUMN IF NOT EXISTS payment_verified_at timestamptz;
ALTER TABLE public.payment_receipts ADD COLUMN IF NOT EXISTS payment_verified_by uuid REFERENCES auth.users(id);
ALTER TABLE public.payment_receipts ADD COLUMN IF NOT EXISTS payment_verification_note text;

CREATE OR REPLACE FUNCTION private.normalize_order_text(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT btrim(translate(p_value,'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'));
$$;
REVOKE ALL ON FUNCTION private.normalize_order_text(text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.assert_order_fields(p_required jsonb,p_values jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE f jsonb; k text; v text; kind text; min_len int; max_len int;
BEGIN
 IF p_values IS NULL OR jsonb_typeof(p_values)<>'object' THEN RAISE EXCEPTION 'invalid_order_fields'; END IF;
 IF p_required IS NULL OR p_required='null'::jsonb THEN RETURN; END IF;
 IF jsonb_typeof(p_required)<>'array' THEN RAISE EXCEPTION 'invalid_product_fields'; END IF;
 FOR f IN SELECT jsonb_array_elements(p_required) LOOP
  k:=f->>'key'; v:=private.normalize_order_text(p_values->>k);
  IF coalesce(k,'')='' OR jsonb_typeof(p_values->k) IS DISTINCT FROM 'string' OR coalesce(v,'')='' THEN
   RAISE EXCEPTION 'required_order_field_missing';
  END IF;
  kind:=coalesce(f->>'type','text'); min_len:=coalesce((f->>'min_length')::int,1); max_len:=coalesce((f->>'max_length')::int,500);
  IF min_len<1 OR max_len>500 OR max_len<min_len OR kind NOT IN ('text','numeric_id','email') THEN RAISE EXCEPTION 'invalid_product_fields'; END IF;
  IF char_length(v) NOT BETWEEN min_len AND max_len OR
     (kind='numeric_id' AND v !~ '^[0-9]+$') OR
     (kind='email' AND v !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN
   RAISE EXCEPTION 'invalid_order_field_value';
  END IF;
 END LOOP;
END $$;

-- Labels and normalized values are server snapshots, not client-chosen fields.
CREATE OR REPLACE FUNCTION private.snapshot_order_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE fields jsonb; f jsonb; values_out jsonb:='{}'; labels_out jsonb:='{}';
BEGIN
 SELECT required_fields INTO fields FROM public.products WHERE id=NEW.product_id;
 IF fields IS NULL THEN RETURN NEW; END IF;
 PERFORM private.assert_order_fields(fields,NEW.field_values);
 FOR f IN SELECT jsonb_array_elements(fields) LOOP
  values_out:=values_out||jsonb_build_object(f->>'key',private.normalize_order_text(NEW.field_values->>(f->>'key')));
  labels_out:=labels_out||jsonb_build_object(f->>'key',coalesce(nullif(f->>'label',''),'بيانات الطلب'));
 END LOOP;
 NEW.field_values:=values_out; NEW.field_labels:=labels_out;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.snapshot_order_fields() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS snapshot_order_fields ON public.orders;
CREATE TRIGGER snapshot_order_fields BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION private.snapshot_order_fields();

-- Do not rewrite any historical order or silently change commercial prices.
ALTER TABLE public.coupons DROP CONSTRAINT IF EXISTS coupons_discount_percent_check;
ALTER TABLE public.coupons ADD CONSTRAINT coupons_discount_percent_check CHECK(discount_percent>0 AND discount_percent<=95) NOT VALID;
ALTER TABLE public.coupons DROP CONSTRAINT IF EXISTS coupons_usage_limits_check;
ALTER TABLE public.coupons ADD CONSTRAINT coupons_usage_limits_check CHECK((max_uses IS NULL OR max_uses>=1) AND min_order_sdg>=0) NOT VALID;
ALTER TABLE public.gift_cards DROP CONSTRAINT IF EXISTS gift_cards_amount_limit_check;
ALTER TABLE public.gift_cards ADD CONSTRAINT gift_cards_amount_limit_check CHECK(amount>0 AND amount<=10000000) NOT VALID;

-- Remaining function replacements follow below, before COMMIT.
CREATE OR REPLACE FUNCTION private.validate_catalog_inputs()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE f jsonb; kind text; min_len int; max_len int;
BEGIN
 IF jsonb_typeof(NEW.required_fields)<>'array' OR jsonb_array_length(NEW.required_fields)>20 THEN RAISE EXCEPTION 'invalid_product_fields'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(NEW.required_fields) AS input_field(value) GROUP BY input_field.value->>'key' HAVING count(*)>1) THEN RAISE EXCEPTION 'duplicate_field_key'; END IF;
 FOR f IN SELECT jsonb_array_elements(NEW.required_fields) LOOP
  kind:=coalesce(f->>'type','text'); min_len:=coalesce((f->>'min_length')::int,1); max_len:=coalesce((f->>'max_length')::int,500);
  IF coalesce(f->>'key','')='' OR coalesce(btrim(f->>'label'),'')='' OR kind NOT IN ('text','numeric_id','email') OR
     min_len<1 OR max_len>500 OR min_len>max_len THEN RAISE EXCEPTION 'invalid_product_fields'; END IF;
 END LOOP;
 IF NEW.options IS NOT NULL AND jsonb_typeof(NEW.options)<>'array' THEN RAISE EXCEPTION 'invalid_product_options'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(NEW.options,'[]')) opt GROUP BY lower(btrim(opt->>'label')) HAVING count(*)>1) THEN
  RAISE EXCEPTION 'duplicate_option_label';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.validate_catalog_inputs() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS validate_catalog_inputs ON public.products;
CREATE TRIGGER validate_catalog_inputs BEFORE INSERT OR UPDATE OF required_fields,options ON public.products
FOR EACH ROW EXECUTE FUNCTION private.validate_catalog_inputs();

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

  ELSE
    -- ⛔ FIX (H1): without a server-side scan the client may NOT choose any
    -- elevated status. Everything lands in quarantine (needs_review) and no
    -- server-derived values are accepted.
    p_amount_detected := NULL;
    p_tx_ref_ocr      := NULL;
    p_ocr_confidence  := NULL;
    p_provider        := NULL;
    p_risk_flags      := ARRAY['manual_review'];
    p_ocr_data        := jsonb_build_object('decision','review','ref_verified',false,'amount_verified',false,'receipt_path',p_receipt_path,'attachment_id',v_attachment);
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

CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid, p_override_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  IF char_length(coalesce(btrim(p_override_reason),'')) NOT BETWEEN 6 AND 500 THEN RAISE EXCEPTION 'bank_review_required'; END IF;
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

  UPDATE public.payment_receipts SET payment_verified=true,payment_verified_at=now(),payment_verified_by=auth.uid(),payment_verification_note=btrim(p_override_reason)
  WHERE id=v_topup.receipt_id AND user_id=v_topup.user_id;

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
$function$;

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
    WHERE id=v_order.receipt_id AND user_id=v_order.user_id;
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

CREATE OR REPLACE FUNCTION public.save_store_settings(p_rate numeric,p_margin numeric,p_whatsapp text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE old_rate text; old_margin text;
BEGIN
 PERFORM private.assert_session_aal();
 IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_settings') THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF p_rate IS NULL OR p_rate<=0 OR p_rate::text IN ('NaN','Infinity','-Infinity')
    OR p_margin IS NULL OR p_margin<=-100 OR p_margin::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'invalid_settings'; END IF;
 IF coalesce(p_whatsapp,'')<>'' AND p_whatsapp !~ '^[0-9]{8,15}$' THEN RAISE EXCEPTION 'invalid_whatsapp'; END IF;
 SELECT value INTO old_rate FROM public.settings WHERE key='usd_to_sdg_rate' FOR UPDATE;
 SELECT value INTO old_margin FROM public.settings WHERE key='profit_margin_percent' FOR UPDATE;
 INSERT INTO public.settings(key,value) VALUES('usd_to_sdg_rate',p_rate::text),('profit_margin_percent',p_margin::text)
 ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=now();
 IF coalesce(p_whatsapp,'')<>'' THEN
  INSERT INTO public.settings(key,value) VALUES('whatsapp_number',p_whatsapp)
  ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=now();
 END IF;
 INSERT INTO public.audit_logs(admin_id,action,details)
 VALUES(auth.uid(),'تعديل الإعدادات العامة',jsonb_build_object('rate',p_rate,'margin',p_margin,'previous_rate',old_rate,'previous_margin',old_margin));
END;
$$;

COMMIT;
