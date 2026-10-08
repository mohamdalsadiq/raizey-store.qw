-- P1-FIN-002: wallet ledger consistency — every balance movement writes wallet_transactions.
--
-- Background: wallet_transactions existed but all 7 wallet-touching functions
-- bypassed it, leaving no auditable money trail.
--
-- Change: each function now captures the post-movement balance (RETURNING) and
-- inserts one ledger row (user_id, amount, direction, balance_after, source,
-- reference_id/details, performed_by) in the SAME transaction.
-- Sources: topup, wallet_order, wallet_order_bulk, referral_commission,
--           gift_card, loyalty_points, admin_refund.
--
-- SAFE: additive INSERTs only; no logic changes. ROLLBACK: re-apply prior bodies.

CREATE OR REPLACE FUNCTION public.admin_confirm_topup(
  p_topup_id uuid, p_override_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$

DECLARE
  v_topup public.wallet_topups%ROWTYPE;
  v_detected numeric;
  v_diff numeric;
  v_tolerance numeric;
  v_overrode boolean := false;
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

  IF v_detected IS NOT NULL THEN
    v_diff := abs(v_detected - v_topup.amount);
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
END;
$$;


CREATE OR REPLACE FUNCTION public.create_wallet_order(
  p_product_id uuid, p_field_values jsonb DEFAULT '{}'::jsonb, p_field_labels jsonb DEFAULT '{}'::jsonb, p_coupon_code text DEFAULT NULL, p_selected_option_id text DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id          uuid := auth.uid();
  v_product          RECORD;
  v_wallet_balance   numeric;
  v_rate             numeric;
  v_margin           numeric;
  v_price_sdg        numeric;
  v_option           jsonb := NULL;
  v_option_price_usd numeric;
  v_coupon_id        uuid;
  v_discount_pct     numeric := 0;
  v_order_id         uuid;
  v_name_snapshot    text;
  v_new_balance      numeric;
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

  SELECT p.* INTO v_product FROM products p
  WHERE p.id = p_product_id AND p.is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
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

  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF p_selected_option_id IS NULL OR btrim(p_selected_option_id) = '' THEN
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
    v_price_sdg     := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
  ELSE
    v_price_sdg     := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_price_sdg) uc;
    v_price_sdg := v_price_sdg * (1.0 - LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95) / 100.0);
  END IF;

  v_price_sdg := ROUND(v_price_sdg);
  IF v_price_sdg <= 0 THEN
    v_price_sdg := 1;
  END IF;

  SELECT w.balance INTO v_wallet_balance
  FROM wallets w WHERE w.user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets w SET balance = w.balance - v_price_sdg, updated_at = now()
  WHERE w.user_id = v_user_id
  RETURNING w.balance INTO v_new_balance;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id, refunded
  ) VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'::jsonb),
    COALESCE(p_field_labels, '{}'::jsonb), v_option,
    'wallet', 'in_progress', v_coupon_id, false
  )
  RETURNING orders.id INTO v_order_id;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id)
  VALUES (v_user_id, v_price_sdg, 'debit', v_new_balance, 'wallet_order', v_order_id);

  RETURN QUERY SELECT v_order_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_wallet_orders_bulk(
  p_items jsonb, p_coupon_code text DEFAULT NULL
)
RETURNS TABLE(id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
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

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

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

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
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
$$;


CREATE OR REPLACE FUNCTION public.process_referral_commission(
  p_user_id uuid, p_order_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$

DECLARE
  v_referrer_id uuid;
  v_order       RECORD;
  v_commission  numeric;
  v_updated     uuid;
  v_new_balance numeric;
BEGIN
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
$$;


CREATE OR REPLACE FUNCTION public.redeem_gift_card(
  p_code text
)
RETURNS TABLE(amount numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$

DECLARE
  v_card    RECORD;
  v_user_id uuid := auth.uid();
  v_updated uuid;
  v_new_balance numeric;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF public.normalize_tx_ref(p_code) IS NULL THEN RAISE EXCEPTION 'giftcard_invalid'; END IF;

  SELECT * INTO v_card FROM gift_cards WHERE upper(gift_cards.code) = upper(trim(p_code)) FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_card.is_redeemed, false) = true THEN
    RAISE EXCEPTION 'giftcard_invalid';
  END IF;

  IF v_card.expires_at IS NOT NULL AND v_card.expires_at <= now() THEN
    RAISE EXCEPTION 'giftcard_expired';
  END IF;

  IF COALESCE(v_card.amount, 0) <= 0 THEN RAISE EXCEPTION 'giftcard_invalid'; END IF;

  UPDATE gift_cards
  SET is_redeemed = true, redeemed_by = v_user_id, redeemed_at = now()
  WHERE gift_cards.id = v_card.id AND COALESCE(gift_cards.is_redeemed, false) = false
  RETURNING gift_cards.id INTO v_updated;

  IF v_updated IS NULL THEN RAISE EXCEPTION 'giftcard_invalid'; END IF;

  INSERT INTO wallets (user_id, balance)
  VALUES (v_user_id, v_card.amount)
  ON CONFLICT (user_id) DO UPDATE SET balance = wallets.balance + v_card.amount, updated_at = now()
  RETURNING wallets.balance INTO v_new_balance;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id)
  VALUES (v_user_id, v_card.amount, 'credit', v_new_balance, 'gift_card', v_card.id);

  RETURN QUERY SELECT v_card.amount;
END;
$$;


CREATE OR REPLACE FUNCTION public.redeem_loyalty_points(
  p_points integer
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$

declare
  v_user_id uuid := auth.uid();
  v_balance integer;
  v_value_rate numeric;
  v_credit numeric;
  v_new_balance numeric;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'invalid_points';
  end if;

  select loyalty_points into v_balance from public.profiles where id = v_user_id for update;

  if v_balance is null or v_balance < p_points then
    raise exception 'insufficient_points';
  end if;

  select coalesce(value::numeric, 0) into v_value_rate from public.settings where key = 'loyalty_point_value_sdg';
  v_credit := p_points * coalesce(v_value_rate, 0);

  update public.profiles set loyalty_points = loyalty_points - p_points where id = v_user_id;
  update public.wallets set balance = balance + v_credit, updated_at = now() where user_id = v_user_id
  returning balance into v_new_balance;

  insert into public.wallet_transactions (user_id, amount, direction, balance_after, source, details)
  values (v_user_id, v_credit, 'credit', v_new_balance, 'loyalty_points', jsonb_build_object('points', p_points));

  insert into public.notifications (user_id, title, message, type)
  values (v_user_id, 'استبدال نقاط الولاء', 'تم تحويل ' || p_points || ' نقطة إلى ' || v_credit || ' جنيه في محفظتك.', 'loyalty');

  return v_credit;
end;
$$;


CREATE OR REPLACE FUNCTION public.admin_refund_wallet(
  p_user_id uuid, p_amount numeric, p_order_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_balance numeric;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  UPDATE public.wallets
  SET balance = balance + p_amount, updated_at = now()
  WHERE user_id = p_user_id
  RETURNING balance INTO v_new_balance;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found for user %', p_user_id;
  END IF;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (p_user_id, p_amount, 'credit', v_new_balance, 'admin_refund', p_order_id, auth.uid());
END;
$$;

