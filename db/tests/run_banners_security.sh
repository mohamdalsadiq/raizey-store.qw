#!/usr/bin/env bash
# Runs every banner security probe in its own ROLLBACK transaction.
#   SUPABASE_ACCESS_TOKEN=<token> bash db/tests/run_banners_security.sh
# Optional: PROJECT_REF (default rglbfizqolrenwfsndyv)
set -uo pipefail
REF="${PROJECT_REF:-rglbfizqolrenwfsndyv}"
TOKEN="${SUPABASE_ACCESS_TOKEN:-$(cat "$HOME/.raizey-audit/live_ro" 2>/dev/null || true)}"
if [ -z "$TOKEN" ]; then echo "no access token available"; exit 2; fi

pass=0; fail=0
probe() { # probe <label> <expect: ERROR|value> <sql>
  local label="$1" expect="$2" sql="$3"
  local body out
  body=$(python3 -c 'import json,sys;print(json.dumps({"query":sys.argv[1]}))' "$sql")
  out=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        --data-binary "$body" "https://api.supabase.com/v1/projects/$REF/database/query")
  local got
  if printf '%s' "$out" | grep -q '"message"'; then got="ERROR"; else
    got=$(python3 -c 'import json,sys;d=json.load(sys.stdin);print(str(d[0].get("v") if d else ""))' <<<"$out" 2>/dev/null || echo "?")
  fi
  if [ "$expect" = "ERROR" ]; then
    if [ "$got" = "ERROR" ]; then printf 'PASS  %s\n' "$label"; pass=$((pass+1));
    else printf 'FAIL  %s (expected an error, got %s)\n' "$label" "$got"; fail=$((fail+1)); fi
  else
    if [ "$got" = "$expect" ]; then printf 'PASS  %s\n' "$label"; pass=$((pass+1));
    else printf 'FAIL  %s (expected %s, got %s)\n' "$label" "$expect" "$got"; fail=$((fail+1)); fi
  fi
}

probe "1 anon sees only active/in-window rows" 3 \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select count(*)::text as v from public.banners; rollback;"
probe "2 anon gets the storefront payload" 3 \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select jsonb_array_length(public.get_banners_public())::text as v; rollback;"
probe "3 anon cannot insert into banners" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; insert into public.banners(image_desktop_url) values ('/assets/img/banner-1-desktop.webp'); select 'inserted' as v; rollback;"
probe "4 anon cannot call admin_save_banner" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.admin_save_banner(null,'{\"image_desktop_url\":\"/assets/img/banner-1-desktop.webp\"}'::jsonb) as v; rollback;"
probe "5 anon cannot call admin_delete_banner" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.admin_delete_banner((select id from public.banners limit 1)) as v; rollback;"
probe "6 anon cannot call banners_validate" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.banners_validate('{\"image_desktop_url\":\"/a.webp\"}'::jsonb) as v; rollback;"
probe "7 non-admin authenticated sees only public rows" 3 \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select count(*)::text as v from public.banners; rollback;"
probe "8 non-admin cannot toggle a banner" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_set_banner_active((select id from public.banners limit 1), false) as v; rollback;"
probe "9 javascript: image url rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"javascript:alert(1)\"}'::jsonb) as v;"
probe "10 protocol-relative url rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"//evil.example/x.webp\"}'::jsonb) as v;"
probe "11 page outside the whitelist rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"/a.webp\",\"link_type\":\"page\",\"link_target\":\"evil.html\"}'::jsonb) as v;"
probe "12 http link rejected (https only)" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"/a.webp\",\"link_type\":\"url\",\"link_target\":\"http://x.example\"}'::jsonb) as v;"
probe "13 image_text without a title rejected" ERROR \
 "select public.banners_validate('{\"banner_style\":\"image_text\",\"image_desktop_url\":\"/a.webp\"}'::jsonb) as v;"
probe "14 over-long title rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"/a.webp\",\"title\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}'::jsonb) as v;"
probe "15 bucket public with 2MB cap" true \
 "select (public and file_size_limit = 2097152)::text as v from storage.buckets where id='banners';"
probe "16 bucket accepts only jpeg/png/webp" true \
 "select (allowed_mime_types <@ array['image/jpeg','image/png','image/webp']::text[] and array['image/jpeg','image/png','image/webp']::text[] <@ allowed_mime_types)::text as v from storage.buckets where id='banners';"
probe "17 no anon write policy on the bucket" 0 \
 "select count(*)::text as v from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'banners%' and cmd in ('INSERT','UPDATE','DELETE') and 'anon' = any(roles);"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
