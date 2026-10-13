-- ROLLBACK for db/migrations/2026-10-13_section_category_icons.sql
-- Drops the icon RPCs, the bucket + its policies, the helper and the columns.
-- Idempotent. No product/price/order data touched.
begin;

drop function if exists public.admin_set_section_icon(uuid,text,text,text);
drop function if exists public.admin_set_category_icon(uuid,text,text,text);
drop function if exists public.icon_fields_validate(text,text,text);
drop function if exists public.icon_image_url_ok(text);

drop policy if exists category_icons_public_read on storage.objects;
drop policy if exists category_icons_admin_write on storage.objects;
drop policy if exists category_icons_admin_update on storage.objects;
drop policy if exists category_icons_admin_delete on storage.objects;
-- The bucket itself is left in place on purpose: dropping storage.buckets could
-- cascade to objects. Remove it manually only after the objects are gone.

delete from public.settings where key = 'catalog_icons_flag';

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_ratio', 'banner_autoplay',
                 'banner_interval', 'banner_effect', 'offers_use_flag'));

alter table public.store_sections drop constraint if exists store_sections_icon_key_chk;
alter table public.store_sections drop constraint if exists store_sections_icon_mode_chk;
alter table public.store_sections
  drop column if exists icon_image_url,
  drop column if exists icon_key,
  drop column if exists icon_mode,
  drop column if exists description;

alter table public.categories drop constraint if exists categories_icon_key_chk;
alter table public.categories drop constraint if exists categories_icon_mode_chk;
alter table public.categories
  drop column if exists icon_image_url,
  drop column if exists icon_key,
  drop column if exists icon_mode;

commit;
