-- MEEM STORE — the mobile banner ratio becomes a global store setting.
--
-- Why: every mobile artwork is 3:4 portrait, and all slides must share one
-- ratio so the hero height never jumps between slides. The ratio is data, not
-- a hardcoded CSS value, so support can switch 3:4 / 4:5 / 1:1 / 4:3 without a
-- deploy. Desktop stays 8:3 always.
--
-- Scope: ONE new settings row + the public read allowlist widened by ONE key.
-- No banner, order, wallet or profile row is touched.
--
-- ROLLBACK: db/rollback/2026-10-12_banner_mobile_aspect_rollback.sql
begin;

insert into public.settings (key, value)
values ('banner_mobile_aspect', '3:4')
on conflict (key) do nothing;

-- Public storefront allowlist (P1-DB-001) + the new key. Admins keep full
-- access through the settings_admin policy.
drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_aspect'));

comment on policy settings_select on public.settings is
  'Public storefront allowlist: exchange rate, margin, referral discount, support WhatsApp number and the banner mobile ratio. Everything else is admin-only.';

select key, value from public.settings where key = 'banner_mobile_aspect';

commit;
