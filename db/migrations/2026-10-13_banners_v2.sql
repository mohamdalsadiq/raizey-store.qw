-- MEEM STORE — banners v2 (status + copy + atomic reorder + stricter validation)
--
-- Builds on db/migrations/2026-10-12_banners.sql (apply that one first).
-- Adds:
--   · banners.status            draft | published   (default published)
--   · banners.hide_if_target_inactive (renamed from hide_when_target_disabled)
--   · admin_copy_banner(uuid)                 — duplicate a slide as a draft
--   · admin_set_banner_status(uuid, text)     — draft/publish toggle
--   · admin_reorder_banners(jsonb)            — save the whole order in ONE call
--   · stricter validation: image URLs must be repo /assets/banners/* or the
--     project's own Supabase storage (the `banners` bucket), never an arbitrary host
--   · get_banners_public() now also requires status = 'published'
--   · settings keys: banner_mobile_ratio, banner_autoplay, banner_interval, banner_effect
--   · products.is_on_offer (display-only flag; prices keep coming from the DB)
--
-- Idempotent. ROLLBACK: db/rollback/2026-10-13_banners_v2_rollback.sql
begin;

-- ---------------------------------------------------------------- 1. columns
alter table public.banners
  add column if not exists status text not null default 'published';
alter table public.banners
  drop constraint if exists banners_status_chk;
alter table public.banners
  add constraint banners_status_chk check (status in ('draft','published'));

-- Rename the flag to the documented name, preserving the values.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='banners'
               and column_name='hide_when_target_disabled')
     and not exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='banners'
               and column_name='hide_if_target_inactive') then
    alter table public.banners rename column hide_when_target_disabled to hide_if_target_inactive;
  end if;
end $$;

alter table public.banners
  add column if not exists hide_if_target_inactive boolean not null default true;

-- ---------------------------------------------------------------- 2. image URL scope
-- A banner image must live in the repo (/assets/banners/...) or the project's
-- own Supabase storage `banners` bucket. Anything else is rejected.
create or replace function public.banners_validate_image_url(p_url text)
returns boolean
language sql
immutable
as $$
  select case
    when p_url is null then false
    when p_url ~ '^/assets/banners/[A-Za-z0-9._@-]+$' then true
    when p_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/banners/[A-Za-z0-9._/@%-]+$' then true
    else false
  end;
$$;
revoke all on function public.banners_validate_image_url(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3. validate() v2
create or replace function public.banners_validate(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_style   text := coalesce(p_payload->>'banner_style','image_only');
  v_status  text := coalesce(p_payload->>'status','published');
  v_image_d text := btrim(coalesce(p_payload->>'image_desktop_url',''));
  v_image_m text := nullif(btrim(coalesce(p_payload->>'image_mobile_url','')),'');
  v_link    text := coalesce(p_payload->>'link_type','none');
  v_target  text := nullif(btrim(coalesce(p_payload->>'link_target','')),'');
  v_title   text := nullif(btrim(coalesce(p_payload->>'title','')),'');
  v_sub     text := nullif(btrim(coalesce(p_payload->>'subtitle','')),'');
  v_cta     text := nullif(btrim(coalesce(p_payload->>'cta_text','')),'');
  v_alt     text := nullif(btrim(coalesce(p_payload->>'alt_text','')),'');
  v_ovd     text := coalesce(p_payload->>'overlay_position_desktop','right');
  v_ovm     text := coalesce(p_payload->>'overlay_position_mobile','top');
begin
  if v_style not in ('image_only','image_text') then raise exception 'INVALID_STYLE'; end if;
  if v_status not in ('draft','published')      then raise exception 'INVALID_STATUS'; end if;
  if v_link not in ('none','page','product','category','offers','whatsapp','url') then
    raise exception 'INVALID_LINK_TYPE';
  end if;
  if v_ovd not in ('right','left') or v_ovm not in ('top','bottom') then
    raise exception 'INVALID_OVERLAY_POSITION';
  end if;

  if not public.banners_validate_image_url(v_image_d) then raise exception 'INVALID_IMAGE_DESKTOP_URL'; end if;
  if v_image_m is not null and not public.banners_validate_image_url(v_image_m) then
    raise exception 'INVALID_IMAGE_MOBILE_URL';
  end if;
  if v_image_d ilike 'javascript:%' or v_image_d ilike 'data:%'
     or coalesce(v_image_m,'') ilike 'javascript:%' or coalesce(v_image_m,'') ilike 'data:%' then
    raise exception 'INVALID_IMAGE_DESKTOP_URL';
  end if;

  if v_title is not null and char_length(v_title) > 45 then raise exception 'TITLE_TOO_LONG'; end if;
  if v_sub   is not null and char_length(v_sub)   > 90 then raise exception 'SUBTITLE_TOO_LONG'; end if;
  if v_cta   is not null and char_length(v_cta)   > 20 then raise exception 'CTA_TOO_LONG'; end if;
  if v_style = 'image_text' and v_title is null then raise exception 'TITLE_REQUIRED'; end if;
  -- alt_text is mandatory before a slide may go live
  if v_status = 'published' and v_alt is null then raise exception 'ALT_REQUIRED'; end if;

  if v_target is not null and (v_target ilike 'javascript:%' or v_target ilike 'data:%') then
    raise exception 'INVALID_LINK_TARGET';
  end if;

  if v_link = 'none' then
    v_target := null;
  elsif v_link = 'offers' then
    v_target := null;
  elsif v_link = 'whatsapp' then
    v_target := null;
  elsif v_link = 'product' then
    if v_target is null or v_target !~ '^[0-9a-fA-F-]{36}$' then raise exception 'INVALID_PRODUCT_ID'; end if;
    if not exists (select 1 from public.products where id = v_target::uuid) then raise exception 'PRODUCT_NOT_FOUND'; end if;
  elsif v_link = 'category' then
    if v_target is null or v_target !~ '^[0-9a-fA-F-]{36}$' then raise exception 'INVALID_CATEGORY_ID'; end if;
    if not exists (select 1 from public.categories where id = v_target::uuid) then raise exception 'CATEGORY_NOT_FOUND'; end if;
  elsif v_link = 'page' then
    if v_target is null
       or v_target !~ '^[a-z0-9-]+\.html(#[A-Za-z0-9_-]+)?$'
       or split_part(v_target,'#',1) not in (
      'index.html','offers.html','wallet.html','cart.html','my-orders.html','product.html',
      'category.html','search.html','referrals.html','notifications.html','account.html',
      'privacy.html') then
      raise exception 'PAGE_NOT_ALLOWED';
    end if;
  elsif v_link = 'url' then
    if v_target is null or v_target !~ '^https://[^[:space:]]+$' then raise exception 'INVALID_URL'; end if;
  end if;

  return jsonb_build_object(
    'banner_style', v_style, 'status', v_status,
    'title', v_title, 'subtitle', v_sub, 'cta_text', v_cta,
    'alt_text', left(coalesce(btrim(p_payload->>'alt_text'),''), 160),
    'image_desktop_url', v_image_d, 'image_mobile_url', v_image_m,
    'link_type', v_link, 'link_target', v_target,
    'whatsapp_message', left(nullif(btrim(coalesce(p_payload->>'whatsapp_message','')),''), 400),
    'overlay_position_desktop', v_ovd, 'overlay_position_mobile', v_ovm,
    'hide_if_target_inactive', coalesce((p_payload->>'hide_if_target_inactive')::boolean, true),
    'sort_order', coalesce((p_payload->>'sort_order')::integer, 0),
    'is_active', coalesce((p_payload->>'is_active')::boolean, true),
    'starts_at', nullif(btrim(coalesce(p_payload->>'starts_at','')),'')::timestamptz,
    'ends_at',   nullif(btrim(coalesce(p_payload->>'ends_at','')),'')::timestamptz
  );
end;
$$;
revoke all on function public.banners_validate(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- 4. save() v2
create or replace function public.admin_save_banner(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v     jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;

  v := public.banners_validate(coalesce(p_payload,'{}'::jsonb));

  if p_id is null then
    insert into public.banners (
      banner_style, status, title, subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
      link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
      hide_if_target_inactive, sort_order, is_active, starts_at, ends_at, created_by, updated_by)
    values (
      v->>'banner_style', v->>'status', v->>'title', v->>'subtitle', v->>'cta_text', v->>'alt_text',
      v->>'image_desktop_url', v->>'image_mobile_url', v->>'link_type', v->>'link_target',
      v->>'whatsapp_message', v->>'overlay_position_desktop', v->>'overlay_position_mobile',
      (v->>'hide_if_target_inactive')::boolean, (v->>'sort_order')::integer, (v->>'is_active')::boolean,
      (v->>'starts_at')::timestamptz, (v->>'ends_at')::timestamptz, v_uid, v_uid)
    returning id into v_id;
  else
    update public.banners set
      banner_style=v->>'banner_style', status=v->>'status', title=v->>'title', subtitle=v->>'subtitle',
      cta_text=v->>'cta_text', alt_text=v->>'alt_text',
      image_desktop_url=v->>'image_desktop_url', image_mobile_url=v->>'image_mobile_url',
      link_type=v->>'link_type', link_target=v->>'link_target', whatsapp_message=v->>'whatsapp_message',
      overlay_position_desktop=v->>'overlay_position_desktop', overlay_position_mobile=v->>'overlay_position_mobile',
      hide_if_target_inactive=(v->>'hide_if_target_inactive')::boolean,
      sort_order=(v->>'sort_order')::integer, is_active=(v->>'is_active')::boolean,
      starts_at=(v->>'starts_at')::timestamptz, ends_at=(v->>'ends_at')::timestamptz, updated_by=v_uid
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'BANNER_NOT_FOUND'; end if;
  end if;

  perform public.append_admin_audit_log(
    case when p_id is null then 'banner_create' else 'banner_update' end,
    'banners', v_id::text, v);
  return v_id;
end;
$$;
revoke all on function public.admin_save_banner(uuid,jsonb) from public, anon;
grant execute on function public.admin_save_banner(uuid,jsonb) to authenticated;

-- ---------------------------------------------------------------- 5. copy
create or replace function public.admin_copy_banner(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_new uuid;
  v_max integer;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;

  select coalesce(max(sort_order),0) + 1 into v_max from public.banners;

  insert into public.banners (
    banner_style, status, title, subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
    link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
    hide_if_target_inactive, sort_order, is_active, starts_at, ends_at, created_by, updated_by)
  select banner_style, 'draft',
         coalesce(title,'') || ' (نسخة)',
         subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
         link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
         hide_if_target_inactive, v_max, false, starts_at, ends_at, v_uid, v_uid
  from public.banners where id = p_id
  returning id into v_new;

  if v_new is null then raise exception 'BANNER_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('banner_copy','banners',v_new::text,
    jsonb_build_object('copied_from', p_id));
  return v_new;
end;
$$;
revoke all on function public.admin_copy_banner(uuid) from public, anon;
grant execute on function public.admin_copy_banner(uuid) to authenticated;

-- ---------------------------------------------------------------- 6. publish/draft
create or replace function public.admin_set_banner_status(p_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  if p_status not in ('draft','published') then raise exception 'INVALID_STATUS'; end if;

  -- publishing requires alt_text so the storefront never ships an alt-less image
  if p_status = 'published'
     and not exists (select 1 from public.banners b where b.id = p_id and coalesce(btrim(b.alt_text),'') <> '') then
    raise exception 'ALT_REQUIRED';
  end if;

  update public.banners set status = p_status, updated_by = v_uid where id = p_id;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('banner_set_status','banners',p_id::text,
    jsonb_build_object('status', p_status));
end;
$$;
revoke all on function public.admin_set_banner_status(uuid,text) from public, anon;
grant execute on function public.admin_set_banner_status(uuid,text) to authenticated;

-- ---------------------------------------------------------------- 7. atomic reorder
-- p_order is a JSON array of banner ids in display order, e.g. ["<uuid>","<uuid>"].
create or replace function public.admin_reorder_banners(p_order jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
  v_ids   uuid[];
  v_id    uuid;
  v_pos   integer := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'array' then raise exception 'INVALID_ORDER'; end if;

  select array_agg(value::uuid) into v_ids from jsonb_array_elements_text(p_order);
  v_count := coalesce(array_length(v_ids, 1), 0);
  if v_count = 0 then raise exception 'EMPTY_ORDER'; end if;

  -- every id must exist and there must be no duplicates / omissions
  if exists (select 1 from unnest(v_ids) u(id) group by id having count(*) > 1) then
    raise exception 'DUPLICATE_ID';
  end if;
  if v_count <> (select count(*) from public.banners where id = any(v_ids)) then
    raise exception 'UNKNOWN_ID';
  end if;
  if v_count <> (select count(*) from public.banners) then
    raise exception 'INCOMPLETE_ORDER';
  end if;

  foreach v_id in array v_ids loop
    v_pos := v_pos + 1;
    update public.banners set sort_order = v_pos, updated_by = v_uid where id = v_id;
  end loop;

  perform public.append_admin_audit_log('banner_reorder_all','banners',null,
    jsonb_build_object('order', p_order));
end;
$$;
revoke all on function public.admin_reorder_banners(jsonb) from public, anon;
grant execute on function public.admin_reorder_banners(jsonb) to authenticated;

-- ---------------------------------------------------------------- 8. public read (status-aware)
create or replace function public.get_banners_public()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(x order by (x->>'sort_order')::integer, x->>'created_at'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', b.id,
      'banner_style', b.banner_style,
      'title', b.title,
      'subtitle', b.subtitle,
      'cta_text', b.cta_text,
      'alt_text', b.alt_text,
      'image_desktop_url', b.image_desktop_url,
      'image_mobile_url', b.image_mobile_url,
      'link_type', b.link_type,
      'link_target', b.link_target,
      'whatsapp_message', b.whatsapp_message,
      'overlay_position_desktop', b.overlay_position_desktop,
      'overlay_position_mobile', b.overlay_position_mobile,
      'sort_order', b.sort_order,
      'created_at', b.created_at
    ) as x
    from public.banners b
    where b.status = 'published'
      and b.is_active
      and (b.starts_at is null or b.starts_at <= now())
      and (b.ends_at   is null or b.ends_at   >= now())
      and (
        not b.hide_if_target_inactive
        or b.link_type = 'none'
        or (b.link_type = 'product'  and exists (select 1 from public.products   p where p.id = b.link_target::uuid and p.is_active))
        or (b.link_type = 'category' and exists (select 1 from public.categories c where c.id = b.link_target::uuid and c.is_active))
        or b.link_type in ('page','offers','whatsapp','url')
      )
  ) s;
$$;
revoke all on function public.get_banners_public() from public;
grant execute on function public.get_banners_public() to anon, authenticated;

-- ---------------------------------------------------------------- 9. settings keys
insert into public.settings (key, value) values
  ('banner_mobile_ratio', coalesce((select value from public.settings where key='banner_mobile_aspect'), '3:4')),
  ('banner_autoplay', 'true'),
  ('banner_interval', '5'),
  ('banner_effect', 'slide'),
  -- tells offers.html the products.is_on_offer column now exists (avoids a 400 probe)
  ('offers_use_flag', 'true')
on conflict (key) do nothing;

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_ratio', 'banner_autoplay',
                 'banner_interval', 'banner_effect', 'offers_use_flag'));

-- ---------------------------------------------------------------- 10. products offer flag
alter table public.products add column if not exists is_on_offer boolean not null default false;
create index if not exists products_on_offer_idx on public.products (is_on_offer) where is_on_offer;

select count(*) as banners, (select count(*) from public.settings where key like 'banner_%') as banner_settings
from public.banners;

commit;
