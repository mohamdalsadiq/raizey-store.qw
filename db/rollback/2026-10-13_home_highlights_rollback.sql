-- ROLLBACK for db/migrations/2026-10-13_home_highlights.sql
-- Drops the most-ordered RPC and the capability marker. No data is touched.
begin;

drop function if exists public.get_top_ordered_products(integer);

delete from public.settings where key = 'home_highlights_flag';

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_ratio', 'banner_autoplay',
                 'banner_interval', 'banner_effect', 'offers_use_flag',
                 'catalog_icons_flag'));

commit;
