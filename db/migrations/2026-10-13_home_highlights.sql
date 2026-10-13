-- MEEM STORE — homepage highlights: "الأكثر طلباً" (most ordered) feed.
--
-- orders is one row per purchased product (public.orders.product_id), so the
-- most-ordered list is a real aggregate over completed/in-progress orders —
-- never a hardcoded number. The function is SECURITY DEFINER so it can count
-- across users without exposing any order rows, and returns only public
-- product fields + an order count.
--
-- "الجديد" (newest) needs no DB work: the storefront sorts products by the
-- real products.created_at column.
--
-- Idempotent. ROLLBACK: db/rollback/2026-10-13_home_highlights_rollback.sql
begin;

create or replace function public.get_top_ordered_products(p_limit integer default 8)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  with counts as (
    select o.product_id, count(*)::int as ordered
    from public.orders o
    where o.product_id is not null
      and o.status in ('completed','in_progress')
    group by o.product_id
  )
  select coalesce(jsonb_agg(x order by (x->>'ordered')::int desc, x->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'image_url', p.image_url,
      'price_usd', p.price_usd,
      'ordered', c.ordered
    ) as x
    from counts c
    join public.products p on p.id = c.product_id and p.is_active
    order by c.ordered desc, p.name
    limit greatest(1, least(coalesce(p_limit, 8), 24))
  ) s;
$$;
revoke all on function public.get_top_ordered_products(integer) from public;
grant execute on function public.get_top_ordered_products(integer) to anon, authenticated;

-- capability marker: the storefront only calls the function / renders the
-- highlights once the schema advertises them.
insert into public.settings (key, value) values ('home_highlights_flag', 'true')
on conflict (key) do nothing;

drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings
  for select to anon, authenticated
  using (key in ('usd_to_sdg_rate', 'profit_margin_percent',
                 'referral_signup_discount_percent', 'whatsapp_number',
                 'banner_mobile_ratio', 'banner_autoplay',
                 'banner_interval', 'banner_effect', 'offers_use_flag',
                 'catalog_icons_flag', 'home_highlights_flag'));

select public.get_top_ordered_products(8) as sample;

commit;
