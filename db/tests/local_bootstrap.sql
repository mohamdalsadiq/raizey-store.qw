-- MEEM STORE — local bootstrap for the SQL probe suites (db/tests/*.sql).
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

-- from the live schema snapshot
create table public.profiles (
  id uuid not null,
  full_name text,
  whatsapp_number text,
  role text default 'customer'::text not null,
  is_banned boolean default false not null,
  created_at timestamp with time zone default now() not null,
  referral_code text,
  referred_by uuid,
  referral_rewarded boolean default false not null,
  milestone10_paid boolean default false not null,
  milestone25_paid boolean default false not null,
  referral_discount_used boolean default false not null,
  loyalty_points integer default 0 not null,
  player_ids jsonb default '{}'::jsonb not null,
  avatar_url text,
  referral_short_code text
);

create table public.settings (
  key text not null,
  value text not null,
  updated_at timestamp with time zone default now() not null
);

create table public.products (
  id uuid default gen_random_uuid() not null,
  category_id uuid,
  name text not null,
  description text,
  image_url text,
  price_usd numeric not null,
  required_fields jsonb default '[]'::jsonb not null,
  is_active boolean default true not null,
  display_order integer default 0 not null,
  created_at timestamp with time zone default now() not null,
  instructions text,
  compare_at_price_usd numeric,
  flash_sale_ends_at timestamp with time zone,
  options jsonb default '[]'::jsonb,
  has_options boolean default false not null,
  delivery_badge_text text
);

create table public.orders (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  product_id uuid,
  product_name_snapshot text not null,
  price_sdg_snapshot numeric not null,
  field_values jsonb default '{}'::jsonb not null,
  payment_type text not null,
  payment_method_id uuid,
  receipt_url text,
  status text default 'pending_review'::text not null,
  rejection_reason text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  transaction_reference text,
  receipt_hash text,
  ocr_status text default 'needs_review'::text,
  amount_verified boolean default false,
  selected_option jsonb,
  coupon_id uuid,
  field_labels jsonb default '{}'::jsonb,
  referral_commission_paid boolean default false,
  refunded boolean default false,
  receipt_id uuid,
  order_code text,
  review_reason text,
  review_severity text
);

create table public.coupons (
  id uuid default gen_random_uuid() not null,
  code text not null,
  discount_percent numeric not null,
  max_uses integer,
  uses_count integer default 0 not null,
  expires_at timestamp with time zone,
  is_active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  min_order_sdg numeric default 0
);

create table public.payment_codes (
  id uuid default gen_random_uuid() not null,
  code text not null,
  amount numeric not null,
  user_id uuid,
  note text,
  status text default 'active'::text not null,
  expires_at timestamp with time zone,
  used_by uuid,
  used_at timestamp with time zone,
  order_id uuid,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.payment_receipts (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  purpose text not null,
  provider text,
  payment_method_id uuid,
  tx_ref_raw text not null,
  tx_ref_norm text not null,
  tx_ref_ocr text,
  receipt_hash text not null,
  receipt_path text,
  amount_expected numeric,
  amount_detected numeric,
  amount_verified boolean default false not null,
  ref_verified boolean default false not null,
  ocr_status text default 'needs_review'::text not null,
  ocr_confidence numeric,
  risk_flags text[] default '{}'::text[] not null,
  ocr_data jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null,
  parent_receipt_id uuid
);

create table public.wallet_topups (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  amount numeric not null,
  payment_method_id uuid,
  receipt_url text,
  status text default 'pending'::text not null,
  rejection_reason text,
  created_at timestamp with time zone default now() not null,
  reviewed_at timestamp with time zone,
  transaction_reference text,
  receipt_hash text,
  ocr_status text default 'needs_review'::text,
  amount_verified boolean default false,
  receipt_id uuid
);

create table public.wallets (
  user_id uuid not null,
  balance numeric default 0 not null,
  updated_at timestamp with time zone default now() not null
);

create table public.store_settings (
  id bigint not null,
  singleton_key boolean default true not null,
  maintenance_mode boolean default false not null,
  maintenance_message text default 'الموقع قيد الصيانة والتحديث حالياً، وسنسعد بخدمتكم مجدداً في أقرب وقت ممكن.'::text not null,
  usd_to_sdg_rate numeric default 0 not null,
  updated_by uuid,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table public.gift_cards (
  id uuid default gen_random_uuid() not null,
  code text not null,
  amount numeric not null,
  is_redeemed boolean default false not null,
  redeemed_by uuid,
  redeemed_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone
);

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

-- ---------------------------------------------------------------- 5. helpers (verbatim from the live definitions dump)
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND COALESCE(is_banned, false) = false
  );
$function$
;
CREATE OR REPLACE FUNCTION public.is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM admin_permissions ap
    JOIN profiles p ON p.id = ap.profile_id
    WHERE ap.profile_id = auth.uid()
      AND ap.is_super_admin = true
      AND p.role = 'admin'
      AND COALESCE(p.is_banned, false) = false
  );
$function$
;
CREATE OR REPLACE FUNCTION public.is_banned()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT is_banned FROM profiles WHERE id = auth.uid()),
    false
  );
$function$
;
CREATE OR REPLACE FUNCTION public.has_admin_permission(permission_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                      SELECT COALESCE(
                                                                                                                                                                                                                                                          (
                                                                                                                                                                                                                                                                SELECT
                                                                                                                                                                                                                                                                        ap.is_super_admin OR
                                                                                                                                                                                                                                                                                CASE permission_key
                                                                                                                                                                                                                                                                                          WHEN 'manage_orders' THEN ap.can_manage_orders
                                                                                                                                                                                                                                                                                                    WHEN 'manage_wallets' THEN ap.can_manage_wallets
                                                                                                                                                                                                                                                                                                              WHEN 'manage_products' THEN ap.can_manage_products
                                                                                                                                                                                                                                                                                                                        WHEN 'manage_settings' THEN ap.can_manage_settings
                                                                                                                                                                                                                                                                                                                                  WHEN 'manage_maintenance' THEN ap.can_manage_maintenance
                                                                                                                                                                                                                                                                                                                                            WHEN 'manage_admins' THEN ap.can_manage_admins
                                                                                                                                                                                                                                                                                                                                                      WHEN 'manage_coupons' THEN ap.can_manage_coupons
                                                                                                                                                                                                                                                                                                                                                                WHEN 'manage_gift_cards' THEN ap.can_manage_gift_cards
                                                                                                                                                                                                                                                                                                                                                                          WHEN 'view_audit_logs' THEN ap.can_view_audit_logs
                                                                                                                                                                                                                                                                                                                                                                                    ELSE false
                                                                                                                                                                                                                                                                                                                                                                                            END
                                                                                                                                                                                                                                                                                                                                                                                                  FROM public.admin_permissions ap
                                                                                                                                                                                                                                                                                                                                                                                                        WHERE ap.profile_id = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                              LIMIT 1
                                                                                                                                                                                                                                                                                                                                                                                                                  ),
                                                                                                                                                                                                                                                                                                                                                                                                                      false
                                                                                                                                                                                                                                                                                                                                                                                                                        );
                                                                                                                                                                                                                                                                                                                                                                                                                        $function$
;
CREATE OR REPLACE FUNCTION public.append_admin_audit_log(p_action text, p_target_table text DEFAULT NULL::text, p_target_id text DEFAULT NULL::text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    v_log_id uuid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      v_admin_id uuid := auth.uid();
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        IF v_admin_id IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                IF NOT public.is_admin() THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    RAISE EXCEPTION 'ADMIN_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        INSERT INTO public.admin_audit_logs (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            admin_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                action,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    target_table,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        target_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            details
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                VALUES (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    v_admin_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        trim(p_action),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            NULLIF(trim(COALESCE(p_target_table, '')), ''),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                NULLIF(trim(COALESCE(p_target_id, '')), ''),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    COALESCE(p_details, '{}'::jsonb)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        RETURNING id INTO v_log_id;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          RETURN v_log_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          END;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          $function$
;
CREATE OR REPLACE FUNCTION public.set_row_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  NEW.updated_at := timezone('utc', now());
    RETURN NEW;
    END;
    $function$
;
CREATE OR REPLACE FUNCTION public.generate_referral_short_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_code text;
  v_attempt integer := 0;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    -- RZY + ثلاث خانات أبجدية رقمية = 6 خانات سهلة العرض.
    v_code := 'RZY' || upper(substr(md5(random()::text || clock_timestamp()::text || v_attempt::text), 1, 3));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE referral_short_code = v_code
    );
    IF v_attempt > 20 THEN
      RAISE EXCEPTION 'referral_code_generation_failed';
    END IF;
  END LOOP;
  RETURN v_code;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.consume_chat_rate_limit(p_rate_key text, p_limit integer DEFAULT 12, p_window_seconds integer DEFAULT 600)
 RETURNS TABLE(allowed boolean, retry_after_seconds integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_limit integer := least(greatest(coalesce(p_limit, 12), 1), 100);
  v_window_seconds integer := least(greatest(coalesce(p_window_seconds, 600), 60), 86400);
  v_window interval;
  v_count integer;
  v_started_at timestamptz;
begin
  if p_rate_key is null or length(p_rate_key) < 16 or length(p_rate_key) > 128 then
    raise exception 'invalid_rate_key';
  end if;

  v_window := make_interval(secs => v_window_seconds);

  insert into private.chat_rate_limits as limits (
    rate_key,
    window_started_at,
    request_count,
    updated_at
  )
  values (p_rate_key, v_now, 1, v_now)
  on conflict (rate_key) do update
  set
    window_started_at = case
      when limits.window_started_at <= v_now - v_window then v_now
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= v_now - v_window then 1
      else limits.request_count + 1
    end,
    updated_at = v_now
  returning request_count, window_started_at
  into v_count, v_started_at;

  allowed := v_count <= v_limit;
  retry_after_seconds := case
    when allowed then 0
    else greatest(
      1,
      ceil(extract(epoch from ((v_started_at + v_window) - v_now)))::integer
    )
  end;
  return next;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.normalize_tx_ref(p_ref text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT NULLIF(regexp_replace(upper(coalesce(p_ref, '')), '[^A-Z0-9]', '', 'g'), '');
$function$
;
CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
 RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_code    RECORD;
  v_norm    text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  v_norm := upper(btrim(coalesce(p_code, '')));
  IF length(v_norm) < 4 THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'cancelled' THEN
    RETURN QUERY SELECT false, 'cancelled'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'used' OR v_code.used_by IS NOT NULL THEN
    RETURN QUERY SELECT false, 'already_used'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'expired'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id THEN
    RETURN QUERY SELECT false, 'not_your_code'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, v_code.amount, v_code.note;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
 RETURNS TABLE(available boolean, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                    DECLARE
                                                                                                                                                                                      v_user_id uuid := auth.uid();
                                                                                                                                                                                        v_norm text;
                                                                                                                                                                                        BEGIN
                                                                                                                                                                                          IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
                                                                                                                                                                                            v_norm := public.normalize_tx_ref(p_tx_ref);
                                                                                                                                                                                              IF v_norm IS NULL OR length(v_norm) < 6 THEN
                                                                                                                                                                                                  RETURN QUERY SELECT false, 'invalid_tx_ref';
                                                                                                                                                                                                      RETURN;
                                                                                                                                                                                                        END IF;
                                                                                                                                                                                                          IF EXISTS (SELECT 1 FROM public.payment_receipts WHERE tx_ref_norm = v_norm)
                                                                                                                                                                                                               OR EXISTS (SELECT 1 FROM public.orders WHERE public.normalize_tx_ref(transaction_reference) = v_norm)
                                                                                                                                                                                                                    OR EXISTS (SELECT 1 FROM public.wallet_topups WHERE public.normalize_tx_ref(transaction_reference) = v_norm) THEN
                                                                                                                                                                                                                        RETURN QUERY SELECT false, 'duplicate_transaction_ref';
                                                                                                                                                                                                                            RETURN;
                                                                                                                                                                                                                              END IF;
                                                                                                                                                                                                                                RETURN QUERY SELECT true, 'available';
                                                                                                                                                                                                                                END;
                                                                                                                                                                                                                                $function$
;
CREATE OR REPLACE FUNCTION public.validate_referral_short_code(p_code text)
 RETURNS TABLE(valid boolean, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_referrer uuid;
BEGIN
  IF length(v_norm) < 5 OR length(v_norm) > 32 THEN
    RETURN QUERY SELECT false, 'invalid_format';
    RETURN;
  END IF;

  SELECT p.id INTO v_referrer
  FROM public.profiles p
  WHERE upper(coalesce(p.referral_short_code, '')) = v_norm
     OR upper(coalesce(p.referral_code, '')) = v_norm
  LIMIT 1;

  IF v_referrer IS NULL THEN
    RETURN QUERY SELECT false, 'not_found';
    RETURN;
  END IF;

  IF auth.uid() IS NOT NULL AND v_referrer = auth.uid() THEN
    RETURN QUERY SELECT false, 'self_referral';
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'valid';
END;
$function$
;


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
