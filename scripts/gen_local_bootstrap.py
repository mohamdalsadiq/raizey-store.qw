#!/usr/bin/env python3
"""Regenerate db/tests/local_bootstrap.sql from the read-only live-schema snapshot.

The SQL suites in db/tests run against the live project when a Supabase access
token is available. Without one they can still run against a throwaway local
PostgreSQL started by db/tests/local_sql_suite.sh — that run needs the *shape*
of the live schema (tables, roles, the helper functions the migrations call),
which is what this generator emits.

    python3 scripts/gen_local_bootstrap.py ~/.raizey-audit/out

Inputs (read-only dump taken 2026-10-08, see docs/PROGRESS.md §6.b):
  12_columns.json     column name / type / nullability / default
  11_defs.json        function definitions lifted verbatim into the stub
  17_settings_keys.json  the settings keys the live project has today

No rows, no identifiers and no secrets from the live project are copied.
"""
import json
import pathlib
import re
import sys

# Tables taken from the snapshot; everything else is hand-written below.
SNAPSHOT_TABLES = [
    "profiles", "settings", "products", "orders", "coupons", "payment_codes",
    "payment_receipts", "wallet_topups", "wallets", "store_settings", "gift_cards",
]

# Helper functions the pending migrations call, lifted verbatim from the live dump
# so the local run exercises the same guard code paths.
STUB_FUNCTIONS = [
    "is_admin", "is_super_admin", "is_banned", "has_admin_permission",
    "append_admin_audit_log", "set_row_updated_at",
    "generate_referral_short_code", "consume_chat_rate_limit", "normalize_tx_ref",
    "validate_payment_code", "check_tx_ref_available",
    # registration validates a referral code while signed out (register.html), so
    # the storefront suite probes it as anon
    "validate_referral_short_code",
]

# Hand-written tables: the snapshot exposes column names but not types for these,
# so they mirror the shape the migrations and the storefront expect.
MANUAL_TABLES = """
-- categories / store_sections / payment_methods / admin tables: the snapshot has
-- these tables (column names) but not their types, so they are written out here.
create table public.categories (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  description        text,
  image_url          text,
  section_id         uuid,
  commission_percent numeric(5,2) not null default 0,
  display_order      integer not null default 0,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now()
);

create table public.store_sections (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  display_order integer not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table public.payment_methods (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  account_info   text,
  instructions   text,
  account_name   text,
  account_number text,
  bin_prefixes   text[],
  bank_key       text,
  display_order  integer not null default 0,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

create table public.admin_permissions (
  profile_id            uuid primary key,
  is_super_admin        boolean not null default false,
  can_manage_orders     boolean not null default false,
  can_manage_wallets    boolean not null default false,
  can_manage_products   boolean not null default false,
  can_manage_settings   boolean not null default false,
  can_manage_maintenance boolean not null default false,
  can_manage_admins     boolean not null default false,
  can_manage_coupons    boolean not null default false,
  can_manage_gift_cards boolean not null default false,
  can_view_audit_logs   boolean not null default false,
  created_by            uuid,
  updated_by            uuid,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table public.admin_audit_logs (
  id           uuid primary key default gen_random_uuid(),
  admin_id     uuid,
  action       text not null,
  target_table text,
  target_id    text,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
""".strip()

HEADER = """-- MEEM STORE — local bootstrap for the SQL probe suites (db/tests/*.sql).
--
-- GENERATED FILE: python3 scripts/gen_local_bootstrap.py ~/.raizey-audit/out
--   → table shapes + helper functions taken from a read-only snapshot of the
--     live schema (2026-10-08) and from db/migrations/*, no live rows.
--
-- It exists so the security/invariant suites can run without a Supabase token:
--   bash db/tests/local_sql_suite.sh
-- The local run checks the migrations + probe SQL against a real PostgreSQL;
-- a green run there is *not* a substitute for the live run with the token.
begin;
"""

