-- MEEM STORE — Phase 3a: homepage banner carousel
-- table + RLS + admin RPCs + audit + public read RPC + storage bucket/policies
-- Idempotent. Apply inside a transaction (see the wrapper at the bottom).

begin;

-- ---------------------------------------------------------------- table
create table if not exists public.banners (
  id                        uuid primary key default gen_random_uuid(),
  banner_style              text not null default 'image_only',
  title                     text,
  subtitle                  text,
  cta_text                  text,
  alt_text                  text not null default '',
  image_desktop_url         text not null,
  image_mobile_url          text,
  link_type                 text not null default 'none',
  link_target               text,
  whatsapp_message          text,
  overlay_position_desktop  text not null default 'right',
  overlay_position_mobile   text not null default 'top',
  hide_if_target_inactive   boolean not null default true,
  sort_order                integer not null default 0,
  is_active                 boolean not null default true,
  starts_at                 timestamptz,
  ends_at                   timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  created_by                uuid,
  updated_by                uuid,
  constraint banners_style_chk   check (banner_style in ('image_only','image_text')),
  constraint banners_link_chk    check (link_type in ('none','page','product','category','offers','whatsapp','url')),
  constraint banners_ovd_chk     check (overlay_position_desktop in ('right','left')),
  constraint banners_ovm_chk     check (overlay_position_mobile in ('top','bottom')),
  constraint banners_window_chk  check (ends_at is null or starts_at is null or ends_at > starts_at),
  -- char limits come from the admin form spec
  constraint banners_title_len    check (title is null or char_length(title) <= 45),
  constraint banners_subtitle_len check (subtitle is null or char_length(subtitle) <= 90),
  constraint banners_cta_len      check (cta_text is null or char_length(cta_text) <= 20),
  -- only same-origin relative paths or https
  constraint banners_img_d_chk check (image_desktop_url ~ '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$'),
  constraint banners_img_m_chk check (image_mobile_url is null or image_mobile_url ~ '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$'),
  constraint banners_no_scheme_abuse check (
    image_desktop_url not ilike 'javascript:%' and image_desktop_url not ilike 'data:%'
    and coalesce(image_mobile_url,'') not ilike 'javascript:%' and coalesce(image_mobile_url,'') not ilike 'data:%'
    and (link_target is null or (link_target not ilike 'javascript:%' and link_target not ilike 'data:%'))
  ),
  -- image_text requires a real title
  constraint banners_text_chk check (banner_style <> 'image_text' or (title is not null and btrim(title) <> '')),
  -- link target must match the declared link type
  constraint banners_target_chk check (
    case link_type
      when 'none'     then link_target is null
      when 'offers'   then link_target is null
      when 'whatsapp' then link_target is null
      when 'url'      then link_target ~ '^https://'
      else coalesce(btrim(link_target),'') <> ''
    end
  )
);

-- The column shipped as hide_when_target_disabled in the first draft of this
-- file; keep databases that already ran that draft working.
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

-- constraints are dropped+re-added so that re-running this file repairs an
-- older definition (the table itself is created above only when missing)
alter table public.banners drop constraint if exists banners_img_d_chk;
alter table public.banners drop constraint if exists banners_img_m_chk;
alter table public.banners add constraint banners_img_d_chk
  check (image_desktop_url ~ '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$');
alter table public.banners add constraint banners_img_m_chk
  check (image_mobile_url is null
         or image_mobile_url ~ '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$');

create index if not exists banners_public_idx on public.banners (is_active, sort_order);
create index if not exists banners_sort_idx on public.banners (sort_order, created_at);

drop trigger if exists banners_touch on public.banners;
create trigger banners_touch before update on public.banners
  for each row execute function public.set_row_updated_at();

-- ---------------------------------------------------------------- RLS
alter table public.banners enable row level security;

-- public read: only active slides inside their display window
drop policy if exists banners_public_read on public.banners;
create policy banners_public_read on public.banners
  for select to anon, authenticated
  using (
    is_active
    and (starts_at is null or starts_at <= now())
    and (ends_at   is null or ends_at   >= now())
  );

-- admins may read everything (incl. inactive) for the admin screen
drop policy if exists banners_admin_read on public.banners;
create policy banners_admin_read on public.banners
  for select to authenticated
  using (public.is_admin());

