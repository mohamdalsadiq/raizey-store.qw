-- Staging candidate: apply only after the composed database and Edge tests pass.
BEGIN;
CREATE TABLE IF NOT EXISTS private.receipt_scan_policy (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 user_daily_limit integer NOT NULL DEFAULT 5 CHECK(user_daily_limit BETWEEN 1 AND 20),
 global_daily_limit integer NOT NULL DEFAULT 1000 CHECK(global_daily_limit BETWEEN 1 AND 20000),
 provider_daily_limit integer NOT NULL DEFAULT 2500 CHECK(provider_daily_limit BETWEEN 1 AND 50000),
 concurrency_limit integer NOT NULL DEFAULT 50 CHECK(concurrency_limit BETWEEN 1 AND 50),
 violation_limit integer NOT NULL DEFAULT 3 CHECK(violation_limit BETWEEN 2 AND 10)
);
INSERT INTO private.receipt_scan_policy(id) VALUES(true) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS private.receipt_scan_accounts (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 generation uuid NOT NULL DEFAULT gen_random_uuid(),
 suspended_at timestamptz,
 reset_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS private.receipt_scan_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 context_key text NOT NULL CHECK(context_key ~ '^[a-f0-9]{64}$'), receipt_hash text NOT NULL CHECK(receipt_hash ~ '^[a-f0-9]{64}$'),
 quota_day date NOT NULL, status text NOT NULL CHECK(status IN ('queued','active','completed','failed')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz NOT NULL,
 started_at timestamptz, finished_at timestamptz, scan_id uuid REFERENCES public.receipt_scan_results(id) ON DELETE SET NULL,
 provider_calls integer NOT NULL DEFAULT 0 CHECK(provider_calls BETWEEN 0 AND 12)
);
CREATE UNIQUE INDEX IF NOT EXISTS receipt_scan_one_pending_user ON private.receipt_scan_jobs(user_id) WHERE status IN ('queued','active');
CREATE INDEX IF NOT EXISTS receipt_scan_jobs_day ON private.receipt_scan_jobs(quota_day,status);
CREATE INDEX IF NOT EXISTS receipt_scan_jobs_user_day ON private.receipt_scan_jobs(user_id,quota_day,status);
CREATE TABLE IF NOT EXISTS private.receipt_scan_provider_days (
 quota_day date PRIMARY KEY, calls integer NOT NULL DEFAULT 0 CHECK(calls>=0)
);
CREATE TABLE IF NOT EXISTS private.receipt_scan_violations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 generation uuid NOT NULL,receipt_hash text NOT NULL,job_id uuid NOT NULL REFERENCES private.receipt_scan_jobs(id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(user_id,generation,receipt_hash),UNIQUE(job_id)
);
ALTER TABLE private.receipt_scan_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.receipt_scan_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.receipt_scan_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.receipt_scan_provider_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.receipt_scan_violations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.receipt_scan_policy,private.receipt_scan_accounts,private.receipt_scan_jobs,private.receipt_scan_provider_days,private.receipt_scan_violations FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA private TO service_role;

CREATE OR REPLACE FUNCTION private.receipt_scan_state(p_user uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE d date := (clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date; p private.receipt_scan_policy%ROWTYPE; a private.receipt_scan_accounts%ROWTYPE; used_n integer; strikes integer;
BEGIN
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id;
 SELECT * INTO a FROM private.receipt_scan_accounts WHERE user_id=p_user;
 SELECT count(*) INTO used_n FROM private.receipt_scan_jobs WHERE user_id=p_user AND quota_day=d
  AND (status='completed' OR (status='active' AND expires_at>clock_timestamp()));
 SELECT count(*) INTO strikes FROM private.receipt_scan_violations WHERE user_id=p_user AND generation=a.generation AND created_at>=clock_timestamp()-interval '7 days';
 RETURN jsonb_build_object('dailyLimit',p.user_daily_limit,'usedToday',used_n,'remaining',greatest(0,p.user_daily_limit-used_n),
  'violations',strikes,'violationLimit',p.violation_limit,'suspended',a.suspended_at IS NOT NULL,
  'resetAt',((d+1)::timestamp AT TIME ZONE 'Africa/Khartoum'),'timezone','Africa/Khartoum');
END $$;

CREATE OR REPLACE FUNCTION private.begin_receipt_scan(p_user uuid,p_hash text,p_context text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p private.receipt_scan_policy%ROWTYPE; j private.receipt_scan_jobs%ROWTYPE; s jsonb; d date:=(clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date; running_n integer; global_n integer; cached_scan uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND NOT is_banned) THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_context !~ '^[a-f0-9]{64}$' OR p_hash IS NULL OR p_context IS NULL THEN RAISE EXCEPTION 'invalid_scan_context'; END IF;
 -- This short lock serializes admission, provider metering, completion and admin reset.
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id FOR UPDATE;
 UPDATE private.receipt_scan_jobs SET status='failed',finished_at=clock_timestamp() WHERE status IN ('queued','active') AND expires_at<=clock_timestamp();
 UPDATE private.receipt_scan_jobs q SET status='failed',finished_at=clock_timestamp() WHERE q.status='queued' AND (
  EXISTS(SELECT 1 FROM private.receipt_scan_accounts a WHERE a.user_id=q.user_id AND a.suspended_at IS NOT NULL) OR
  NOT EXISTS(SELECT 1 FROM public.profiles pr WHERE pr.id=q.user_id AND NOT pr.is_banned) OR
  (SELECT count(*) FROM private.receipt_scan_jobs z WHERE z.user_id=q.user_id AND z.quota_day=d AND z.status IN ('completed','active'))>=p.user_daily_limit);
 INSERT INTO private.receipt_scan_accounts(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 s:=private.receipt_scan_state(p_user);
 IF (s->>'suspended')::boolean THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_feature_suspended','usage',s); END IF;
 -- Close the cache/admission race: a request that finished while the caller was
 -- reading its cache cannot create a second paid run for the same context.
 SELECT r.id INTO cached_scan FROM private.receipt_scan_jobs q JOIN public.receipt_scan_results r ON r.id=q.scan_id
 WHERE q.user_id=p_user AND q.context_key=p_context AND q.receipt_hash=p_hash AND q.status='completed'
 AND r.user_id=p_user AND r.claimed_at IS NULL AND r.expires_at>clock_timestamp()
 AND r.ocr_data->>'usage_lease_id'=q.id::text AND r.ocr_data->>'usage_context_key'=p_context
 AND r.ocr_data->>'receipt_policy'='mandatory-visual-v1' ORDER BY r.created_at DESC LIMIT 1;
 IF cached_scan IS NOT NULL THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_cached','scanId',cached_scan,'usage',s); END IF;
 SELECT * INTO j FROM private.receipt_scan_jobs WHERE user_id=p_user AND status IN ('queued','active') FOR UPDATE;
 IF FOUND AND j.context_key IS DISTINCT FROM p_context THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_scan_in_progress','usage',s); END IF;
 IF j.status='active' THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_scan_in_progress','usage',s); END IF;
 IF (s->>'remaining')::integer<=0 THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_daily_limit','usage',s); END IF;
 SELECT count(*) INTO global_n FROM private.receipt_scan_jobs WHERE quota_day=d AND started_at IS NOT NULL;
 IF global_n>=p.global_daily_limit THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_store_daily_limit','usage',s); END IF;
 IF COALESCE((SELECT calls FROM private.receipt_scan_provider_days WHERE quota_day=d),0)>=p.provider_daily_limit THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_provider_daily_limit','usage',s); END IF;
 IF j.id IS NULL THEN
  IF (SELECT count(*) FROM private.receipt_scan_jobs WHERE status='queued')>=200 THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_queue_full','usage',s); END IF;
  INSERT INTO private.receipt_scan_jobs(user_id,context_key,receipt_hash,quota_day,status,expires_at)
    VALUES(p_user,p_context,p_hash,d,'queued',clock_timestamp()+interval '15 minutes') RETURNING * INTO j;
 END IF;
 SELECT count(*) INTO running_n FROM private.receipt_scan_jobs WHERE status='active';
 IF running_n>=p.concurrency_limit OR EXISTS(SELECT 1 FROM private.receipt_scan_jobs WHERE status='queued' AND (created_at,id)<(j.created_at,j.id)) THEN
  RETURN jsonb_build_object('allowed',false,'reason','receipt_queued','ticketId',j.id,'position',(SELECT count(*) FROM private.receipt_scan_jobs WHERE status='queued' AND (created_at,id)<=(j.created_at,j.id)),'retryAfter',3,'usage',s);
 END IF;
 UPDATE private.receipt_scan_jobs SET status='active',quota_day=d,started_at=clock_timestamp(),expires_at=clock_timestamp()+interval '5 minutes' WHERE id=j.id;
 RETURN jsonb_build_object('allowed',true,'leaseId',j.id,'usage',private.receipt_scan_state(p_user));
END $$;

CREATE OR REPLACE FUNCTION private.poll_receipt_scan(p_user uuid,p_ticket uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j private.receipt_scan_jobs%ROWTYPE;p private.receipt_scan_policy%ROWTYPE;s jsonb;
BEGIN
 SELECT * INTO j FROM private.receipt_scan_jobs WHERE id=p_ticket AND user_id=p_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'scan_ticket_not_found'; END IF;
 s:=private.receipt_scan_state(p_user);
 IF (s->>'suspended')::boolean THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_feature_suspended','usage',s); END IF;
 IF j.expires_at<=clock_timestamp() OR j.status NOT IN ('queued','active') THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_queue_expired','usage',s); END IF;
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id;
 RETURN jsonb_build_object('allowed',false,'reason','receipt_queued','ticketId',j.id,'retryAfter',3,
 'canRetry',j.status='queued' AND (SELECT count(*) FROM private.receipt_scan_jobs WHERE status='active' AND expires_at>clock_timestamp())<p.concurrency_limit AND NOT EXISTS(SELECT 1 FROM private.receipt_scan_jobs WHERE status='queued' AND expires_at>clock_timestamp() AND (created_at,id)<(j.created_at,j.id)),
 'position',(SELECT count(*) FROM private.receipt_scan_jobs WHERE status='queued' AND expires_at>clock_timestamp() AND (created_at,id)<=(j.created_at,j.id)),'usage',s);
END $$;

CREATE OR REPLACE FUNCTION private.meter_receipt_scan(p_user uuid,p_lease uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p private.receipt_scan_policy%ROWTYPE;j private.receipt_scan_jobs%ROWTYPE;d date:=(clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date;
BEGIN
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id FOR UPDATE;
 SELECT * INTO j FROM private.receipt_scan_jobs WHERE id=p_lease AND user_id=p_user FOR UPDATE;
 IF NOT FOUND OR j.status<>'active' OR j.expires_at<=clock_timestamp() OR j.provider_calls>=12 OR EXISTS(SELECT 1 FROM private.receipt_scan_accounts WHERE user_id=p_user AND suspended_at IS NOT NULL) OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND NOT is_banned) THEN RETURN false; END IF;
 INSERT INTO private.receipt_scan_provider_days(quota_day) VALUES(d) ON CONFLICT DO NOTHING;
 IF (SELECT calls FROM private.receipt_scan_provider_days WHERE quota_day=d)>=p.provider_daily_limit THEN RETURN false; END IF;
 UPDATE private.receipt_scan_provider_days SET calls=calls+1 WHERE quota_day=d;
 UPDATE private.receipt_scan_jobs SET provider_calls=provider_calls+1 WHERE id=j.id;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION private.finish_receipt_scan(p_user uuid,p_lease uuid,p_scan uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p private.receipt_scan_policy%ROWTYPE;j private.receipt_scan_jobs%ROWTYPE;s public.receipt_scan_results%ROWTYPE;a private.receipt_scan_accounts%ROWTYPE;n integer;
BEGIN
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id FOR UPDATE;
 SELECT * INTO j FROM private.receipt_scan_jobs WHERE id=p_lease AND user_id=p_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'scan_lease_not_found'; END IF;
 IF j.status IN ('completed','failed') THEN RETURN private.receipt_scan_state(p_user)||jsonb_build_object('leaseCompleted',j.status='completed'); END IF;
 IF j.status<>'active' THEN RAISE EXCEPTION 'scan_lease_not_active'; END IF;
 IF p_scan IS NOT NULL THEN
  SELECT * INTO s FROM public.receipt_scan_results WHERE id=p_scan AND user_id=p_user;
  IF NOT FOUND OR s.receipt_hash IS DISTINCT FROM j.receipt_hash OR s.ocr_data->>'usage_lease_id' IS DISTINCT FROM j.id::text THEN RAISE EXCEPTION 'scan_usage_proof_mismatch'; END IF;
 END IF;
 UPDATE private.receipt_scan_jobs SET status=CASE WHEN s.ocr_data->>'completed_machine_check'='true' AND j.expires_at>clock_timestamp() THEN 'completed' ELSE 'failed' END,scan_id=p_scan,finished_at=clock_timestamp() WHERE id=j.id;
 IF j.expires_at<=clock_timestamp() AND p_scan IS NOT NULL THEN UPDATE public.receipt_scan_results SET submission_allowed=false WHERE id=p_scan; END IF;
 IF s.ocr_data->>'non_receipt_confirmed'='true' AND s.ocr_data->>'completed_machine_check'='true' AND j.expires_at>clock_timestamp() THEN
  SELECT * INTO a FROM private.receipt_scan_accounts WHERE user_id=p_user FOR UPDATE;
  INSERT INTO private.receipt_scan_violations(user_id,generation,receipt_hash,job_id) VALUES(p_user,a.generation,j.receipt_hash,j.id) ON CONFLICT DO NOTHING;
  SELECT count(*) INTO n FROM private.receipt_scan_violations WHERE user_id=p_user AND generation=a.generation AND created_at>=clock_timestamp()-interval '7 days';
  IF n>=p.violation_limit AND a.suspended_at IS NULL THEN
   UPDATE private.receipt_scan_accounts SET suspended_at=clock_timestamp() WHERE user_id=p_user;
   INSERT INTO public.audit_logs(admin_id,action,details) VALUES(NULL,'تجميد الفحص الذكي تلقائياً',jsonb_build_object('target_id',p_user,'violations',n,'policy','receipt-usage-v1'));
  END IF;
 END IF;
 RETURN private.receipt_scan_state(p_user)||jsonb_build_object('leaseCompleted',(SELECT status='completed' FROM private.receipt_scan_jobs WHERE id=j.id));
END $$;

-- Even an already saved OCR result cannot be claimed after suspension, or before
-- its server-only usage lease was finalized. Customers cannot race the callback.
CREATE OR REPLACE FUNCTION private.require_receipt_usage() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM private.receipt_scan_accounts WHERE user_id=NEW.user_id AND suspended_at IS NOT NULL) THEN RAISE EXCEPTION 'receipt_feature_suspended'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.receipt_scan_jobs j WHERE j.user_id=NEW.user_id AND j.receipt_hash=NEW.receipt_hash AND j.status='completed' AND j.scan_id=(NEW.ocr_data->>'edge_scan_id')::uuid AND j.id::text=NEW.ocr_data->>'usage_lease_id') THEN RAISE EXCEPTION 'scan_usage_proof_required'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS require_receipt_usage ON public.payment_receipts;
CREATE TRIGGER require_receipt_usage BEFORE INSERT ON public.payment_receipts FOR EACH ROW EXECUTE FUNCTION private.require_receipt_usage();

CREATE OR REPLACE FUNCTION private.admin_receipt_scan_states(p_users uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE items jsonb;
BEGIN
 PERFORM private.assert_session_aal();
 IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_admins') THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF COALESCE(cardinality(p_users),0)>200 THEN RAISE EXCEPTION 'too_many_users'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('userId',p.id,'usage',private.receipt_scan_state(p.id))),'[]') INTO items FROM public.profiles p WHERE p.id=ANY(p_users);
 RETURN jsonb_build_object('customers',items,'policy',(SELECT to_jsonb(x)-'id' FROM private.receipt_scan_policy x WHERE id));
END $$;
CREATE OR REPLACE FUNCTION private.admin_set_receipt_scan_suspension(p_user uuid,p_suspended boolean,p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM private.assert_session_aal();
 IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_admins') THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF p_suspended IS NULL OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 6 AND 500 OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND role='customer') THEN RAISE EXCEPTION 'invalid_suspension_input'; END IF;
 PERFORM 1 FROM private.receipt_scan_policy WHERE id FOR UPDATE;
 INSERT INTO private.receipt_scan_accounts(user_id) VALUES(p_user) ON CONFLICT DO NOTHING;
 UPDATE private.receipt_scan_accounts SET suspended_at=CASE WHEN p_suspended THEN clock_timestamp() ELSE NULL END,generation=CASE WHEN p_suspended THEN generation ELSE gen_random_uuid() END,reset_at=clock_timestamp() WHERE user_id=p_user;
 INSERT INTO public.audit_logs(admin_id,action,details) VALUES(auth.uid(),CASE WHEN p_suspended THEN 'تجميد الفحص الذكي' ELSE 'فك تجميد الفحص الذكي' END,jsonb_build_object('target_id',p_user,'reason',btrim(p_reason)));
END $$;
CREATE OR REPLACE FUNCTION private.admin_update_receipt_scan_policy(p_user_limit integer,p_global_limit integer,p_provider_limit integer,p_concurrency integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM private.assert_session_aal();
 IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_admins') THEN RAISE EXCEPTION 'access_denied'; END IF;
 UPDATE private.receipt_scan_policy SET user_daily_limit=p_user_limit,global_daily_limit=p_global_limit,provider_daily_limit=p_provider_limit,concurrency_limit=p_concurrency WHERE id;
 INSERT INTO public.audit_logs(admin_id,action,details) VALUES(auth.uid(),'تعديل سياسة الفحص الذكي',jsonb_build_object('daily_user',p_user_limit,'daily_store',p_global_limit,'provider_calls',p_provider_limit,'concurrency',p_concurrency));
END $$;

CREATE OR REPLACE FUNCTION private.validate_receipt_scan(p_user uuid,p_scan uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT NOT EXISTS(SELECT 1 FROM private.receipt_scan_accounts WHERE user_id=p_user AND suspended_at IS NOT NULL)
 AND EXISTS(SELECT 1 FROM private.receipt_scan_jobs j JOIN public.receipt_scan_results r ON r.id=j.scan_id
 WHERE j.user_id=p_user AND j.scan_id=p_scan AND j.status='completed' AND r.user_id=p_user AND r.expires_at>clock_timestamp()
 AND r.claimed_at IS NULL AND r.ocr_data->>'usage_lease_id'=j.id::text AND r.receipt_hash=j.receipt_hash)
$$;
CREATE OR REPLACE FUNCTION public.validate_receipt_scan_usage(p_user uuid,p_scan uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.validate_receipt_scan(p_user,p_scan) $$;

-- API wrappers are invokers. The privileged implementations remain private.
CREATE OR REPLACE FUNCTION public.get_receipt_scan_usage(p_user uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.receipt_scan_state(p_user) $$;
CREATE OR REPLACE FUNCTION public.begin_receipt_scan_usage(p_user uuid,p_hash text,p_context text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.begin_receipt_scan(p_user,p_hash,p_context) $$;
CREATE OR REPLACE FUNCTION public.poll_receipt_scan_usage(p_user uuid,p_ticket uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.poll_receipt_scan(p_user,p_ticket) $$;
CREATE OR REPLACE FUNCTION public.meter_receipt_scan_usage(p_user uuid,p_lease uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.meter_receipt_scan(p_user,p_lease) $$;
CREATE OR REPLACE FUNCTION public.finish_receipt_scan_usage(p_user uuid,p_lease uuid,p_scan uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.finish_receipt_scan(p_user,p_lease,p_scan) $$;
CREATE OR REPLACE FUNCTION public.admin_receipt_scan_states(p_users uuid[]) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.admin_receipt_scan_states(p_users) $$;
CREATE OR REPLACE FUNCTION public.admin_set_receipt_scan_suspension(p_user uuid,p_suspended boolean,p_reason text) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.admin_set_receipt_scan_suspension(p_user,p_suspended,p_reason) $$;
CREATE OR REPLACE FUNCTION public.admin_update_receipt_scan_policy(p_user_limit integer,p_global_limit integer,p_provider_limit integer,p_concurrency integer) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.admin_update_receipt_scan_policy(p_user_limit,p_global_limit,p_provider_limit,p_concurrency) $$;

DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('private','public') AND p.proname IN (
 'receipt_scan_state','begin_receipt_scan','poll_receipt_scan','meter_receipt_scan','finish_receipt_scan','require_receipt_usage','admin_receipt_scan_states','admin_set_receipt_scan_suspension','admin_update_receipt_scan_policy',
 'validate_receipt_scan','validate_receipt_scan_usage','get_receipt_scan_usage','begin_receipt_scan_usage','poll_receipt_scan_usage','meter_receipt_scan_usage','finish_receipt_scan_usage') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC,anon,authenticated',f.nspname,f.proname,f.args);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO service_role',f.nspname,f.proname,f.args);
  IF f.proname LIKE 'admin_%' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated',f.nspname,f.proname,f.args); END IF;
 END LOOP;
END $$;
COMMIT;
