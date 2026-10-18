-- Disposable fixtures only. On a real Supabase database the entire file MUST end in ROLLBACK.
BEGIN;
SET LOCAL statement_timeout='15s';
DO $$BEGIN
 IF EXISTS(SELECT 1 FROM auth.users WHERE id::text LIKE 'a6180000-0000-4000-8000-%') THEN RAISE EXCEPTION 'audit_fixture_collision'; END IF;
END$$;
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('a6180000-0000-4000-8000-000000000001','audit-a-20261018@example.invalid','{"full_name":"Audit A"}'),
 ('a6180000-0000-4000-8000-000000000002','audit-b-20261018@example.invalid','{"full_name":"Audit B"}'),
 ('a6180000-0000-4000-8000-000000000003','audit-admin-20261018@example.invalid','{"full_name":"Audit Staff"}'),
 ('a6180000-0000-4000-8000-000000000004','audit-super-20261018@example.invalid','{"full_name":"Audit Super"}');
SET LOCAL session_replication_role=replica;
UPDATE public.profiles SET role='admin' WHERE id IN ('a6180000-0000-4000-8000-000000000003','a6180000-0000-4000-8000-000000000004');
SET LOCAL session_replication_role=origin;
INSERT INTO public.admin_permissions(profile_id,can_manage_products,can_manage_orders,can_manage_wallets)
VALUES ('a6180000-0000-4000-8000-000000000003',true,true,true);
INSERT INTO public.admin_permissions(profile_id,is_super_admin) VALUES('a6180000-0000-4000-8000-000000000004',true);
INSERT INTO public.categories(id,name,is_active) VALUES ('a6180000-0000-4000-8000-000000000010','AUDIT fixture',true);
INSERT INTO public.products(id,category_id,name,price_usd,is_active) VALUES
 ('a6180000-0000-4000-8000-000000000011','a6180000-0000-4000-8000-000000000010','AUDIT product',0.01,true);
