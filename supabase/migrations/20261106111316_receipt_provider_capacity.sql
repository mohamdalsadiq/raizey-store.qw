-- Shared provider quota guard. Customer days stay in Khartoum; Google days
-- use America/Los_Angeles (including DST). Two stages are reserved atomically.
BEGIN;
ALTER TABLE private.receipt_scan_policy
 ADD COLUMN IF NOT EXISTS provider_rpm_limit integer NOT NULL DEFAULT 15 CHECK(provider_rpm_limit BETWEEN 2 AND 100000),
 ADD COLUMN IF NOT EXISTS provider_tpm_limit integer NOT NULL DEFAULT 250000 CHECK(provider_tpm_limit BETWEEN 16000 AND 2000000000),
 ADD COLUMN IF NOT EXISTS provider_token_reserve integer NOT NULL DEFAULT 16000 CHECK(provider_token_reserve BETWEEN 1000 AND 1000000);
ALTER TABLE private.receipt_scan_jobs ADD COLUMN IF NOT EXISTS provider_reserved integer NOT NULL DEFAULT 0 CHECK(provider_reserved BETWEEN 0 AND 2);
CREATE TABLE IF NOT EXISTS private.receipt_scan_provider_window (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),lease_id uuid NOT NULL,
 called_at timestamptz NOT NULL DEFAULT clock_timestamp(),token_reserve integer NOT NULL CHECK(token_reserve>0)
);
CREATE INDEX IF NOT EXISTS receipt_scan_provider_window_time ON private.receipt_scan_provider_window(called_at);
ALTER TABLE private.receipt_scan_provider_window ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.receipt_scan_provider_window FROM PUBLIC,anon,authenticated;
-- Apply the observed free-project ceilings, once. Reapplying must not reset
-- later administrator configuration or actual counters.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='receipt_provider_quota_initialized' AND conrelid='private.receipt_scan_policy'::regclass) THEN
  UPDATE private.receipt_scan_policy SET provider_daily_limit=least(provider_daily_limit,500),global_daily_limit=least(global_daily_limit,250);
  -- Old counters used Khartoum days. Conservatively carry both intersecting
  -- days into today's Pacific counter; never erase already incurred calls.
  INSERT INTO private.receipt_scan_provider_days(quota_day,calls)
   SELECT (clock_timestamp() AT TIME ZONE 'America/Los_Angeles')::date,coalesce(sum(calls),0)::integer
   FROM private.receipt_scan_provider_days WHERE quota_day >= (clock_timestamp() AT TIME ZONE 'America/Los_Angeles')::date
   ON CONFLICT(quota_day) DO UPDATE SET calls=greatest(private.receipt_scan_provider_days.calls,EXCLUDED.calls);
  ALTER TABLE private.receipt_scan_policy ADD CONSTRAINT receipt_provider_quota_initialized CHECK(true);
 END IF;
END $$;
CREATE OR REPLACE FUNCTION private.receipt_provider_capacity(p_new_calls integer,p_exclude uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE p private.receipt_scan_policy%ROWTYPE;d date:=(clock_timestamp() AT TIME ZONE 'America/Los_Angeles')::date;
 day_calls integer;minute_calls integer;held integer;tokens bigint;
BEGIN
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id;
 SELECT coalesce(calls,0) INTO day_calls FROM private.receipt_scan_provider_days WHERE quota_day=d;
 day_calls:=coalesce(day_calls,0);
 SELECT count(*),coalesce(sum(token_reserve),0) INTO minute_calls,tokens FROM private.receipt_scan_provider_window WHERE called_at>clock_timestamp()-interval '60 seconds';
 SELECT coalesce(sum(provider_reserved),0) INTO held FROM private.receipt_scan_jobs WHERE status='active' AND expires_at>clock_timestamp() AND (p_exclude IS NULL OR id<>p_exclude);
 RETURN jsonb_build_object('allowed',day_calls+held+p_new_calls<=p.provider_daily_limit AND minute_calls+held+p_new_calls<=p.provider_rpm_limit AND tokens+(held::bigint+p_new_calls)*p.provider_token_reserve<=p.provider_tpm_limit,
 'dayExhausted',day_calls+p_new_calls>p.provider_daily_limit);
END $$;

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
  'resetAt',((d+1)::timestamp AT TIME ZONE 'Africa/Khartoum'),'timezone','Africa/Khartoum','providerResetAt',(((clock_timestamp() AT TIME ZONE 'America/Los_Angeles')::date+1)::timestamp AT TIME ZONE 'America/Los_Angeles'),'providerTimezone','America/Los_Angeles');