FOOTER = """
-- ---------------------------------------------------------------- 6. row level security
-- The live project has RLS on for every public table; the migrations only ADD
-- policies (they never enable RLS), so the stub must enable it here or the
-- probes would silently read everything.
alter table public.profiles            enable row level security;
alter table public.settings            enable row level security;
alter table public.products            enable row level security;
alter table public.categories          enable row level security;
alter table public.store_sections      enable row level security;
alter table public.payment_methods     enable row level security;
alter table public.orders              enable row level security;
alter table public.coupons             enable row level security;
alter table public.payment_codes       enable row level security;
alter table public.payment_receipts    enable row level security;
alter table public.wallet_topups       enable row level security;
alter table public.wallets             enable row level security;
alter table public.store_settings      enable row level security;
alter table public.gift_cards          enable row level security;
alter table public.admin_permissions   enable row level security;
alter table public.admin_audit_logs    enable row level security;

-- the storefront's own read policies (copied from the live dump, so the anon
-- probes see exactly what an anonymous visitor sees)
create policy products_select_active_anon on public.products
  for select to anon using (is_active = true);
create policy products_select_active_authenticated on public.products
  for select to authenticated using (is_active = true or is_admin());
create policy categories_select_active_anon on public.categories
  for select to anon using (is_active = true);
create policy categories_select_active_authenticated on public.categories
  for select to authenticated using (is_active = true or is_admin());
create policy store_sections_select_active_anon on public.store_sections
  for select to anon using (is_active = true);
create policy store_sections_select_authenticated on public.store_sections
  for select to authenticated using (is_active = true or is_admin());
create policy payment_methods_select_active_anon on public.payment_methods
  for select to anon using (is_active = true);
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid() or is_admin());
-- account.html updates its own profiles row directly, so the live project has a
-- self-update policy. Mirrored here with the identity gate only: the live
-- WITH CHECK also calls profile_guard_fields_unchanged(...) to freeze role,
-- is_banned and the loyalty/referral columns, which this stub does not model.
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------- 7. minimal data
-- One admin (super admin) and one plain customer, mirroring the live roles.
insert into public.profiles (id, role, is_banned) values
  ('11111111-1111-1111-1111-111111111111', 'admin', false),
  ('00000000-0000-0000-0000-0000000000aa', 'customer', false);

insert into public.admin_permissions (profile_id, is_super_admin, can_manage_products, can_manage_settings)
values ('11111111-1111-1111-1111-111111111111', true, true, true);

insert into public.store_sections (id, name, display_order, is_active) values
  ('22222222-2222-2222-2222-222222222222', 'الألعاب', 1, true);

insert into public.categories (id, name, section_id, display_order, is_active) values
  ('33333333-3333-3333-3333-333333333333', 'ببجي', '22222222-2222-2222-2222-222222222222', 1, true);

insert into public.products (id, name, price_usd, category_id, is_active, display_order) values
  ('44444444-4444-4444-4444-444444444444', '1000 شدات ببجي', 9.5,  '33333333-3333-3333-3333-333333333333', true, 1),
  ('55555555-5555-5555-5555-555555555555', '2000 شدات ببجي', 18.0, '33333333-3333-3333-3333-333333333333', true, 2),
  ('66666666-6666-6666-6666-666666666666', 'منتج مخفي',      5.0,  '33333333-3333-3333-3333-333333333333', false, 3);

-- orders is the only source of the "most ordered" feed, so seed both states the
-- feed counts ('completed', 'in_progress') plus a pending one it must ignore.
insert into public.orders (user_id, product_id, product_name_snapshot, price_sdg_snapshot, payment_type, status)
select '00000000-0000-0000-0000-0000000000aa', v.product_id, v.product_name, v.price_sdg, 'wallet', v.status
from (values
  ('44444444-4444-4444-4444-444444444444'::uuid, '1000 شدات ببجي', 5500::numeric, 'completed'),
  ('44444444-4444-4444-4444-444444444444'::uuid, '1000 شدات ببجي', 5500::numeric, 'completed'),
  ('44444444-4444-4444-4444-444444444444'::uuid, '1000 شدات ببجي', 5500::numeric, 'in_progress'),
  ('55555555-5555-5555-5555-555555555555'::uuid, '2000 شدات ببجي', 10500::numeric, 'in_progress'),
  ('55555555-5555-5555-5555-555555555555'::uuid, '2000 شدات ببجي', 10500::numeric, 'pending_review'),
  ('66666666-6666-6666-6666-666666666666'::uuid, 'منتج مخفي', 2900::numeric, 'completed'),
  ('66666666-6666-6666-6666-666666666666'::uuid, 'منتج مخفي', 2900::numeric, 'completed'),
  ('66666666-6666-6666-6666-666666666666'::uuid, 'منتج مخفي', 2900::numeric, 'completed')
) as v(product_id, product_name, price_sdg, status);

-- the storefront's own read grants: RLS must stay the only gate
-- (banners is created later by its own migration, which grants it itself)
grant select on all tables in schema public to anon, authenticated;
-- the live project also lets a signed-in user UPDATE their own profiles row
-- (account.html); the profiles_update_own policy is the restriction there.
grant update on public.profiles to authenticated;
grant select on storage.objects, storage.buckets to anon, authenticated;
grant insert, update, delete on storage.objects to authenticated;

commit;
"""


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def column_type(c) -> str:
    """information_schema reports every array column as "ARRAY"; take the
    element type from the default cast (`'{}'::text[]` → text[])."""
    if c["data_type"].upper() != "ARRAY":
        return c["data_type"]
    m = re.search(r"::([a-z_]+)\[\]", c.get("def") or "")
    return f"{m.group(1)}[]" if m else "text[]"


