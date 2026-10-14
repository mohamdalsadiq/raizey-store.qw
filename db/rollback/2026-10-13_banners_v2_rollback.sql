-- ROLLBACK for db/migrations/2026-10-13_banners_v2.sql
-- Restores the v1 function bodies from 2026-10-12_banners.sql and drops the
-- v2-only columns / settings / helper. Idempotent. Prices and orders untouched.
begin;

-- 1. drop the v2-only functions
drop function if exists public.admin_reorder_banners(jsonb);
drop function if exists public.admin_set_banner_status(uuid,text);
drop function if exists public.admin_copy_banner(uuid);

-- 2. restore v1 save() (v2 only added the status/alt branch)
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
      coalesce((v->>'hide_if_target_inactive')::boolean, true),
      (v->>'sort_order')::integer, (v->>'is_active')::boolean,
      (v->>'starts_at')::timestamptz, (v->>'ends_at')::timestamptz, v_uid, v_uid)
    returning id into v_id;
  else
    update public.banners set
      banner_style=v->>'banner_style', title=v->>'title', subtitle=v->>'subtitle', cta_text=v->>'cta_text',
      alt_text=v->>'alt_text', image_desktop_url=v->>'image_desktop_url', image_mobile_url=v->>'image_mobile_url',
      link_type=v->>'link_type', link_target=v->>'link_target', whatsapp_message=v->>'whatsapp_message',
      overlay_position_desktop=v->>'overlay_position_desktop', overlay_position_mobile=v->>'overlay_position_mobile',
      hide_if_target_inactive=coalesce((v->>'hide_if_target_inactive')::boolean, true),
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

-- 3. restore the v1 public read (no status column)
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
      'id', b.id, 'banner_style', b.banner_style, 'title', b.title, 'subtitle', b.subtitle,
      'cta_text', b.cta_text, 'alt_text', b.alt_text,
      'image_desktop_url', b.image_desktop_url, 'image_mobile_url', b.image_mobile_url,
      'link_type', b.link_type, 'link_target', b.link_target, 'whatsapp_message', b.whatsapp_message,
      'overlay_position_desktop', b.overlay_position_desktop,
      'overlay_position_mobile', b.overlay_position_mobile,
      'sort_order', b.sort_order, 'created_at', b.created_at
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

-- 4. restore the v1 validate() (permissive image URL regex, no status/alt gate)
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
  if v_style not in ('image_only','image_text') then raise exception 'INVALID_STYLE'; end if;
  if v_link not in ('none','page','product','category','offers','whatsapp','url') then raise exception 'INVALID_LINK_TYPE'; end if;
  if v_ovd not in ('right','left') or v_ovm not in ('top','bottom') then raise exception 'INVALID_OVERLAY_POSITION'; end if;
  if v_image_d = '' or v_image_d !~ v_url_re
     or v_image_d ilike 'javascript:%' or v_image_d ilike 'data:%' then raise exception 'INVALID_IMAGE_DESKTOP_URL'; end if;
  if v_image_m is not null
     and (v_image_m !~ v_url_re or v_image_m ilike 'javascript:%' or v_image_m ilike 'data:%') then raise exception 'INVALID_IMAGE_MOBILE_URL'; end if;
  if v_title is not null and char_length(v_title) > 45 then raise exception 'TITLE_TOO_LONG'; end if;
  if v_sub   is not null and char_length(v_sub)   > 90 then raise exception 'SUBTITLE_TOO_LONG'; end if;
  if v_cta   is not null and char_length(v_cta)   > 20 then raise exception 'CTA_TOO_LONG'; end if;
  if v_style = 'image_text' and v_title is null then raise exception 'TITLE_REQUIRED'; end if;
  if v_target is not null and (v_target ilike 'javascript:%' or v_target ilike 'data:%') then raise exception 'INVALID_LINK_TARGET'; end if;
  if v_link = 'none' then v_target := null;
  elsif v_link = 'offers' then v_target := null;
  elsif v_link = 'whatsapp' then v_target := null;
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
      'category.html','search.html','referrals.html','notifications.html','account.html','privacy.html') then
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

drop function if exists public.banners_validate_image_url(text);

-- 5. drop the v2 settings we added (keep the v1 banner_mobile_aspect untouched)
delete from public.settings where key in ('banner_mobile_ratio','banner_autoplay','banner_interval','banner_effect','offers_use_flag');

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_aspect'));

-- 5.b restore the v1 public read policy (it no longer has a status column)
drop policy if exists banners_public_read on public.banners;
create policy banners_public_read on public.banners
  for select to anon, authenticated
  using (
    is_active
    and (starts_at is null or starts_at <= now())
    and (ends_at   is null or ends_at   >= now())
  );

-- 6. drop the v2 columns
alter table public.banners drop constraint if exists banners_status_chk;
alter table public.banners drop column if exists status;
drop index if exists public.products_on_offer_idx;
alter table public.products drop column if exists is_on_offer;

-- keep hide_if_target_inactive (the restored v1 functions above use it); the
-- original column name is only cosmetic and no other code depends on it.

commit;
