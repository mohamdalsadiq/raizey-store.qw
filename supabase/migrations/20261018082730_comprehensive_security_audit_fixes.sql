-- Verified against production 0bc7427 on 2026-10-18. No customer data changes.
-- Apply with the matching frontend: MFA challenge + execute_store_action client.
CREATE SCHEMA IF NOT EXISTS private;
CREATE OR REPLACE FUNCTION private.session_has_required_aal()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
 SELECT auth.uid() IS NOT NULL AND (
   COALESCE(auth.jwt()->>'aal','aal1') = 'aal2' OR NOT EXISTS (
     SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=auth.uid() AND f.status='verified'
   )
 );
$$;
CREATE OR REPLACE FUNCTION private.assert_session_aal()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
 IF NOT private.session_has_required_aal() THEN RAISE EXCEPTION 'mfa_required'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.session_has_required_aal(), private.assert_session_aal() FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.session_has_required_aal(),private.assert_session_aal() TO authenticated,service_role;

-- Restrictive policy composes with ownership/permission policies; it never grants rows.
DO $$ DECLARE t text; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  EXECUTE format('DROP POLICY IF EXISTS require_enrolled_mfa ON public.%I',t);
  EXECUTE format('CREATE POLICY require_enrolled_mfa ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (private.session_has_required_aal()) WITH CHECK (private.session_has_required_aal())',t);
 END LOOP;
END $$;
DROP POLICY IF EXISTS require_enrolled_mfa ON storage.objects;
CREATE POLICY require_enrolled_mfa ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
USING (private.session_has_required_aal()) WITH CHECK (private.session_has_required_aal());

-- Public clients may edit only personal contact/display fields. Staff/ban changes use guarded RPCs.
REVOKE INSERT,UPDATE,DELETE ON public.profiles FROM authenticated;
GRANT UPDATE(full_name,whatsapp_number,player_ids,avatar_url) ON public.profiles TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.store_settings FROM authenticated;

DROP POLICY IF EXISTS gift_cards_select_own ON public.gift_cards;
CREATE POLICY gift_cards_select_own ON public.gift_cards FOR SELECT TO authenticated
USING (redeemed_by=auth.uid() OR (public.is_admin() AND public.has_admin_permission('manage_gift_cards')));
DROP POLICY IF EXISTS audit_logs_select_admin ON public.audit_logs;
CREATE POLICY audit_logs_select_admin ON public.audit_logs FOR SELECT TO authenticated
USING (public.is_admin() AND public.has_admin_permission('view_audit_logs'));

-- For direct inserts the database supplies the actor and timestamp. Trusted RPC inserts retain their source.
CREATE OR REPLACE FUNCTION private.bind_audit_actor()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
 IF current_user='authenticated' THEN
  NEW.admin_id:=auth.uid(); NEW.created_at:=statement_timestamp();
  IF TG_TABLE_NAME='audit_logs' THEN NEW.source:='admin_action'; END IF;
 END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.bind_audit_actor() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS bind_audit_actor ON public.audit_logs;
CREATE TRIGGER bind_audit_actor BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION private.bind_audit_actor();
DROP TRIGGER IF EXISTS bind_audit_actor ON public.admin_audit_logs;
CREATE TRIGGER bind_audit_actor BEFORE INSERT ON public.admin_audit_logs FOR EACH ROW EXECUTE FUNCTION private.bind_audit_actor();
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

  SELECT private.session_has_required_aal() AND EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND COALESCE(is_banned, false) = false
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT private.session_has_required_aal() AND EXISTS (
    SELECT 1 FROM admin_permissions ap
    JOIN profiles p ON p.id = ap.profile_id
    WHERE ap.profile_id = auth.uid()
      AND ap.is_super_admin = true
      AND p.role = 'admin'
      AND COALESCE(p.is_banned, false) = false
  );
$function$;

