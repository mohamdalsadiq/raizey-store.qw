#!/usr/bin/env bash
# Runs the icon + homepage-highlight probes in their own ROLLBACK transactions.
#
#   live   SUPABASE_ACCESS_TOKEN=<token> bash db/tests/run_storefront_security.sh
#   local  MEEM_LOCAL_DSN="postgresql://..." bash db/tests/run_storefront_security.sh
#
# The probe index and what each one proves: db/tests/storefront_security.sql
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=probe_lib.sh
. "$HERE/probe_lib.sh"

if [ -z "${MEEM_LOCAL_DSN:-}" ] && [ -z "$(probe_token)" ]; then
  echo "no access token available"; exit 2
fi

# account.html writes profiles directly (full_name / whatsapp_number / player_ids
# / avatar_url) instead of going through an RPC, so the profile policies are the
# only gate there. These two probes are the live confirmation docs asked for.
CUSTOMER_UUID="$(_probe_run "select id::text from public.profiles where role='customer' and coalesce(is_banned,false)=false order by created_at, id limit 1")"
OTHER_UUID="$(_probe_run "select id::text from public.profiles where role='customer' and coalesce(is_banned,false)=false order by created_at desc, id limit 1")"

# ------------------------------------------------------------------ icons bucket
probe "1 category-icons bucket is public with a 200KB cap" true \
 "select (public and file_size_limit = 204800)::text as v from storage.buckets where id='category-icons';"
probe "2 bucket accepts only jpeg/png/webp" true \
 "select (allowed_mime_types @> array['image/jpeg','image/png','image/webp']::text[] and allowed_mime_types <@ array['image/jpeg','image/png','image/webp']::text[])::text as v from storage.buckets where id='category-icons';"
probe "3 no anon write policy on the bucket" 0 \
 "select count(*)::text as v from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'category_icons%' and cmd in ('INSERT','UPDATE','DELETE') and 'anon' = any(roles);"

# ------------------------------------------------------------------ admin RPCs
probe "4 anon cannot call admin_set_section_icon" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.admin_set_section_icon((select id from public.store_sections limit 1),'preset','gamepad-2',null) as v; rollback;"
probe "5 anon cannot call admin_set_category_icon" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.admin_set_category_icon((select id from public.categories limit 1),'preset','gamepad-2',null) as v; rollback;"
probe "6 a non-admin cannot call admin_set_section_icon" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_set_section_icon((select id from public.store_sections limit 1),'preset','gamepad-2',null) as v; rollback;"
probe "7 a non-admin cannot call admin_set_category_icon" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_set_category_icon((select id from public.categories limit 1),'preset','gamepad-2',null) as v; rollback;"
probe "8 anon cannot call icon_fields_validate" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.icon_fields_validate('preset','gamepad-2',null) as v; rollback;"

# ------------------------------------------------------------------ validation rules
probe "9 an unknown icon_mode is rejected" ERROR \
 "select public.icon_fields_validate('holiday','gamepad-2',null) as v;"
probe "10 a malformed preset key is rejected" ERROR \
 "select public.icon_fields_validate('preset','Game Pad!',null) as v;"
probe "11 custom mode without an image is rejected" ERROR \
 "select public.icon_fields_validate('custom',null,null) as v;"
probe "12 a javascript: icon image is rejected" ERROR \
 "select public.icon_fields_validate('custom',null,'javascript:alert(1)') as v;"
probe "13 an off-bucket https icon image is rejected" ERROR \
 "select public.icon_fields_validate('custom',null,'https://evil.example/icon.webp') as v;"
probe "14 a valid preset key is accepted" ok \
 "select public.icon_fields_validate('preset','gamepad-2',null); select 'ok' as v;"

# ------------------------------------------------------------------ columns + capability
probe "15 the three icon columns exist on both tables" 6 \
 "select count(*)::text as v from information_schema.columns where table_schema='public' and table_name in ('store_sections','categories') and column_name in ('icon_mode','icon_key','icon_image_url');"
