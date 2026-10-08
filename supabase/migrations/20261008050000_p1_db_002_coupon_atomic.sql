-- P1-DB-002: atomic coupon path — canonize + remove dead non-atomic leftover.
--
-- Background: the coupon claim already runs through use_coupon_atomic (SELECT ..
-- FOR UPDATE with all validity checks, unique redemption insert, clamped discount).
-- This migration:
--   1. DROPs increment_coupon_usage(uuid) — a dead, UNAUTHENTICATED blind
--      uses_count incrementer (no auth, no validation, no user binding).
--      Nothing in the repo calls it; leaving it is a loaded footgun.
--   2. Re-pins use_coupon_atomic byte-identical as the canonical definition.
--
-- INVARIANT: validate + consume in ONE transaction; the discount applied is
-- always server-computed, never client-supplied.
--
-- SAFE: drop of dead code + identical re-apply. ROLLBACK: n/a.

DROP FUNCTION IF EXISTS public.increment_coupon_usage(uuid);

CREATE OR REPLACE FUNCTION public.use_coupon_atomic(
  p_code text,
  p_order_total numeric DEFAULT NULL
)
RETURNS TABLE(coupon_id uuid, discount_percent numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
  v_pct     numeric;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT c.* INTO v_coupon FROM coupons c
  WHERE upper(c.code) = upper(btrim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF p_order_total IS NOT NULL AND COALESCE(v_coupon.min_order_sdg, 0) > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  BEGIN
    INSERT INTO coupon_redemptions (coupon_id, user_id) VALUES (v_coupon.id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'coupon_already_used';
  END;

  UPDATE coupons c SET uses_count = COALESCE(c.uses_count, 0) + 1
  WHERE c.id = v_coupon.id;

  v_pct := LEAST(GREATEST(COALESCE(v_coupon.discount_percent, 0), 0), 95);
  RETURN QUERY SELECT v_coupon.id, v_pct;
END;
$$;

COMMENT ON FUNCTION public.use_coupon_atomic(text, numeric) IS
  'P1-DB-002 canonical atomic coupon claim. INVARIANT: validate + consume in one transaction; discount is server-computed.';
