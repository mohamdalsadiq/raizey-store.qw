-- Rollback for the banner mobile ratio setting.
begin;
drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number'));
delete from public.settings where key = 'banner_mobile_aspect';
commit;