END $$;
CREATE OR REPLACE FUNCTION private.begin_receipt_scan(p_user uuid,p_hash text,p_context text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p private.receipt_scan_policy%ROWTYPE; j private.receipt_scan_jobs%ROWTYPE; s jsonb; d date:=(clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date; running_n integer; global_n integer; cached_scan uuid; capacity jsonb;
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
 capacity:=private.receipt_provider_capacity(2,NULL);
 IF (capacity->>'dayExhausted')::boolean THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_provider_daily_limit','usage',s); END IF;
 IF j.id IS NULL THEN
  IF (SELECT count(*) FROM private.receipt_scan_jobs WHERE status='queued')>=200 THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_queue_full','usage',s); END IF;
  INSERT INTO private.receipt_scan_jobs(user_id,context_key,receipt_hash,quota_day,status,expires_at)
    VALUES(p_user,p_context,p_hash,d,'queued',clock_timestamp()+interval '15 minutes') RETURNING * INTO j;
 END IF;
 SELECT count(*) INTO running_n FROM private.receipt_scan_jobs WHERE status='active';
 IF running_n>=p.concurrency_limit OR NOT (capacity->>'allowed')::boolean OR EXISTS(SELECT 1 FROM private.receipt_scan_jobs WHERE status='queued' AND (created_at,id)<(j.created_at,j.id)) THEN
  RETURN jsonb_build_object('allowed',false,'reason','receipt_queued','ticketId',j.id,'position',(SELECT count(*) FROM private.receipt_scan_jobs WHERE status='queued' AND (created_at,id)<=(j.created_at,j.id)),'retryAfter',3,'usage',s);
 END IF;
 UPDATE private.receipt_scan_jobs SET status='active',provider_reserved=2,quota_day=d,started_at=clock_timestamp(),expires_at=clock_timestamp()+interval '5 minutes' WHERE id=j.id;
 RETURN jsonb_build_object('allowed',true,'leaseId',j.id,'usage',private.receipt_scan_state(p_user));
END $$;
CREATE OR REPLACE FUNCTION private.poll_receipt_scan(p_user uuid,p_ticket uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE j private.receipt_scan_jobs%ROWTYPE;p private.receipt_scan_policy%ROWTYPE;s jsonb;capacity jsonb;
BEGIN
 SELECT * INTO j FROM private.receipt_scan_jobs WHERE id=p_ticket AND user_id=p_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'scan_ticket_not_found'; END IF;
 s:=private.receipt_scan_state(p_user);
 IF (s->>'suspended')::boolean THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_feature_suspended','usage',s); END IF;
 IF j.expires_at<=clock_timestamp() OR j.status NOT IN ('queued','active') THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_queue_expired','usage',s); END IF;
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id;
 capacity:=private.receipt_provider_capacity(2,NULL);
 IF (capacity->>'dayExhausted')::boolean THEN RETURN jsonb_build_object('allowed',false,'reason','receipt_provider_daily_limit','usage',s); END IF;
 RETURN jsonb_build_object('allowed',false,'reason','receipt_queued','ticketId',j.id,'retryAfter',3,
 'canRetry',j.status='queued' AND (capacity->>'allowed')::boolean AND (SELECT count(*) FROM private.receipt_scan_jobs WHERE status='active' AND expires_at>clock_timestamp())<p.concurrency_limit AND NOT EXISTS(SELECT 1 FROM private.receipt_scan_jobs WHERE status='queued' AND expires_at>clock_timestamp() AND (created_at,id)<(j.created_at,j.id)),
 'position',(SELECT count(*) FROM private.receipt_scan_jobs WHERE status='queued' AND expires_at>clock_timestamp() AND (created_at,id)<=(j.created_at,j.id)),'usage',s);
END $$;
CREATE OR REPLACE FUNCTION private.meter_receipt_scan(p_user uuid,p_lease uuid,p_stage text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p private.receipt_scan_policy%ROWTYPE;j private.receipt_scan_jobs%ROWTYPE;
 d date:=(clock_timestamp() AT TIME ZONE 'America/Los_Angeles')::date;future_calls integer;capacity jsonb;
BEGIN
 SELECT * INTO p FROM private.receipt_scan_policy WHERE id FOR UPDATE;
 SELECT * INTO j FROM private.receipt_scan_jobs WHERE id=p_lease AND user_id=p_user FOR UPDATE;
 IF NOT FOUND OR j.status<>'active' OR j.expires_at<=clock_timestamp() OR j.provider_calls>=12 OR p_stage NOT IN ('ocr','visual') OR p_stage IS NULL
 OR EXISTS(SELECT 1 FROM private.receipt_scan_accounts WHERE user_id=p_user AND suspended_at IS NOT NULL)
 OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=p_user AND NOT is_banned) THEN RETURN false; END IF;
 -- Every OCR retry still reserves a later visual call. Retries cannot consume
 -- another customer's promises or leave its accepted-looking OCR unusable.
 future_calls:=CASE WHEN p_stage='ocr' THEN 1 ELSE 0 END;
 capacity:=private.receipt_provider_capacity(1+future_calls,j.id);
 IF NOT (capacity->>'allowed')::boolean THEN RETURN false; END IF;
 DELETE FROM private.receipt_scan_provider_window WHERE called_at<clock_timestamp()-interval '2 minutes';
 INSERT INTO private.receipt_scan_provider_days(quota_day,calls) VALUES(d,1) ON CONFLICT(quota_day) DO UPDATE SET calls=private.receipt_scan_provider_days.calls+1;
 INSERT INTO private.receipt_scan_provider_window(lease_id,token_reserve) VALUES(j.id,p.provider_token_reserve);
 UPDATE private.receipt_scan_jobs SET provider_calls=provider_calls+1,provider_reserved=future_calls WHERE id=j.id;
 RETURN true;
END $$;
-- Keep the older two-argument server contract safe during the rollout.
CREATE OR REPLACE FUNCTION private.meter_receipt_scan(p_user uuid,p_lease uuid) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.meter_receipt_scan(p_user,p_lease,'ocr') $$;
CREATE OR REPLACE FUNCTION public.meter_receipt_scan_usage(p_user uuid,p_lease uuid,p_stage text) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private.meter_receipt_scan(p_user,p_lease,p_stage) $$;
REVOKE ALL ON FUNCTION private.receipt_provider_capacity(integer,uuid),private.meter_receipt_scan(uuid,uuid,text),public.meter_receipt_scan_usage(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.receipt_provider_capacity(integer,uuid),private.meter_receipt_scan(uuid,uuid,text),public.meter_receipt_scan_usage(uuid,uuid,text) TO service_role;
COMMIT;