CREATE OR REPLACE FUNCTION public.has_admin_permission(permission_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                      SELECT public.is_admin() AND COALESCE (
                                                                                                                                                                                                                                                          (
                                                                                                                                                                                                                                                                SELECT
                                                                                                                                                                                                                                                                        ap.is_super_admin OR
                                                                                                                                                                                                                                                                                CASE permission_key
                                                                                                                                                                                                                                                                                          WHEN 'manage_orders' THEN ap.can_manage_orders
                                                                                                                                                                                                                                                                                                    WHEN 'manage_wallets' THEN ap.can_manage_wallets
                                                                                                                                                                                                                                                                                                              WHEN 'manage_products' THEN ap.can_manage_products
                                                                                                                                                                                                                                                                                                                        WHEN 'manage_settings' THEN ap.can_manage_settings
                                                                                                                                                                                                                                                                                                                                  WHEN 'manage_maintenance' THEN ap.can_manage_maintenance
                                                                                                                                                                                                                                                                                                                                            WHEN 'manage_admins' THEN ap.can_manage_admins
                                                                                                                                                                                                                                                                                                                                                      WHEN 'manage_coupons' THEN ap.can_manage_coupons
                                                                                                                                                                                                                                                                                                                                                                WHEN 'manage_gift_cards' THEN ap.can_manage_gift_cards
                                                                                                                                                                                                                                                                                                                                                                          WHEN 'view_audit_logs' THEN ap.can_view_audit_logs
                                                                                                                                                                                                                                                                                                                                                                                    ELSE false
                                                                                                                                                                                                                                                                                                                                                                                            END
                                                                                                                                                                                                                                                                                                                                                                                                  FROM public.admin_permissions ap
                                                                                                                                                                                                                                                                                                                                                                                                        WHERE ap.profile_id = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                              LIMIT 1
                                                                                                                                                                                                                                                                                                                                                                                                                  ),
                                                                                                                                                                                                                                                                                                                                                                                                                      false
                                                                                                                                                                                                                                                                                                                                                                                                                        );
$function$;

CREATE OR REPLACE FUNCTION public.create_wallet_orders_bulk(p_items jsonb, p_coupon_code text DEFAULT NULL::text)
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
  v_balance      numeric;
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
  i              int;
  v_new_balance  numeric;
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

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

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

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  -- Preserve the existing rounded basket charge. Allocate it to orders to the cent.
  v_total := ROUND(v_total * (1.0-v_discount_pct/100.0));
  IF v_total <= 0 THEN v_total:=1; END IF;

  SELECT w.balance INTO v_balance FROM wallets w WHERE w.user_id = v_user_id FOR UPDATE;
  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_balance < v_total THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets w SET balance = w.balance - v_total, updated_at = now()
  WHERE w.user_id = v_user_id
  RETURNING w.balance INTO v_new_balance;

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
        payment_type, status, coupon_id, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        v_alloc_amount,
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'wallet', 'in_progress', v_coupon_id, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, details)
  VALUES (v_user_id, v_total, 'debit', v_new_balance, 'wallet_order_bulk', jsonb_build_object('order_ids', v_ids));

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;

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

  -- ── حجز الإيصال داخل نفس المعاملة (المبلغ المتوقع يُحسب هنا) ──
  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    v_method_id,
    v_total,
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

