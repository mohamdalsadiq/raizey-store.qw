#!/usr/bin/env bash
# Runs every banner security probe in its own ROLLBACK transaction.
#
#   live   SUPABASE_ACCESS_TOKEN=<token> bash db/tests/run_banners_security.sh
#          optional: PROJECT_REF (default rglbfizqolrenwfsndyv)
#   local  MEEM_LOCAL_DSN="postgresql://..." bash db/tests/run_banners_security.sh
#          (started by db/tests/local_sql_suite.sh)
#
# The probe index and what each one proves: db/tests/banners_security.sql
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=probe_lib.sh
. "$HERE/probe_lib.sh"

if [ -z "${MEEM_LOCAL_DSN:-}" ] && [ -z "$(probe_token)" ]; then
  echo "no access token available"; exit 2
fi

# ------------------------------------------------------------------ 1. visibility
probe "1 anon sees only active/in-window rows" 3 \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select count(*)::text as v from public.banners; rollback;"
probe "2 anon gets the storefront payload" 3 \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select jsonb_array_length(public.get_banners_public())::text as v; rollback;"
probe "3 anon cannot insert into banners" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; insert into public.banners(image_desktop_url) values ('/assets/banners/banner-1-desktop.webp'); select 'inserted' as v; rollback;"
probe "4 anon cannot call admin_save_banner" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.admin_save_banner(null,'{\"image_desktop_url\":\"/assets/banners/banner-1-desktop.webp\"}'::jsonb) as v; rollback;"
probe "5 anon cannot call admin_delete_banner" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.admin_delete_banner((select id from public.banners limit 1)) as v; rollback;"
probe "6 anon cannot call banners_validate" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.banners_validate('{\"image_desktop_url\":\"/assets/banners/a.webp\"}'::jsonb) as v; rollback;"
probe "7 non-admin authenticated sees only public rows" 3 \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select count(*)::text as v from public.banners; rollback;"
probe "8 non-admin cannot toggle a banner" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_set_banner_active((select id from public.banners limit 1), false) as v; rollback;"

# ------------------------------------------------------------------ 2. link validation
probe "9 javascript: image url rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"javascript:alert(1)\"}'::jsonb) as v;"
probe "10 protocol-relative url rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"//evil.example/x.webp\"}'::jsonb) as v;"
probe "11 page outside the whitelist rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"/assets/banners/a.webp\",\"link_type\":\"page\",\"link_target\":\"evil.html\"}'::jsonb) as v;"
probe "12 http link rejected (https only)" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"/assets/banners/a.webp\",\"link_type\":\"url\",\"link_target\":\"http://x.example\"}'::jsonb) as v;"
probe "13 image_text without a title rejected" ERROR \
 "select public.banners_validate('{\"banner_style\":\"image_text\",\"image_desktop_url\":\"/assets/banners/a.webp\"}'::jsonb) as v;"
probe "14 over-long title rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"/assets/banners/a.webp\",\"title\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}'::jsonb) as v;"

# ------------------------------------------------------------------ 3. bucket
probe "15 bucket public with 2MB cap" true \
 "select (public and file_size_limit = 2097152)::text as v from storage.buckets where id='banners';"
probe "16 bucket accepts only jpeg/png/webp" true \
 "select (allowed_mime_types <@ array['image/jpeg','image/png','image/webp']::text[] and array['image/jpeg','image/png','image/webp']::text[] <@ allowed_mime_types)::text as v from storage.buckets where id='banners';"
probe "17 no anon write policy on the bucket" 0 \
 "select count(*)::text as v from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'banners%' and cmd in ('INSERT','UPDATE','DELETE') and 'anon' = any(roles);"
probe "17.b row level security is on for banners" true \
 "select relrowsecurity::text as v from pg_class where oid = 'public.banners'::regclass;"

# ------------------------------------------------------------------ 4. drafts + scheduling (MASTER_SPEC §1ح)
probe "18 draft/future/expired/inactive rows stay hidden, the live one shows" true \
 "begin;
  insert into public.banners (id,banner_style,status,title,subtitle,cta_text,alt_text,image_desktop_url,link_type,sort_order,is_active,starts_at,ends_at) values
   ('00000000-0000-0000-0000-0000000000d1','image_only','draft',null,null,null,'probe-draft','/assets/banners/probe-draft.webp','none',900,true,null,null),
   ('00000000-0000-0000-0000-0000000000d2','image_only','published',null,null,null,'probe-future','/assets/banners/probe-future.webp','none',901,true,now() + interval '2 days',null),
   ('00000000-0000-0000-0000-0000000000d3','image_only','published',null,null,null,'probe-expired','/assets/banners/probe-expired.webp','none',902,true,null,now() - interval '2 days'),
   ('00000000-0000-0000-0000-0000000000d4','image_only','published',null,null,null,'probe-off','/assets/banners/probe-off.webp','none',903,false,null,null),
   ('00000000-0000-0000-0000-0000000000d5','image_only','published',null,null,null,'probe-live','/assets/banners/probe-live.webp','none',904,true,null,null);
  set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select (count(*) filter (where alt_text like 'probe-%') = 1
      and coalesce(bool_or(alt_text = 'probe-live'), false))::text as v
  from public.banners;
  rollback;"