INSERT INTO public.settings(key,value) VALUES ('usd_to_sdg_rate','150'),('profit_margin_percent','0') ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value;
UPDATE public.wallets SET balance=100 WHERE user_id='a6180000-0000-4000-8000-000000000001';
INSERT INTO public.wallet_transactions(user_id,amount,direction,balance_after,source)
VALUES ('a6180000-0000-4000-8000-000000000001',100,'credit',100,'opening_balance');
CREATE TEMP TABLE audit_results(name text,passed boolean,evidence jsonb);
GRANT INSERT,SELECT ON audit_results TO authenticated,anon;
CREATE FUNCTION pg_temp.check_result(label text,ok boolean,detail jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $$
 INSERT INTO audit_results VALUES(label,coalesce(ok,false),detail);
$$;
CREATE FUNCTION pg_temp.try_sql(command text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE command; RETURN 'accepted'; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END;
$$;
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE audit_action_result AS SELECT public.execute_store_action('create_wallet_orders_bulk',
 '{"p_items":[{"product_id":"a6180000-0000-4000-8000-000000000011","quantity":2}]}','a6180000-0000-4000-8000-000000000050') AS response;
SELECT pg_temp.check_result('wallet_success',(SELECT (response->>'ok')::boolean FROM audit_action_result));
SELECT pg_temp.check_result('wallet_retry_replayed',(public.execute_store_action('create_wallet_orders_bulk',
 '{"p_items":[{"product_id":"a6180000-0000-4000-8000-000000000011","quantity":2}]}','a6180000-0000-4000-8000-000000000050')->>'replayed')::boolean);
SELECT pg_temp.check_result('idempotency_payload_conflict',(public.execute_store_action('create_wallet_orders_bulk',
 '{"p_items":[{"product_id":"a6180000-0000-4000-8000-000000000011","quantity":3}]}','a6180000-0000-4000-8000-000000000050')->>'error')='idempotency_conflict');
SELECT pg_temp.check_result('direct_money_rpc_denied',pg_temp.try_sql($q$SELECT public.create_wallet_orders_bulk('[]')$q$) LIKE '%permission denied%');
SELECT pg_temp.check_result('negative_quantity_denied',(public.execute_store_action('create_wallet_orders_bulk',
 '{"p_items":[{"product_id":"a6180000-0000-4000-8000-000000000011","quantity":-1}]}',gen_random_uuid())->>'error')='invalid_quantity');
SELECT pg_temp.check_result('client_price_ignored',(SELECT sum(price_sdg_snapshot)=3 FROM public.orders));
DO $$DECLARE i integer; r jsonb; BEGIN
 FOR i IN 1..12 LOOP r:=public.execute_store_action('redeem_gift_card',jsonb_build_object('p_code','AUDIT-MISSING-'||i),gen_random_uuid()); END LOOP;
 PERFORM pg_temp.check_result('failed_gift_attempts_limited',r->>'error'='rate_limited',r);
END$$;
RESET ROLE;
SELECT pg_temp.check_result('wallet_debit_matches_orders',
 (SELECT sum(amount) FROM public.wallet_transactions WHERE user_id='a6180000-0000-4000-8000-000000000001' AND direction='debit')=
 (SELECT sum(price_sdg_snapshot) FROM public.orders WHERE user_id='a6180000-0000-4000-8000-000000000001'));
SELECT pg_temp.check_result('retry_did_not_duplicate',(SELECT count(*)=2 FROM public.orders WHERE user_id='a6180000-0000-4000-8000-000000000001'));
SELECT pg_temp.check_result('failed_attempt_counter_persisted',(SELECT request_count=12 FROM private.chat_rate_limits WHERE rate_key='action:redeem_gift_card:a6180000-0000-4000-8000-000000000001'));
INSERT INTO public.payment_codes(id,code,amount) VALUES('a6180000-0000-4000-8000-000000000050','AUDIT-CANCEL-TEST',10);
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_result('staff_cannot_promote',pg_temp.try_sql($q$UPDATE public.profiles SET role='admin' WHERE id='a6180000-0000-4000-8000-000000000002'$q$) LIKE '%permission denied%');
SELECT pg_temp.check_result('staff_cannot_cancel_code_without_permission',pg_temp.try_sql($q$SELECT public.admin_cancel_payment_code('a6180000-0000-4000-8000-000000000050')$q$)='access_denied');
SELECT pg_temp.check_result('profile_display_edit_allowed',pg_temp.try_sql($q$UPDATE public.profiles SET full_name='Audit Staff Renamed' WHERE id='a6180000-0000-4000-8000-000000000003'$q$)='accepted');
SELECT public.admin_update_order_status(id,'cancelled') FROM public.orders WHERE user_id='a6180000-0000-4000-8000-000000000001' AND status='in_progress';
INSERT INTO public.audit_logs(admin_id,action,source,created_at) VALUES('a6180000-0000-4000-8000-000000000002','AUDIT forged actor','security_event','2000-01-01');
RESET ROLE;
SELECT pg_temp.check_result('refund_no_minted_money',(SELECT balance=100 FROM public.wallets WHERE user_id='a6180000-0000-4000-8000-000000000001'));
SELECT pg_temp.check_result('audit_actor_bound',exists(SELECT 1 FROM public.audit_logs WHERE action='AUDIT forged actor' AND admin_id='a6180000-0000-4000-8000-000000000003' AND source='admin_action' AND created_at>='2026-10-18'));
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000004","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE audit_cancel_result AS SELECT pg_temp.try_sql($q$SELECT public.admin_cancel_payment_code('a6180000-0000-4000-8000-000000000050')$q$) AS outcome;
SELECT pg_temp.check_result('authorized_cancel_succeeds',(SELECT outcome='accepted' FROM audit_cancel_result),(SELECT jsonb_build_object('result',outcome) FROM audit_cancel_result));
SELECT pg_temp.check_result('cancel_replay_denied',pg_temp.try_sql($q$SELECT public.admin_cancel_payment_code('a6180000-0000-4000-8000-000000000050')$q$)='code_not_active');
RESET ROLE;
SELECT pg_temp.check_result('cancel_and_audit_atomic',exists(SELECT 1 FROM public.admin_audit_logs WHERE action='cancel_payment_code' AND target_id='a6180000-0000-4000-8000-000000000050') AND (SELECT status='cancelled' FROM public.payment_codes WHERE code='AUDIT-CANCEL-TEST'));
INSERT INTO public.gift_cards(code,amount) VALUES('AUDIT-STAFF-SECRET',25),('AUDIT-CUSTOMER-GIFT',30);
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_result('staff_cannot_read_gift_codes',NOT exists(SELECT 1 FROM public.gift_cards WHERE code='AUDIT-STAFF-SECRET'));
SELECT pg_temp.check_result('staff_cannot_read_audit_without_permission',NOT exists(SELECT 1 FROM public.audit_logs));
SELECT pg_temp.check_result('staff_cannot_bypass_maintenance_permission',pg_temp.try_sql($q$UPDATE public.store_settings SET maintenance_mode=true$q$) LIKE '%permission denied%');
RESET ROLE;
INSERT INTO public.payment_methods(id,name,is_active,account_number,account_info) VALUES
 ('a6180000-0000-4000-8000-000000000020','AUDIT bank',true,'12345','AUDIT only'),
 ('a6180000-0000-4000-8000-000000000021','AUDIT other bank',true,'99999','AUDIT only');
INSERT INTO public.receipt_scan_results(id,user_id,receipt_hash,image_bytes,mime_type,expected_amount,manual_ref,decision,ocr_status,amount_detected,tx_ref_ocr,risk_flags,ocr_data,submission_allowed,expires_at)
VALUES ('a6180000-0000-4000-8000-000000000030','a6180000-0000-4000-8000-000000000002',repeat('a',64),128,'image/png',150,'AUDIT618001','review_admin','needs_admin_check',150,'AUDIT618001',ARRAY['old_receipt'],jsonb_build_object('expected_method_id','a6180000-0000-4000-8000-000000000020','raw_text_excerpt','AUDIT server OCR'),true,now()+interval '30 minutes');
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_result('cross_user_wallet_read_denied',NOT exists(SELECT 1 FROM public.wallets WHERE user_id='a6180000-0000-4000-8000-000000000001'));
SELECT pg_temp.check_result('cross_user_order_cancel_denied',pg_temp.try_sql($q$SELECT public.cancel_my_order((SELECT (response->'data'->0->>'id')::uuid FROM audit_action_result))$q$)<>'accepted');
CREATE TEMP TABLE audit_topup_payload AS SELECT jsonb_build_object('p_amount',150,'p_payment_method_id','a6180000-0000-4000-8000-000000000021','p_receipt_url',null,
 'p_tx_ref','AUDIT618001','p_receipt_hash',repeat('a',64),'p_ocr_status','passed','p_risk_flags','[]'::jsonb,
 'p_ocr_data',jsonb_build_object('edge_scan_id','a6180000-0000-4000-8000-000000000030','raw_text_excerpt','AUDIT fake OCR')) AS payload;
SELECT pg_temp.check_result('scan_wrong_method_denied',(public.execute_store_action('create_wallet_topup_from_receipt',(SELECT payload FROM audit_topup_payload),gen_random_uuid())->>'error')='receipt_scan_method_mismatch');
UPDATE audit_topup_payload SET payload=jsonb_set(payload,'{p_payment_method_id}','"a6180000-0000-4000-8000-000000000020"');
SELECT pg_temp.check_result('valid_topup_allowed',(public.execute_store_action('create_wallet_topup_from_receipt',(SELECT payload FROM audit_topup_payload),gen_random_uuid())->>'ok')::boolean);
SELECT pg_temp.check_result('gift_success',(public.execute_store_action('redeem_gift_card','{"p_code":"AUDIT-CUSTOMER-GIFT"}',gen_random_uuid())->>'ok')::boolean);
SELECT pg_temp.check_result('gift_replay_denied',(public.execute_store_action('redeem_gift_card','{"p_code":"AUDIT-CUSTOMER-GIFT"}',gen_random_uuid())->>'ok')::boolean=false);
RESET ROLE;
SELECT pg_temp.check_result('server_scan_status_preserved',exists(SELECT 1 FROM public.payment_receipts WHERE receipt_hash=repeat('a',64) AND ocr_status='needs_admin_check' AND risk_flags=ARRAY['old_receipt'] AND ocr_data->>'raw_text_excerpt'='AUDIT server OCR'));
SET LOCAL session_replication_role=replica;
INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,secret,friendly_name,created_at,updated_at)
VALUES('a6180000-0000-4000-8000-000000000041','a6180000-0000-4000-8000-000000000001','totp','verified','AUDIT-NOT-A-REAL-SECRET','AUDIT',now(),now());
SET LOCAL session_replication_role=origin;
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_result('mfa_read_denied',NOT exists(SELECT 1 FROM public.profiles WHERE id=auth.uid()));
SELECT pg_temp.check_result('mfa_rpc_denied',pg_temp.try_sql($q$SELECT public.execute_store_action('create_wallet_orders_bulk','{}',gen_random_uuid())$q$)='mfa_required');
SELECT pg_temp.check_result('mfa_edge_context_denied',public.get_session_security_context()->>'requires_mfa'='true');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_result('aal2_read_allowed',exists(SELECT 1 FROM public.profiles WHERE id=auth.uid()));
SELECT pg_temp.check_result('aal2_edge_context_allowed',public.get_session_security_context()->>'allowed'='true');
RESET ROLE;
UPDATE public.products SET required_fields='[{"key":"player_id","label":"Player ID"}]' WHERE id='a6180000-0000-4000-8000-000000000011';
SELECT set_config('request.jwt.claims','{"sub":"a6180000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_result('required_fields_enforced',(public.execute_store_action('create_wallet_orders_bulk','{"p_items":[{"product_id":"a6180000-0000-4000-8000-000000000011"}]}',gen_random_uuid())->>'error')='required_order_field_missing');
SELECT pg_temp.check_result('required_fields_legitimate_flow',(public.execute_store_action('create_wallet_orders_bulk','{"p_items":[{"product_id":"a6180000-0000-4000-8000-000000000011","field_values":{"player_id":"123456"}}]}',gen_random_uuid())->>'ok')::boolean);
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT name,passed,evidence FROM audit_results ORDER BY name;
ROLLBACK;
