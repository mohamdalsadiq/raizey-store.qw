-- MEEM STORE — section & category icons (auto | preset | custom)
--
-- Adds the icon columns used by assets/js/category-icons.js, an admin-only
-- storage bucket for custom icons, and admin RPCs (is_admin + permission +
-- audit log) that validate the icon key/image before it is stored.
--
-- The storefront works with or without these columns (see index.html / category.html):
-- absent columns are treated as icon_mode = 'auto'.
--
-- Idempotent. ROLLBACK: db/rollback/2026-10-13_section_category_icons_rollback.sql
begin;

-- ---------------------------------------------------------------- 1. columns
-- store_sections
alter table public.store_sections
  add column if not exists description text,
  add column if not exists icon_mode text not null default 'auto',
  add column if not exists icon_key text,
  add column if not exists icon_image_url text;
alter table public.store_sections drop constraint if exists store_sections_icon_mode_chk;
alter table public.store_sections
  add constraint store_sections_icon_mode_chk check (icon_mode in ('auto','preset','custom'));
alter table public.store_sections drop constraint if exists store_sections_icon_key_chk;
alter table public.store_sections
  add constraint store_sections_icon_key_chk check (icon_key is null or icon_key ~ '^[a-z0-9-]{2,40}$');

-- categories
alter table public.categories
  add column if not exists icon_mode text not null default 'auto',
  add column if not exists icon_key text,
  add column if not exists icon_image_url text;
alter table public.categories drop constraint if exists categories_icon_mode_chk;
alter table public.categories
  add constraint categories_icon_mode_chk check (icon_mode in ('auto','preset','custom'));
alter table public.categories drop constraint if exists categories_icon_key_chk;
alter table public.categories
  add constraint categories_icon_key_chk check (icon_key is null or icon_key ~ '^[a-z0-9-]{2,40}$');

-- ---------------------------------------------------------------- 2. image scope helper
create or replace function public.icon_image_url_ok(p_url text)
returns boolean
language sql
immutable
as $$
  select case
    when p_url is null then true
    when p_url = '' then true
    when p_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/category-icons/[A-Za-z0-9._/@%-]+$' then true
    else false
  end;
$$;
revoke all on function public.icon_image_url_ok(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3. storage bucket
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('category-icons','category-icons', true, 209715, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 209715,
      allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists category_icons_public_read on storage.objects;
create policy category_icons_public_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'category-icons');

drop policy if exists category_icons_admin_write on storage.objects;
create policy category_icons_admin_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'category-icons' and public.is_admin());

drop policy if exists category_icons_admin_update on storage.objects;
create policy category_icons_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'category-icons' and public.is_admin())
  with check (bucket_id = 'category-icons' and public.is_admin());

drop policy if exists category_icons_admin_delete on storage.objects;
create policy category_icons_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'category-icons' and public.is_admin());

-- ---------------------------------------------------------------- 4. shared validation
create or replace function public.icon_fields_validate(p_mode text, p_key text, p_image text)
returns void
language plpgsql
immutable
as $$
declare
  v_mode text := coalesce(nullif(btrim(p_mode),''),'auto');
  v_key  text := nullif(btrim(coalesce(p_key,'')),'');
  v_img  text := nullif(btrim(coalesce(p_image,'')),'');
begin
  if v_mode not in ('auto','preset','custom') then raise exception 'INVALID_ICON_MODE'; end if;
  if v_mode = 'preset' then
    if v_key is null or v_key !~ '^[a-z0-9-]{2,40}$' then raise exception 'INVALID_ICON_KEY'; end if;
  end if;
  if v_mode = 'custom' then
    if v_img is null then raise exception 'ICON_IMAGE_REQUIRED'; end if;
    if not public.icon_image_url_ok(v_img) then raise exception 'INVALID_ICON_IMAGE_URL'; end if;
  end if;
end;
$$;
revoke all on function public.icon_fields_validate(text,text,text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. admin RPCs
create or replace function public.admin_set_section_icon(
  p_id uuid, p_mode text, p_key text, p_image text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_products') then raise exception 'PERMISSION_REQUIRED'; end if;

  perform public.icon_fields_validate(p_mode, p_key, p_image);

  update public.store_sections set
    icon_mode = coalesce(nullif(btrim(p_mode),''),'auto'),
    icon_key = case when p_mode = 'preset' then nullif(btrim(coalesce(p_key,'')),'') else null end,
    icon_image_url = case when p_mode = 'custom' then nullif(btrim(coalesce(p_image,'')),'') else null end
  where id = p_id;
  if not found then raise exception 'SECTION_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('section_set_icon','store_sections',p_id::text,
    jsonb_build_object('mode',p_mode,'key',p_key,'image',p_image));
end;
$$;
revoke all on function public.admin_set_section_icon(uuid,text,text,text) from public, anon;
grant execute on function public.admin_set_section_icon(uuid,text,text,text) to authenticated;

create or replace function public.admin_set_category_icon(
  p_id uuid, p_mode text, p_key text, p_image text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_products') then raise exception 'PERMISSION_REQUIRED'; end if;

  perform public.icon_fields_validate(p_mode, p_key, p_image);

  update public.categories set
    icon_mode = coalesce(nullif(btrim(p_mode),''),'auto'),
    icon_key = case when p_mode = 'preset' then nullif(btrim(coalesce(p_key,'')),'') else null end,
    icon_image_url = case when p_mode = 'custom' then nullif(btrim(coalesce(p_image,'')),'') else null end
  where id = p_id;
  if not found then raise exception 'CATEGORY_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('category_set_icon','categories',p_id::text,
    jsonb_build_object('mode',p_mode,'key',p_key,'image',p_image));
end;
$$;
revoke all on function public.admin_set_category_icon(uuid,text,text,text) from public, anon;
grant execute on function public.admin_set_category_icon(uuid,text,text,text) to authenticated;

-- ---------------------------------------------------------------- 6. capability marker
-- The storefront reads this before asking for the new columns, so it never
-- issues a request against a column that is not there yet.
insert into public.settings (key, value) values ('catalog_icons_flag', 'true')
on conflict (key) do nothing;

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_ratio', 'banner_autoplay',
                 'banner_interval', 'banner_effect', 'offers_use_flag',
                 'catalog_icons_flag'));

select
  (select count(*) from public.store_sections) as sections,
  (select count(*) from public.categories) as categories;

commit;