CREATE OR REPLACE FUNCTION public.redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text DEFAULT NULL::text)
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
  v_norm         text;
  v_code         RECORD;
  v_updated      uuid;
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
  v_last_id      uuid;
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

  -- ── قفل الرمز أولاً ──
  v_norm := upper(btrim(coalesce(p_code, '')));
  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  FOR UPDATE;

  IF NOT FOUND                                             THEN RAISE EXCEPTION 'not_found';     END IF;
  IF v_code.status = 'cancelled'                            THEN RAISE EXCEPTION 'cancelled';     END IF;
  IF v_code.status <> 'active' OR v_code.used_by IS NOT NULL THEN RAISE EXCEPTION 'already_used'; END IF;
  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN RAISE EXCEPTION 'expired'; END IF;
  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id   THEN RAISE EXCEPTION 'not_your_code'; END IF;

  -- ── حساب الأسعار من القاعدة فقط ──
  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

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

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  -- Preserve the existing rounded basket charge. Allocate it to orders to the cent.
  v_total := ROUND(v_total * (1.0-v_discount_pct/100.0));
  IF v_total <= 0 THEN v_total:=1; END IF;

  -- ── قيمة الرمز يجب أن تغطي الإجمالي (تحقق في السيرفر لا المتصفح) ──
  IF COALESCE(v_code.amount, 0) < v_total THEN
    RAISE EXCEPTION 'amount_too_low';
  END IF;

  -- ── إدخال الطلبات ──
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
        payment_type, status, coupon_id, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        v_alloc_amount,
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'code', 'in_progress', v_coupon_id, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids     := array_append(v_ids, v_order_id);
      v_last_id := v_order_id;
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  -- ── استهلاك الرمز شرطياً: الحاجز الحقيقي ضد الاستخدام المزدوج ──
  UPDATE public.payment_codes pc
  SET status = 'used', used_by = v_user_id, used_at = now(), order_id = v_last_id
  WHERE pc.id = v_code.id AND pc.status = 'active' AND pc.used_by IS NULL
  RETURNING pc.id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'already_used';
  END IF;

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_code_orders_bulk(p_items jsonb, p_code text, p_coupon_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_codeRow      public.payment_codes;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF EXISTS (SELECT 1 FROM store_settings WHERE store_settings.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN RAISE EXCEPTION 'cart_too_large'; END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;

  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

    SELECT * INTO v_product FROM products
    WHERE products.id = (v_item->>'product_id')::uuid AND products.is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'product_not_found'; END IF;

    PERFORM private.assert_order_fields(v_product.required_fields,COALESCE(v_item->'field_values','{}'::jsonb));
    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(trim(v_item->>'option_id'), '') = '' THEN RAISE EXCEPTION 'option_required'; END IF;
      SELECT opt INTO v_option FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id') LIMIT 1;
      IF v_option IS NULL THEN RAISE EXCEPTION 'option_not_found'; END IF;
      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;

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

  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent INTO v_coupon_id, v_discount_pct
    FROM public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  -- Preserve the existing rounded basket charge. Allocate it to orders to the cent.
  v_total := ROUND(v_total * (1.0-v_discount_pct/100.0));
  IF v_total <= 0 THEN v_total:=1; END IF;

  SELECT * INTO v_codeRow FROM public.payment_codes
  WHERE upper(replace(code, ' ', '')) = upper(replace(trim(p_code), ' ', ''))
  FOR UPDATE;

  IF v_codeRow.id IS NULL THEN RAISE EXCEPTION 'code_not_found'; END IF;
  IF v_codeRow.status <> 'active' THEN RAISE EXCEPTION 'code_not_active'; END IF;
  IF v_codeRow.expires_at IS NOT NULL AND v_codeRow.expires_at < now() THEN RAISE EXCEPTION 'code_expired'; END IF;
  IF v_codeRow.user_id IS NOT NULL AND v_codeRow.user_id <> v_user_id THEN RAISE EXCEPTION 'code_not_yours'; END IF;
  IF v_codeRow.amount < v_total THEN RAISE EXCEPTION 'code_amount_too_low'; END IF;

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
        payment_type, status, coupon_id, review_reason, review_severity
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        v_alloc_amount,
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'code', 'in_progress', v_coupon_id,
        'دفع برمز إداري: ' || v_codeRow.code, 'info'
      )
      RETURNING orders.id INTO v_order_id;
      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  UPDATE public.payment_codes
  SET status = 'used', used_by = v_user_id, used_at = now(), order_id = v_ids[1]
  WHERE id = v_codeRow.id;

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.set_store_maintenance(p_enabled boolean, p_message text DEFAULT NULL::text)
 RETURNS store_settings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              v_row public.store_settings;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                v_message text := COALESCE(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    NULLIF(trim(p_message), ''),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'الموقع قيد الصيانة والتحديث حالياً، وسنسعد بخدمتكم مجدداً في أقرب وقت ممكن.'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          );
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            IF auth.uid() IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_maintenance') THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        RAISE EXCEPTION 'MISSING_PERMISSION:manage_maintenance';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            UPDATE public.store_settings
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              SET maintenance_mode = COALESCE(p_enabled, false),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    maintenance_message = v_message,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          updated_by = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHERE singleton_key = true
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              RETURNING * INTO v_row;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                PERFORM public.append_admin_audit_log(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    'set_store_maintenance',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'store_settings',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            v_row.id::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                jsonb_build_object(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      'maintenance_mode', COALESCE(p_enabled, false),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            'maintenance_message', v_message
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  );

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    RETURN v_row;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    END;
$function$;

CREATE OR REPLACE FUNCTION public.set_store_exchange_rate(p_rate numeric)
 RETURNS store_settings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            v_row public.store_settings;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              IF auth.uid() IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_settings') THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          RAISE EXCEPTION 'MISSING_PERMISSION:manage_settings';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              IF p_rate IS NULL OR p_rate <= 0 THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  RAISE EXCEPTION 'INVALID_EXCHANGE_RATE';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      UPDATE public.store_settings
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        SET usd_to_sdg_rate = p_rate,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              updated_by = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHERE singleton_key = true
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  RETURNING * INTO v_row;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    PERFORM public.append_admin_audit_log(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'set_store_exchange_rate',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            'store_settings',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                v_row.id::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    jsonb_build_object('usd_to_sdg_rate', p_rate)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      );

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        RETURN v_row;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        END;
$function$;


-- Existing service-only setter grants are retained; the current UI uses save_store_settings.
CREATE TABLE IF NOT EXISTS private.store_action_requests (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 request_id uuid NOT NULL, action text NOT NULL, input_hash text NOT NULL,
 result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,request_id)
);
ALTER TABLE private.store_action_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.store_action_requests FROM PUBLIC,anon,authenticated;

-- The limiter is outside the exception subtransaction. Failed attempts now commit their counter.
CREATE OR REPLACE FUNCTION public.execute_store_action(p_action text,p_payload jsonb DEFAULT '{}'::jsonb,p_request_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
 v_uid uuid:=auth.uid(); v_rate record; v_data jsonb; v_cached private.store_action_requests%ROWTYPE;
 v_hash text; v_limit integer:=30; v_window integer:=60; v_write boolean;
BEGIN
 PERFORM private.assert_session_aal();
 IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('create_wallet_orders_bulk','create_bank_orders_bulk','redeem_payment_code_order',
                     'create_wallet_topup_from_receipt','redeem_gift_card','validate_coupon') THEN
  RETURN jsonb_build_object('ok',false,'error','unsupported_action');
 END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>262144 THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_action_payload');
 END IF;
 v_write:=p_action<>'validate_coupon';
 IF v_write AND p_request_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','request_id_required'); END IF;
 IF v_write THEN
  v_hash:=encode(sha256(convert_to(p_action||p_payload::text,'UTF8')),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(v_uid::text||p_request_id::text,0));
  SELECT * INTO v_cached FROM private.store_action_requests WHERE user_id=v_uid AND request_id=p_request_id;
  IF FOUND THEN
   IF v_cached.input_hash<>v_hash THEN RETURN jsonb_build_object('ok',false,'error','idempotency_conflict'); END IF;
   RETURN jsonb_build_object('ok',true,'data',v_cached.result,'replayed',true);
  END IF;
 END IF;
 IF p_action='redeem_gift_card' THEN v_limit:=10;v_window:=3600;
 ELSIF p_action='validate_coupon' THEN v_limit:=60;v_window:=3600;
 END IF;
 SELECT * INTO v_rate FROM public.consume_chat_rate_limit('action:'||p_action||':'||v_uid::text,v_limit,v_window);
 IF NOT v_rate.allowed THEN RETURN jsonb_build_object('ok',false,'error','rate_limited','retry_after',v_rate.retry_after_seconds); END IF;
 BEGIN
  CASE p_action
   WHEN 'create_wallet_orders_bulk' THEN
    SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) INTO v_data
    FROM public.create_wallet_orders_bulk(p_payload->'p_items',p_payload->>'p_coupon_code') r;
   WHEN 'create_bank_orders_bulk' THEN
    SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) INTO v_data
    FROM public.create_bank_orders_bulk(p_payload->'p_items',p_payload->'p_receipt',p_payload->>'p_coupon_code') r;
   WHEN 'redeem_payment_code_order' THEN
    SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) INTO v_data
    FROM public.redeem_payment_code_order(p_payload->>'p_code',p_payload->'p_items',p_payload->>'p_coupon_code') r;
   WHEN 'redeem_gift_card' THEN
    SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) INTO v_data FROM public.redeem_gift_card(p_payload->>'p_code') r;
   WHEN 'validate_coupon' THEN
    SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) INTO v_data
    FROM public.validate_coupon(p_payload->>'p_code',nullif(p_payload->>'p_order_total','')::numeric) r;
   WHEN 'create_wallet_topup_from_receipt' THEN
    SELECT to_jsonb(public.create_wallet_topup_from_receipt(
     (p_payload->>'p_amount')::numeric,(p_payload->>'p_payment_method_id')::uuid,p_payload->>'p_receipt_url',
     p_payload->>'p_tx_ref',p_payload->>'p_receipt_hash',p_payload->>'p_receipt_path',p_payload->>'p_provider',
     nullif(p_payload->>'p_amount_detected','')::numeric,p_payload->>'p_tx_ref_ocr',coalesce(p_payload->>'p_ocr_status','needs_review'),
     nullif(p_payload->>'p_ocr_confidence','')::numeric,
     CASE WHEN jsonb_typeof(p_payload->'p_risk_flags')='array' THEN ARRAY(SELECT jsonb_array_elements_text(p_payload->'p_risk_flags')) ELSE '{}'::text[] END,
     coalesce(p_payload->'p_ocr_data','{}'::jsonb))) INTO v_data;
  END CASE;
 EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok',false,'error',left(SQLERRM,300));
 END;
 IF v_write THEN
  INSERT INTO private.store_action_requests(user_id,request_id,action,input_hash,result)
   VALUES(v_uid,p_request_id,p_action,v_hash,v_data);
 END IF;
 RETURN jsonb_build_object('ok',true,'data',v_data);