probe "16 icon_mode defaults to auto" 2 \
 "select count(*)::text as v from information_schema.columns where table_schema='public' and table_name in ('store_sections','categories') and column_name = 'icon_mode' and column_default = '''auto''::text';"
probe "17 the capability markers were seeded" 2 \
 "select count(*)::text as v from public.settings where key in ('catalog_icons_flag','home_highlights_flag');"
probe "17.b row level security is on for settings" true \
 "select relrowsecurity::text as v from pg_class where oid = 'public.settings'::regclass;"
probe "18 no non-whitelisted settings key is visible to anon" 0 \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select count(*)::text as v from public.settings where key not in ('usd_to_sdg_rate','profit_margin_percent','referral_signup_discount_percent','whatsapp_number','banner_mobile_ratio','banner_autoplay','banner_interval','banner_effect','offers_use_flag','catalog_icons_flag','home_highlights_flag'); rollback;"

# ------------------------------------------------------------------ most-ordered feed
probe_ok "19 anon can read the most-ordered feed" \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select jsonb_array_length(public.get_top_ordered_products(8)) as v; rollback;"
# deliberately runs as the owner: an anon join would have inactive products
# filtered out by the products policy and the probe would pass for free.
probe "20 the feed never returns an inactive product" 0 \
 "select count(*)::text as v
  from jsonb_array_elements(public.get_top_ordered_products(24)) e
  join public.products p on p.id = (e->>'id')::uuid
  where p.is_active = false;"
probe "21 the feed honours the requested limit" true \
 "select (jsonb_array_length(public.get_top_ordered_products(2)) <= 2)::text as v;"
probe "22 the feed caps a huge limit at 24" true \
 "select (jsonb_array_length(public.get_top_ordered_products(999)) <= 24)::text as v;"
probe "23 every ordered number equals a real aggregate" true \
 "select (not exists (
    select 1 from jsonb_array_elements(public.get_top_ordered_products(24)) e
    where (e->>'ordered')::int <> (
      select count(*) from public.orders o
      where o.product_id = (e->>'id')::uuid and o.status in ('completed','in_progress'))
  ))::text as v;"

# ------------------------------------------------- 24. profile self-service writes
case "$CUSTOMER_UUID" in
  [0-9a-fA-F]*-*-*-*-*) has_customer=1 ;;
  *) has_customer=0 ;;
esac
if [ "$has_customer" = "1" ]; then
  probe "24 a signed-in customer can update their own profile" 1 \
   "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"$CUSTOMER_UUID\"}';
    with u as (update public.profiles set full_name = coalesce(full_name,'probe') where id = '$CUSTOMER_UUID' returning 1)
    select count(*)::text as v from u;
    rollback;"
  # registration validates the referral code while the visitor is still signed
  # out; if this call fails the page blocks account creation (real bug found and
  # fixed on 2026-10-14, see db/migrations/2026-10-14_referral_code_check_for_anon.sql)
  probe_ok "27 anon can validate a referral code" \
   "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
    select valid::text as v from public.validate_referral_short_code('MEEMZZZZZZZZ');
    rollback;"
  probe "28 an unknown referral code reports not_found" "false/not_found" \
   "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
    select (v.valid::text || '/' || v.reason) as v from public.validate_referral_short_code('MEEMZZZZZZZZ') v;
    rollback;"
  probe_any "25 anon reads no profile row (no GRANT on live, zero rows locally)" \
   "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
    select count(*)::text as v from public.profiles;
    rollback;" ERROR 0
  if [ "$OTHER_UUID" != "$CUSTOMER_UUID" ]; then
    probe "26 a customer cannot change another customer's profile" 0 \
     "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"$CUSTOMER_UUID\"}';
      with u as (update public.profiles set full_name = coalesce(full_name,'probe') where id = '$OTHER_UUID' returning 1)
      select count(*)::text as v from u;
      rollback;"
  else
    skip "26 a customer cannot change another profile" "only one customer profile exists"
  fi
else
  skip "24-26 profile self-service writes" "no customer profile"
fi

printf '\n%s passed, %s failed, %s skipped\n' "$probe_pass" "$probe_fail" "$probe_skip"
[ "$probe_fail" -eq 0 ]
