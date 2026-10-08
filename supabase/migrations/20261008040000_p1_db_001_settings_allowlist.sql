-- P1-DB-001: public settings allowlist.
--
-- Background: settings_select allowed anon+authenticated SELECT on ALL keys,
-- exposing internal business values (loyalty_point_value_sdg,
-- loyalty_points_per_sdg, milestone10_bonus/threshold, milestone25_bonus/threshold,
-- referral_bonus_amount, profit internals).
--
-- Fix: anon/authenticated can read ONLY the keys the public storefront actually
-- uses (verified in repo 2026-10-08):
--   usd_to_sdg_rate, profit_margin_percent  -> assets/js/supabase-client.js getExchangeRate()
--   referral_signup_discount_percent         -> referrals.html
-- All other keys remain admin-only via the settings_admin policy.
-- No server-side function reads settings directly (verified), so nothing breaks.
--
-- SAFE: purely restrictive policy change. ROLLBACK: restore USING (true).

DROP POLICY IF EXISTS settings_select ON public.settings;

CREATE POLICY settings_select ON public.settings
  FOR SELECT TO anon, authenticated
  USING (key IN ('usd_to_sdg_rate', 'profit_margin_percent', 'referral_signup_discount_percent'));

COMMENT ON POLICY settings_select ON public.settings IS
  'P1-DB-001: public allowlist — anon/authenticated see only storefront-needed keys; internals stay admin-only.';