-- writes go through the SECURITY DEFINER RPCs only: no INSERT/UPDATE/DELETE policy.
revoke all on public.banners from anon, authenticated;
grant select on public.banners to anon, authenticated;

-- ---------------------------------------------------------------- validation helper
create or replace function public.banners_validate(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_style   text := coalesce(p_payload->>'banner_style','image_only');
  v_image_d text := btrim(coalesce(p_payload->>'image_desktop_url',''));
  v_image_m text := nullif(btrim(coalesce(p_payload->>'image_mobile_url','')),'');
  v_link    text := coalesce(p_payload->>'link_type','none');
  v_target  text := nullif(btrim(coalesce(p_payload->>'link_target','')),'');
  v_title   text := nullif(btrim(coalesce(p_payload->>'title','')),'');
  v_sub     text := nullif(btrim(coalesce(p_payload->>'subtitle','')),'');
  v_cta     text := nullif(btrim(coalesce(p_payload->>'cta_text','')),'');
  v_ovd     text := coalesce(p_payload->>'overlay_position_desktop','right');
  v_ovm     text := coalesce(p_payload->>'overlay_position_mobile','top');
  v_url_re  text := '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$';
begin
  if v_style not in ('image_only','image_text') then
    raise exception 'INVALID_STYLE';
  end if;
  if v_link not in ('none','page','product','category','offers','whatsapp','url') then
    raise exception 'INVALID_LINK_TYPE';
  end if;
  if v_ovd not in ('right','left') or v_ovm not in ('top','bottom') then
    raise exception 'INVALID_OVERLAY_POSITION';
  end if;
  if v_image_d = '' or v_image_d !~ v_url_re
     or v_image_d ilike 'javascript:%' or v_image_d ilike 'data:%' then
    raise exception 'INVALID_IMAGE_DESKTOP_URL';
  end if;
  if v_image_m is not null
     and (v_image_m !~ v_url_re or v_image_m ilike 'javascript:%' or v_image_m ilike 'data:%') then
    raise exception 'INVALID_IMAGE_MOBILE_URL';
  end if;
  -- length caps are enforced for every style, not just image_text
  if v_title is not null and char_length(v_title) > 45 then raise exception 'TITLE_TOO_LONG'; end if;
  if v_sub   is not null and char_length(v_sub)   > 90 then raise exception 'SUBTITLE_TOO_LONG'; end if;
  if v_cta   is not null and char_length(v_cta)   > 20 then raise exception 'CTA_TOO_LONG'; end if;
  if v_style = 'image_text' and v_title is null then
    raise exception 'TITLE_REQUIRED';
  end if;
  if v_target is not null and (v_target ilike 'javascript:%' or v_target ilike 'data:%') then
    raise exception 'INVALID_LINK_TARGET';
  end if;
  if v_link = 'none' then
    v_target := null;
  elsif v_link = 'offers' then
    v_target := null;
  elsif v_link = 'whatsapp' then
    v_target := null;   -- the number always comes from public.settings
  elsif v_link = 'product' then
    if v_target is null or v_target !~ '^[0-9a-fA-F-]{36}$' then raise exception 'INVALID_PRODUCT_ID'; end if;
    if not exists (select 1 from public.products where id = v_target::uuid) then raise exception 'PRODUCT_NOT_FOUND'; end if;
  elsif v_link = 'category' then
    if v_target is null or v_target !~ '^[0-9a-fA-F-]{36}$' then raise exception 'INVALID_CATEGORY_ID'; end if;
    if not exists (select 1 from public.categories where id = v_target::uuid) then raise exception 'CATEGORY_NOT_FOUND'; end if;
  elsif v_link = 'page' then
    -- optional #anchor on a whitelisted local page, e.g. index.html#products
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
    'banner_style', v_style, 'title', v_title, 'subtitle', v_sub, 'cta_text', v_cta,
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

-- ---------------------------------------------------------------- admin RPC: save
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
      banner_style, title, subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
      link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
      hide_if_target_inactive, sort_order, is_active, starts_at, ends_at, created_by, updated_by)
    values (
      v->>'banner_style', v->>'title', v->>'subtitle', v->>'cta_text', v->>'alt_text',
      v->>'image_desktop_url', v->>'image_mobile_url', v->>'link_type', v->>'link_target',
      v->>'whatsapp_message', v->>'overlay_position_desktop', v->>'overlay_position_mobile',
      (v->>'hide_if_target_inactive')::boolean, (v->>'sort_order')::integer, (v->>'is_active')::boolean,
      (v->>'starts_at')::timestamptz, (v->>'ends_at')::timestamptz, v_uid, v_uid)
    returning id into v_id;
  else
    update public.banners set
      banner_style=v->>'banner_style', title=v->>'title', subtitle=v->>'subtitle', cta_text=v->>'cta_text',
      alt_text=v->>'alt_text', image_desktop_url=v->>'image_desktop_url', image_mobile_url=v->>'image_mobile_url',
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