probe "19 get_banners_public() drops the same rows" true \
 "begin;
  insert into public.banners (id,banner_style,status,title,subtitle,cta_text,alt_text,image_desktop_url,link_type,sort_order,is_active,starts_at,ends_at) values
   ('00000000-0000-0000-0000-0000000000d1','image_only','draft',null,null,null,'probe-draft','/assets/banners/probe-draft.webp','none',900,true,null,null),
   ('00000000-0000-0000-0000-0000000000d3','image_only','published',null,null,null,'probe-expired','/assets/banners/probe-expired.webp','none',902,true,null,now() - interval '2 days'),
   ('00000000-0000-0000-0000-0000000000d5','image_only','published',null,null,null,'probe-live','/assets/banners/probe-live.webp','none',904,true,null,null);
  set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select ((public.get_banners_public())::text not ilike '%probe-draft%'
      and (public.get_banners_public())::text not ilike '%probe-expired%'
      and (public.get_banners_public())::text ilike '%probe-live%')::text as v;
  rollback;"

# ------------------------------------------------------------------ 5. no writes for non-admins (MASTER_SPEC §1ح)
probe "20 non-admin cannot copy a banner" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_copy_banner((select id from public.banners limit 1)) as v; rollback;"
probe "21 non-admin cannot change the status" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_set_banner_status((select id from public.banners limit 1),'draft') as v; rollback;"
probe "22 non-admin cannot reorder banners" ERROR \
 "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"00000000-0000-0000-0000-0000000000aa\"}'; select public.admin_reorder_banners(jsonb_build_array((select id from public.banners order by sort_order, id limit 1))) as v; rollback;"
probe "23 anon cannot call the image-url helper" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}'; select public.banners_validate_image_url('/assets/banners/a.webp') as v; rollback;"

# ------------------------------------------------------------------ 6. image scope v2 (repo folder or the project's own bucket only)
probe "24 an arbitrary https host is rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"https://evil.example/x.webp\"}'::jsonb) as v;"
probe "25 a data: image url is rejected" ERROR \
 "select public.banners_validate('{\"image_desktop_url\":\"data:image/webp;base64,AAAA\"}'::jsonb) as v;"
probe "26 the project's own bucket url is accepted" true \
 "select public.banners_validate_image_url('https://rglbfizqolrenwfsndyv.supabase.co/storage/v1/object/public/banners/x.webp')::text as v;"
probe "27 publishing without alt_text is rejected" ERROR \
 "select public.banners_validate('{\"status\":\"published\",\"image_desktop_url\":\"/assets/banners/a.webp\",\"alt_text\":\"   \"}'::jsonb) as v;"

# ------------------------------------------------------------------ 7. admin paths (need a real admin identity)
ADMIN_UUID="$(_probe_run "select id::text from public.profiles where role = 'admin' and coalesce(is_banned,false) = false order by created_at, id limit 1")"
case "$ADMIN_UUID" in
  [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*) is_admin_identity=1 ;;
  *) is_admin_identity=0 ;;
esac

if [ "$is_admin_identity" = "1" ]; then
  probe "28 admin can create a draft slide" true \
   "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"$ADMIN_UUID\"}';
    select (public.admin_save_banner(null,'{\"status\":\"draft\",\"image_desktop_url\":\"/assets/banners/probe-new.webp\",\"alt_text\":\"probe\"}'::jsonb) is not null)::text as v;
    rollback;"
  # NB: the copy is verified in a *following* statement — a data-modifying CTE
  # is not visible to the rest of its own statement.
  probe "29 copying a banner always lands as a new draft" true \
   "begin; set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"$ADMIN_UUID\"}';
    select public.admin_copy_banner(
      (select id from public.banners where status = 'published' order by sort_order, id limit 1)) is not null;
    select (select (b.status = 'draft' and b.is_active = false)::text
            from public.banners b
            where b.sort_order = (select max(sort_order) from public.banners)) as v;
    rollback;"
  probe "30 publishing a slide without alt_text is rejected" ERROR \
   "begin;
    insert into public.banners (id,banner_style,status,alt_text,image_desktop_url,link_type,sort_order,is_active)
      values ('00000000-0000-0000-0000-0000000000e1','image_only','draft','','/assets/banners/probe-noalt.webp','none',910,true);
    set local role authenticated; set local request.jwt.claims='{\"role\":\"authenticated\",\"sub\":\"$ADMIN_UUID\"}';
    select public.admin_set_banner_status('00000000-0000-0000-0000-0000000000e1','published') as v;
    rollback;"
  probe "31 admin reorder applies the whole order in one call" true \
   "begin;
    set local request.jwt.claims='{\"role\":\"postgres\",\"sub\":\"$ADMIN_UUID\"}';
    create temp table t_order as
      select jsonb_agg(id order by sort_order desc, id) as arr from public.banners;
    select public.admin_reorder_banners((select arr from t_order));
    select ((select count(distinct sort_order) from public.banners) = (select count(*) from public.banners)
        and (select min(sort_order) from public.banners) = 1
        and (select max(sort_order) from public.banners) = (select count(*) from public.banners)
        and (select b.sort_order from public.banners b where b.id = ((select arr from t_order) ->> 0)::uuid) = 1)::text as v;
    rollback;"
  probe "32 a duplicate order is rejected and nothing moves" true \
   "begin;
    create temp table t_before as select id, sort_order from public.banners;
    set local request.jwt.claims='{\"role\":\"postgres\",\"sub\":\"$ADMIN_UUID\"}';
    do \$\$ begin
      begin
        perform public.admin_reorder_banners(jsonb_build_array(
          (select id from public.banners order by sort_order, id limit 1),
          (select id from public.banners order by sort_order, id limit 1)));
      exception when others then null;
      end;
    end \$\$;
    select (not exists (select 1 from public.banners b join t_before t using (id)
                        where b.sort_order is distinct from t.sort_order))::text as v;
    rollback;"
else
  skip "28-32 admin create/copy/publish/atomic-reorder" "no usable admin identity in profiles"
fi

printf '\n%s passed, %s failed, %s skipped\n' "$probe_pass" "$probe_fail" "$probe_skip"
[ "$probe_fail" -eq 0 ]
