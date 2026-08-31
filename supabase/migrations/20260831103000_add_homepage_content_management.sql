begin;

create table if not exists public.store_banners (
  id uuid primary key default gen_random_uuid(),
  eyebrow text not null default 'RAIZEY STORE'
    check (char_length(eyebrow) between 1 and 60),
  title text not null
    check (char_length(title) between 1 and 120),
  subtitle text not null default ''
    check (char_length(subtitle) <= 260),
  image_url text
    check (image_url is null or image_url ~ '^https://'),
  link_url text not null default 'index.html'
    check (char_length(link_url) between 1 and 2048 and link_url !~* '^\s*(javascript|data):'),
  display_order integer not null default 0
    check (display_order between -1000 and 1000),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.store_ticker_items (
  id uuid primary key default gen_random_uuid(),
  text text not null
    check (char_length(text) between 1 and 140),
  display_order integer not null default 0
    check (display_order between -1000 and 1000),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.store_banners enable row level security;
alter table public.store_ticker_items enable row level security;

revoke all on public.store_banners from public, anon, authenticated;
revoke all on public.store_ticker_items from public, anon, authenticated;
grant select on public.store_banners to anon, authenticated;
grant select on public.store_ticker_items to anon, authenticated;
grant insert, update, delete on public.store_banners to authenticated;
grant insert, update, delete on public.store_ticker_items to authenticated;

drop policy if exists store_banners_select_anon on public.store_banners;
create policy store_banners_select_anon
  on public.store_banners for select to anon
  using (is_active = true);

drop policy if exists store_banners_select_authenticated on public.store_banners;
create policy store_banners_select_authenticated
  on public.store_banners for select to authenticated
  using (
    is_active = true
    or ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')))
  );

drop policy if exists store_banners_admin_insert on public.store_banners;
create policy store_banners_admin_insert
  on public.store_banners for insert to authenticated
  with check (
    (select public.is_admin())
    and (select public.has_admin_permission('manage_settings'))
    and created_by = (select auth.uid())
  );

drop policy if exists store_banners_admin_update on public.store_banners;
create policy store_banners_admin_update
  on public.store_banners for update to authenticated
  using ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')))
  with check ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')));

drop policy if exists store_banners_admin_delete on public.store_banners;
create policy store_banners_admin_delete
  on public.store_banners for delete to authenticated
  using ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')));

drop policy if exists store_ticker_select_anon on public.store_ticker_items;
create policy store_ticker_select_anon
  on public.store_ticker_items for select to anon
  using (is_active = true);

drop policy if exists store_ticker_select_authenticated on public.store_ticker_items;
create policy store_ticker_select_authenticated
  on public.store_ticker_items for select to authenticated
  using (
    is_active = true
    or ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')))
  );

drop policy if exists store_ticker_admin_insert on public.store_ticker_items;
create policy store_ticker_admin_insert
  on public.store_ticker_items for insert to authenticated
  with check (
    (select public.is_admin())
    and (select public.has_admin_permission('manage_settings'))
    and created_by = (select auth.uid())
  );

drop policy if exists store_ticker_admin_update on public.store_ticker_items;
create policy store_ticker_admin_update
  on public.store_ticker_items for update to authenticated
  using ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')))
  with check ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')));

drop policy if exists store_ticker_admin_delete on public.store_ticker_items;
create policy store_ticker_admin_delete
  on public.store_ticker_items for delete to authenticated
  using ((select public.is_admin()) and (select public.has_admin_permission('manage_settings')));

create index if not exists idx_store_banners_public_order
  on public.store_banners (display_order, created_at)
  where is_active = true;
create index if not exists idx_store_ticker_public_order
  on public.store_ticker_items (display_order, created_at)
  where is_active = true;
create index if not exists idx_store_banners_created_by
  on public.store_banners (created_by);
create index if not exists idx_store_ticker_created_by
  on public.store_ticker_items (created_by);

commit;
