-- P3-SEC-001: gift card abuse controls — brute-force protection.
--
-- redeem_gift_card already has: auth, banned check, row lock, double-redeem guard,
-- expiry, amount validation, atomicity. Missing: rate limiting on attempts.
--
-- This adds: max 10 redemption attempts per hour per user, via the existing
-- consume_chat_rate_limit RPC (private.chat_rate_limits). Fails closed.
--
-- SAFE: additive check at function start; no schema change.
-- ROLLBACK: drop the rate-limit block.
-- APPLIED LIVE: 2026-10-08.

CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code text)
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
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;

  -- P3-SEC-001: brute-force protection — 10 attempts/hour per user
  SELECT * INTO v_rate FROM public.consume_chat_rate_limit(
    'giftcard:' || v_user_id::text, 10, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'giftcard_rate_limited';
  END IF;

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

COMMENT ON FUNCTION public.redeem_gift_card(text) IS
  'P3-SEC-001: + brute-force protection (10/hour/user).';