END;
$$;
REVOKE ALL ON FUNCTION public.execute_store_action(text,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.execute_store_action(text,jsonb,uuid) TO authenticated,service_role;
REVOKE EXECUTE ON FUNCTION public.create_wallet_orders_bulk(p_items jsonb, p_coupon_code text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.create_wallet_topup_from_receipt(p_amount numeric, p_payment_method_id uuid, p_receipt_url text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_gift_card(p_code text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_coupon(p_code text, p_order_total numeric) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.use_coupon_atomic(p_code text, p_order_total numeric) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_payment_method_id uuid, p_amount_expected numeric, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
 RETURNS TABLE(available boolean, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_norm    text;
  v_rate    RECORD;
BEGIN
  PERFORM private.assert_session_aal();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  -- حد معدل موحّد: يمنع استخدام الدالة كأداة تعداد مكثّفة
  SELECT * INTO v_rate
  FROM public.consume_chat_rate_limit('txref:' || v_user_id::text, 30, 3600);
  IF NOT v_rate.allowed THEN
    RETURN QUERY SELECT false, 'rate_limited'::text;
    RETURN;
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RETURN QUERY SELECT false, 'invalid_tx_ref'::text;
    RETURN;
  END IF;

  -- نطاق الفحص: صفوف المستخدم نفسه فقط.
  -- الحماية الحقيقية من إعادة استخدام أرقام الآخرين تبقى قيدًا فريدًا على القاعدة.
  IF EXISTS (
       SELECT 1 FROM public.payment_receipts r
       WHERE r.tx_ref_norm = v_norm AND r.user_id = v_user_id
     )
     OR EXISTS (
       SELECT 1 FROM public.orders o
       WHERE public.normalize_tx_ref(o.transaction_reference) = v_norm
         AND o.user_id = v_user_id
     )
     OR EXISTS (
       SELECT 1 FROM public.wallet_topups t
       WHERE public.normalize_tx_ref(t.transaction_reference) = v_norm
         AND t.user_id = v_user_id
     ) THEN
    RETURN QUERY SELECT false, 'duplicate_transaction_ref'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'available'::text;
END
$function$;

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
  PERFORM private.assert_session_aal();
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
  -- أكواد الدفع 13 خانة (RZY-XXXX-XXXX)؛ أي مدخل أقصر مرفوض قبل أي بحث
  IF length(v_norm) < 10 THEN
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

CREATE OR REPLACE FUNCTION public.cancel_my_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_order   public.orders%ROWTYPE;
BEGIN
  PERFORM private.assert_session_aal();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'invalid_order';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.user_id <> v_user_id THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  -- wallet orders are charged up-front and move to in_progress immediately;
  -- refunding one is an admin decision (admin_update_order_status → cancel).
  IF v_order.payment_type = 'wallet' THEN
    RAISE EXCEPTION 'wallet_order_requires_support';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.attach_secondary_receipt(p_parent_tx_ref text, p_order_id uuid, p_receipt jsonb)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_claim   RECORD;
BEGIN
  PERFORM private.assert_session_aal();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  -- الطلب يجب أن يكون لهذا المستخدم
  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.id = p_order_id AND o.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'receipt_not_owned';
  END IF;

  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    NULLIF(p_receipt->>'payment_method_id', '')::uuid,
    NULLIF(p_receipt->>'expected_amount', '')::numeric,
    NULLIF(p_receipt->>'amount_detected', '')::numeric,
    NULLIF(p_receipt->>'tx_ref_ocr', ''),
    COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_admin_check'),
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
       || jsonb_build_object(
            'split_parent_tx_ref', p_parent_tx_ref,
            'split_parent_order',  p_order_id,
            'is_secondary',        true)
  ) c;

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  -- الإشعار الثاني لا يُعتبر مقبولاً تلقائياً أبداً
  UPDATE payment_receipts pr
  SET ocr_status = 'needs_admin_check'
  WHERE pr.id = v_claim.id;

  RETURN QUERY SELECT v_claim.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.log_receipt_fraud_attempt(p_entered_reference text, p_reason text, p_provider text DEFAULT NULL::text, p_ocr_excerpt text DEFAULT NULL::text, p_order_amount numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_rate    RECORD;
BEGIN
  PERFORM private.assert_session_aal();
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
$function$;

CREATE OR REPLACE FUNCTION public.report_fraud_alert(p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id   uuid;
  v_rate RECORD;
BEGIN
  PERFORM private.assert_session_aal();
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
$function$;

CREATE OR REPLACE FUNCTION public.process_referral_commission(p_user_id uuid, p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE
  v_referrer_id uuid;
  v_order       RECORD;
  v_commission  numeric;
  v_updated     uuid;
  v_new_balance numeric;
BEGIN
  PERFORM private.assert_session_aal();
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  SELECT * INTO v_order FROM orders
  WHERE id = p_order_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF COALESCE(v_order.referral_commission_paid, false) = true THEN RETURN; END IF;
  IF v_order.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  SELECT referred_by INTO v_referrer_id FROM profiles WHERE id = p_user_id;
  IF v_referrer_id IS NULL OR v_referrer_id = p_user_id THEN RETURN; END IF;

  UPDATE orders SET referral_commission_paid = true
  WHERE id = p_order_id AND COALESCE(referral_commission_paid, false) = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN RETURN; END IF;

  v_commission := ROUND(COALESCE(v_order.price_sdg_snapshot, 0) * 0.02, 2);
  IF v_commission <= 0 THEN RETURN; END IF;

  INSERT INTO wallets (user_id, balance) VALUES (v_referrer_id, v_commission)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = wallets.balance + v_commission, updated_at = now()
  RETURNING wallets.balance INTO v_new_balance;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_referrer_id, v_commission, 'credit', v_new_balance, 'referral_commission', p_order_id, auth.uid());
END;
$function$;

ALTER FUNCTION public.icon_image_url_ok(text) SET search_path='';
ALTER FUNCTION public.icon_fields_validate(text,text,text) SET search_path='';
ALTER FUNCTION public.banners_validate_image_url(text) SET search_path='';

CREATE OR REPLACE FUNCTION public.get_session_security_context()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT jsonb_build_object(
  'allowed',auth.uid() IS NOT NULL AND private.session_has_required_aal() AND NOT public.is_banned(),
  'requires_mfa',auth.uid() IS NOT NULL AND NOT private.session_has_required_aal()
 );
$$;
REVOKE ALL ON FUNCTION public.get_session_security_context() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_session_security_context() TO authenticated,service_role;

-- Validate the complete form before any write; update prices + contact + audit atomically.
CREATE OR REPLACE FUNCTION public.save_store_settings(p_rate numeric,p_margin numeric,p_whatsapp text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM private.assert_session_aal();
 IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_settings') THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF p_rate IS NULL OR p_rate<=0 OR p_rate::text IN ('NaN','Infinity','-Infinity')
    OR p_margin IS NULL OR p_margin<=-100 OR p_margin::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'invalid_settings'; END IF;
 IF coalesce(p_whatsapp,'')<>'' AND p_whatsapp !~ '^[0-9]{8,15}$' THEN RAISE EXCEPTION 'invalid_whatsapp'; END IF;
 INSERT INTO public.settings(key,value) VALUES('usd_to_sdg_rate',p_rate::text),('profit_margin_percent',p_margin::text)
 ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=now();
 IF coalesce(p_whatsapp,'')<>'' THEN
  INSERT INTO public.settings(key,value) VALUES('whatsapp_number',p_whatsapp)
  ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=now();
 END IF;
 INSERT INTO public.audit_logs(admin_id,action,details)
 VALUES(auth.uid(),'تعديل الإعدادات العامة',jsonb_build_object('rate',p_rate,'margin',p_margin));
END;
$$;
REVOKE ALL ON FUNCTION public.save_store_settings(numeric,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_store_settings(numeric,numeric,text) TO authenticated,service_role;

-- Cancel and record the administrative action in the same database transaction.
CREATE OR REPLACE FUNCTION public.admin_cancel_payment_code(p_code_id uuid)
RETURNS public.payment_codes LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_code public.payment_codes;
BEGIN
 PERFORM private.assert_session_aal();
 IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_settings') THEN RAISE EXCEPTION 'access_denied'; END IF;
 UPDATE public.payment_codes SET status='cancelled',updated_at=now()
 WHERE id=p_code_id AND status='active' RETURNING * INTO v_code;
 IF NOT FOUND THEN RAISE EXCEPTION 'code_not_active'; END IF;
 PERFORM public.append_admin_audit_log('cancel_payment_code','payment_codes',p_code_id::text,'{}'::jsonb);
 RETURN v_code;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cancel_payment_code(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_payment_code(uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admin_refund_wallet(p_order_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  IF v_order.price_sdg_snapshot IS NULL OR v_order.price_sdg_snapshot < 0 THEN
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

  -- A zero-cent allocation has nothing to credit; never create a zero/negative ledger entry.
  IF v_order.price_sdg_snapshot=0 THEN
    UPDATE public.orders SET refunded=true WHERE id=p_order_id;
    INSERT INTO public.audit_logs(admin_id,action,details,source)
    VALUES(v_admin,'admin_refund_wallet',jsonb_build_object('order_id',p_order_id,'amount',0,'reason',p_reason),'admin_action');
    RETURN;
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
$function$;


CREATE OR REPLACE FUNCTION private.assert_order_fields(p_required jsonb,p_values jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE f jsonb; k text;
BEGIN
 IF p_values IS NULL OR jsonb_typeof(p_values)<>'object' THEN RAISE EXCEPTION 'invalid_order_fields'; END IF;
 IF p_required IS NULL OR p_required='null'::jsonb THEN RETURN; END IF;
 IF jsonb_typeof(p_required)<>'array' THEN RAISE EXCEPTION 'invalid_product_fields'; END IF;
 FOR f IN SELECT jsonb_array_elements(p_required) LOOP
  k:=f->>'key';
  IF coalesce(k,'')='' OR jsonb_typeof(p_values->k) IS DISTINCT FROM 'string'
     OR coalesce(btrim(p_values->>k),'')='' OR char_length(p_values->>k)>500 THEN
    RAISE EXCEPTION 'required_order_field_missing';
  END IF;
 END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION private.assert_order_fields(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