-- ---------------------------------------------------------------- admin RPCs: delete / activate / reorder
create or replace function public.admin_delete_banner(p_id uuid)
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
  delete from public.banners where id = p_id;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
  perform public.append_admin_audit_log('banner_delete','banners',p_id::text,jsonb_build_object('id',p_id));
end;
$$;

create or replace function public.admin_set_banner_active(p_id uuid, p_active boolean)
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
  update public.banners set is_active = coalesce(p_active,false), updated_by = v_uid where id = p_id;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
  perform public.append_admin_audit_log('banner_set_active','banners',p_id::text,
    jsonb_build_object('is_active',coalesce(p_active,false)));
end;
$$;

create or replace function public.admin_reorder_banner(p_id uuid, p_direction text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_cur integer;
  v_other uuid;
  v_other_order integer;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  if p_direction not in ('up','down') then raise exception 'INVALID_DIRECTION'; end if;

  select sort_order into v_cur from public.banners where id = p_id;
  if v_cur is null then raise exception 'BANNER_NOT_FOUND'; end if;

  if p_direction = 'up' then
    select id, sort_order into v_other, v_other_order from public.banners
      where (sort_order, id) < (v_cur, p_id) order by sort_order desc, id desc limit 1;
  else
    select id, sort_order into v_other, v_other_order from public.banners
      where (sort_order, id) > (v_cur, p_id) order by sort_order asc, id asc limit 1;
  end if;
  if v_other is null then return; end if;

  update public.banners set sort_order = v_other_order, updated_by = v_uid where id = p_id;
  update public.banners set sort_order = v_cur, updated_by = v_uid where id = v_other;
  perform public.append_admin_audit_log('banner_reorder','banners',p_id::text,
    jsonb_build_object('direction',p_direction,'swapped_with',v_other));
end;
$$;

revoke all on function public.admin_save_banner(uuid,jsonb)   from public, anon;
revoke all on function public.admin_delete_banner(uuid)       from public, anon;
revoke all on function public.admin_set_banner_active(uuid,boolean) from public, anon;
revoke all on function public.admin_reorder_banner(uuid,text) from public, anon;
grant execute on function public.admin_save_banner(uuid,jsonb)   to authenticated;
grant execute on function public.admin_delete_banner(uuid)       to authenticated;
grant execute on function public.admin_set_banner_active(uuid,boolean) to authenticated;
grant execute on function public.admin_reorder_banner(uuid,text) to authenticated;

-- ---------------------------------------------------------------- public read RPC
-- Returns only slides the storefront may render, in order, already validated.
create or replace function public.get_banners_public()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(x order by x->>'sort_order', x->>'created_at'), '[]'::jsonb)
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
    where b.is_active
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

-- ---------------------------------------------------------------- storage bucket
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('banners','banners', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 2097152,
      allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists banners_public_read_objects on storage.objects;
create policy banners_public_read_objects on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'banners');

drop policy if exists banners_admin_write on storage.objects;
create policy banners_admin_write on storage.objects
  for insert to authenticated
  with check (bucket_id = 'banners' and public.is_admin());

drop policy if exists banners_admin_update on storage.objects;
create policy banners_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'banners' and public.is_admin())
  with check (bucket_id = 'banners' and public.is_admin());

drop policy if exists banners_admin_delete on storage.objects;
create policy banners_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'banners' and public.is_admin());

commit;
