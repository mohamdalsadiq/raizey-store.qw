-- BRAND-001 — store WhatsApp number moves out of the HTML and into public.settings.
--
-- Why: the support number was hardcoded in three shipped files
-- (index.html, category.html, checkout-v2.html). It must be readable from the
-- database so support can change it without a deploy.
--
-- Scope: ONE new settings row (default = the value that was hardcoded) and the
-- public read allowlist widened by exactly ONE key. No table/column changes.
-- No customer, wallet, order, receipt or profile row is touched.
--
-- ============================ ROLLBACK =====================================
-- BEGIN;
--   DROP POLICY IF EXISTS settings_select ON public.settings;
--   CREATE POLICY settings_select ON public.settings
--     FOR SELECT TO anon, authenticated
--     USING (key IN ('usd_to_sdg_rate', 'profit_margin_percent',
--                    'referral_signup_discount_percent'));
--   DELETE FROM public.settings WHERE key = 'whatsapp_number';
-- COMMIT;
-- ===========================================================================

BEGIN;

INSERT INTO public.settings (key, value)
VALUES ('whatsapp_number', '249901815039')
ON CONFLICT (key) DO NOTHING;

-- P1-DB-001 allowlist + the new public key (admins keep full access via settings_admin).
DROP POLICY IF EXISTS settings_select ON public.settings;

CREATE POLICY settings_select ON public.settings
  FOR SELECT TO anon, authenticated
  USING (key IN ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number'));

COMMENT ON POLICY settings_select ON public.settings IS
  'Public storefront allowlist: exchange rate, margin, referral discount and the support WhatsApp number. Everything else is admin-only.';

COMMIT;

-- Post-check (must all be true):
--   SELECT count(*) = 1 FROM public.settings WHERE key = 'whatsapp_number';
--   SELECT relrowsecurity FROM pg_class WHERE relname = 'settings';           -- true
--   SELECT pg_get_expr(polqual, polrelid) FROM pg_policy WHERE polname = 'settings_select';