def column_ddl(c) -> str:
    line = f"  {c['column_name']} {column_type(c)}"
    if c["def"]:
        line += f" default {c['def']}"
    if c["is_nullable"] == "NO":
        line += " not null"
    return line


def tables_sql(cols) -> str:
    out = []
    for table in SNAPSHOT_TABLES:
        rows = [c for c in cols if c["table_name"] == table]
        if not rows:
            continue
        body = ",\n".join(column_ddl(c) for c in rows)
        out.append(f"create table public.{table} (\n{body}\n);")
    return "\n\n".join(out)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    snap = pathlib.Path(sys.argv[1])
    cols = json.loads((snap / "12_columns.json").read_text())
    defs = {d["sig"].split("(")[0].strip(): d["def"] for d in json.loads((snap / "11_defs.json").read_text())}

    parts = [HEADER]

    parts.append("""
-- ---------------------------------------------------------------- 1. roles
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon noinherit nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated noinherit nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role noinherit nologin;
  end if;
end $$;

create schema if not exists auth;
create schema if not exists storage;

-- auth.uid(): the same contract as Supabase's helper (request.jwt.claims → sub)
create or replace function auth.uid() returns uuid
language sql stable as $fn$
  select nullif(current_setting('request.jwt.claims', true)::jsonb->>'sub', '')::uuid;
$fn$;

-- ---------------------------------------------------------------- 2. tables
""".strip("\n"))

    parts.append("-- from the live schema snapshot\n" + tables_sql(cols))
    parts.append(MANUAL_TABLES)

    parts.append("""
-- ---------------------------------------------------------------- 3. primary keys
-- (the snapshot lists columns per table; the keys the probes rely on are added here)
alter table public.profiles            add primary key (id);
alter table public.settings            add primary key (key);
alter table public.products            add primary key (id);
alter table public.orders              add primary key (id);
alter table public.coupons             add primary key (id);
alter table public.payment_codes       add primary key (id);
alter table public.payment_receipts    add primary key (id);
alter table public.wallet_topups       add primary key (id);
alter table public.wallets             add primary key (user_id);
alter table public.store_settings      add primary key (id);
alter table public.gift_cards          add primary key (id);

-- ---------------------------------------------------------------- 4. storage shape
create table storage.buckets (
  id                 text primary key,
  name               text not null,
  owner              uuid,
  public             boolean not null default false,
  avif_autodetection boolean not null default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table storage.objects (
  id                 uuid primary key default gen_random_uuid(),
  bucket_id          text references storage.buckets(id),
  name               text,
  owner              uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  last_accessed_at   timestamptz not null default now(),
  metadata           jsonb
);
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;
""".strip("\n"))

    fn_sql = []
    for name in STUB_FUNCTIONS:
        body = defs.get(name)
        if not body:
            fn_sql.append(f"-- missing from the snapshot: {name}")
            continue
        fn_sql.append(body.rstrip(";") + ";")
    parts.append("-- ---------------------------------------------------------------- 5. helpers (verbatim from the live definitions dump)\n"
                 + "\n".join(fn_sql))

    parts.append(FOOTER)
    out = "\n\n".join(parts)
    target = pathlib.Path(__file__).resolve().parent.parent / "db/tests/local_bootstrap.sql"
    target.write_text(out)
    print(f"wrote {target} ({len(out.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
