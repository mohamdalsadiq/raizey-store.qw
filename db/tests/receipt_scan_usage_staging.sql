-- Isolated staging only. No AI calls; every fixture is rolled back.
-- Single-session admission assertions are not a multi-connection load test.
DO $test$
DECLARE
 fixture_users uuid[]:=ARRAY[]::uuid[]; leases uuid[]:=ARRAY[]::uuid[];
 u uuid; sid uuid; lease uuid; ticket uuid; r jsonb; s jsonb;
 h text; context text; blocked boolean; checks integer:=0; i integer;
BEGIN
 BEGIN
  IF (SELECT concurrency_limit FROM private.receipt_scan_policy WHERE id)<>50 THEN RAISE EXCEPTION 'FAIL concurrency configuration'; END IF; checks:=checks+1;
  FOR i IN 1..51 LOOP
   u:=gen_random_uuid(); fixture_users:=array_append(fixture_users,u);
   INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES(u,'receipt-usage-fixture-'||u::text||'@example.invalid','{}');
   r:=public.begin_receipt_scan_usage(u,lpad(to_hex(i),64,'0'),lpad(to_hex(i+1000),64,'0'));
   IF i<=50 THEN
    IF r->>'allowed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'FAIL immediate admission %: %',i,r; END IF;
    leases:=array_append(leases,(r->>'leaseId')::uuid);
   ELSE
    IF r->>'reason' IS DISTINCT FROM 'receipt_queued' THEN RAISE EXCEPTION 'FAIL overflow'; END IF;
    ticket:=(r->>'ticketId')::uuid;
   END IF;
  END LOOP;
  checks:=checks+2;
  IF (SELECT count(*) FROM private.receipt_scan_jobs WHERE user_id=ANY(fixture_users) AND status='active')<>50 THEN RAISE EXCEPTION 'FAIL active ceiling'; END IF; checks:=checks+1;
  r:=public.begin_receipt_scan_usage(fixture_users[1],lpad(to_hex(1),64,'0'),lpad(to_hex(1001),64,'0'));
  IF r->>'reason' IS DISTINCT FROM 'receipt_scan_in_progress' THEN RAISE EXCEPTION 'FAIL duplicate in-flight'; END IF; checks:=checks+1;
  PERFORM public.finish_receipt_scan_usage(fixture_users[1],leases[1],NULL);
  r:=public.get_receipt_scan_usage(fixture_users[1]);
  IF (r->>'remaining')::integer<>5 THEN RAISE EXCEPTION 'FAIL technical refund'; END IF; checks:=checks+1;
  r:=public.poll_receipt_scan_usage(fixture_users[51],ticket);
  IF r->>'canRetry' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'FAIL queue resumption'; END IF; checks:=checks+1;
  blocked:=false;
  BEGIN PERFORM public.poll_receipt_scan_usage(fixture_users[1],ticket); EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='scan_ticket_not_found' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL ticket ownership'; END IF; checks:=checks+1;
  r:=public.begin_receipt_scan_usage(fixture_users[51],lpad(to_hex(51),64,'0'),lpad(to_hex(1051),64,'0'));
  IF r->>'allowed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'FAIL ticket admission'; END IF; checks:=checks+1;
  lease:=(r->>'leaseId')::uuid;
  FOR i IN 1..12 LOOP
   IF public.meter_receipt_scan_usage(fixture_users[51],lease) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL call metering'; END IF;
  END LOOP;
  IF public.meter_receipt_scan_usage(fixture_users[51],lease) IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL retry cap'; END IF; checks:=checks+1;
  PERFORM public.finish_receipt_scan_usage(fixture_users[51],lease,NULL);
  IF (SELECT calls FROM private.receipt_scan_provider_days WHERE quota_day=(clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date)<>12 THEN RAISE EXCEPTION 'FAIL provider refund incorrectly erased actual calls'; END IF; checks:=checks+1;
  FOR i IN 2..50 LOOP PERFORM public.finish_receipt_scan_usage(fixture_users[i],leases[i],NULL); END LOOP;

  -- Three distinct, server-confirmed unrelated images freeze only scanning.
  FOR i IN 1..3 LOOP
   h:=lpad(to_hex(2000+i),64,'0');context:=lpad(to_hex(3000+i),64,'0');
   r:=public.begin_receipt_scan_usage(fixture_users[1],h,context);lease:=(r->>'leaseId')::uuid;sid:=gen_random_uuid();
   INSERT INTO public.receipt_scan_results(id,user_id,receipt_hash,image_bytes,mime_type,decision,ocr_status,submission_allowed,expires_at,ocr_data)
   VALUES(sid,fixture_users[1],h,69,'image/png','reject','rejected',false,clock_timestamp()+interval '30 minutes',jsonb_build_object('usage_lease_id',lease,'usage_context_key',context,'receipt_policy','mandatory-visual-v1','completed_machine_check',true,'non_receipt_confirmed',true));
   r:=public.finish_receipt_scan_usage(fixture_users[1],lease,sid);
   s:=public.finish_receipt_scan_usage(fixture_users[1],lease,sid);
   IF (r->>'violations')::integer<>i OR (s->>'violations')::integer<>i OR (s->>'remaining')::integer<>(5-i) THEN RAISE EXCEPTION 'FAIL duplicate completion'; END IF;
  END LOOP;checks:=checks+1;
  IF r->>'suspended' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'FAIL abuse suspension'; END IF; checks:=checks+1;
  IF public.validate_receipt_scan_usage(fixture_users[1],sid) IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL suspended cached proof'; END IF; checks:=checks+1;
  r:=public.begin_receipt_scan_usage(fixture_users[1],repeat('a',64),repeat('b',64));
  IF r->>'reason' IS DISTINCT FROM 'receipt_feature_suspended' THEN RAISE EXCEPTION 'FAIL suspended admission'; END IF; checks:=checks+1;
  IF (SELECT is_banned FROM public.profiles WHERE id=fixture_users[1]) OR (SELECT balance FROM public.wallets WHERE user_id=fixture_users[1])<>0 THEN RAISE EXCEPTION 'FAIL incorrect full-account penalty'; END IF; checks:=checks+1;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',fixture_users[1],'role','authenticated','aal','aal1')::text,true);
  SET LOCAL ROLE authenticated;
  blocked:=false;
  BEGIN PERFORM * FROM private.receipt_scan_jobs; EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL customer reads counters'; END IF; checks:=checks+1;
  blocked:=false;
  BEGIN PERFORM public.begin_receipt_scan_usage(fixture_users[1],repeat('a',64),repeat('b',64)); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL customer forges usage lease'; END IF; checks:=checks+1;
  blocked:=false;
  BEGIN PERFORM public.admin_set_receipt_scan_suspension(fixture_users[1],false,'TEST unauthorized release'); EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='access_denied' THEN blocked:=true; ELSE RAISE; END IF;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL customer releases suspension'; END IF; checks:=checks+1;
  RESET ROLE;
  -- This intentional exception rolls back all users, jobs, scans and counters.
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='fixture_complete';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN
  IF checks<>19 THEN RAISE EXCEPTION 'FAIL incomplete staging checks: %',checks; END IF;
 END;
 IF EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(fixture_users)) OR EXISTS(SELECT 1 FROM private.receipt_scan_jobs WHERE user_id=ANY(fixture_users)) THEN RAISE EXCEPTION 'FAIL fixture cleanup'; END IF;
END $test$;
SELECT '19 live staging scan-usage checks passed; all fixtures rolled back; no AI calls' AS result;
