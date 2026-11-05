-- Run only on the isolated security staging project. All fixtures roll back.
-- These checks exercise the real SQL/RLS path, not Gemini or physical Storage.
DO $test$
DECLARE
 u uuid := 'ba550000-0000-4000-8000-000000000001';
 method uuid := 'ba550000-0000-4000-8000-000000000002';
 sid uuid := 'ba550000-0000-4000-8000-000000000003';
 attachment uuid;
 image_path text := 'ba550000-0000-4000-8000-000000000001/verified/ba550000-0000-4000-8000-000000000004.png';
 payload jsonb; response jsonb; blocked boolean; checks integer := 0;
BEGIN
 BEGIN
  INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES(u,'receipt-staging-fixture@example.invalid','{}');
  INSERT INTO public.payment_methods(id,name,account_info,account_number,is_active) VALUES(method,'STAGING RECEIPT FIXTURE','Not a real payment destination','1234567',true);
  INSERT INTO storage.buckets(id,name,public) VALUES('receipts','receipts',false) ON CONFLICT(id) DO NOTHING;
  INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('receipts',image_path,'{"size":69,"mimetype":"image/png"}');
  INSERT INTO public.receipt_attachments(user_id,object_path,receipt_hash,image_bytes,mime_type) VALUES(u,image_path,repeat('c',64),69,'image/png') RETURNING id INTO attachment;
  payload := jsonb_build_object('p_amount',1,'p_payment_method_id',method,'p_tx_ref','LIVEFIXTURE123456','p_receipt_hash',repeat('c',64),'p_receipt_path',image_path,'p_receipt_url','receipts/'||image_path,'p_ocr_status','passed','p_amount_detected',1,'p_tx_ref_ocr','LIVEFIXTURE123456','p_ocr_data',jsonb_build_object('ref_verified',true,'amount_verified',true));
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','aal','aal1')::text,true);
  SET LOCAL ROLE authenticated;
  blocked:=false;
  BEGIN PERFORM * FROM public.receipt_attachments; EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL client can access attachment registry'; END IF; checks:=checks+1;
  blocked:=false;
  BEGIN INSERT INTO storage.objects(bucket_id,name) VALUES('receipts',u::text||'/replacement.png'); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'FAIL client can upload unchecked image'; END IF; checks:=checks+1;
  SELECT public.execute_store_action('create_wallet_topup_from_receipt',payload,gen_random_uuid()) INTO response;
  IF response->>'ok' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'FAIL missing scan accepted'; END IF; checks:=checks+1;
  RESET ROLE;
  INSERT INTO public.receipt_scan_results(id,user_id,receipt_hash,image_bytes,mime_type,expected_amount,manual_ref,expected_account,decision,ocr_status,amount_detected,tx_ref_ocr,submission_allowed,expires_at,ocr_data)
  VALUES(sid,u,repeat('c',64),69,'image/png',1,'LIVEFIXTURE123456','1234567','accept','passed',1,'LIVEFIXTURE123456',true,now()+interval '30 minutes',jsonb_build_object('receipt_path',image_path,'attachment_id',attachment,'expected_method_id',method,'receipt_policy','legacy','automatic_check_complete',true,'ref_verified',true,'amount_verified',true));
  payload := jsonb_set(payload,'{p_ocr_data}',jsonb_build_object('edge_scan_id',sid));
  SET LOCAL ROLE authenticated;
  SELECT public.execute_store_action('create_wallet_topup_from_receipt',payload,gen_random_uuid()) INTO response;
  IF response->>'ok' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'FAIL legacy scan accepted'; END IF; checks:=checks+1;
  RESET ROLE;
  UPDATE public.receipt_scan_results SET ocr_data=jsonb_set(ocr_data,'{receipt_policy}','"mandatory-visual-v1"'),expires_at=now()-interval '1 minute' WHERE id=sid;
  SET LOCAL ROLE authenticated;
  SELECT public.execute_store_action('create_wallet_topup_from_receipt',payload,gen_random_uuid()) INTO response;
  IF response->>'ok' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'FAIL expired scan accepted'; END IF; checks:=checks+1;
  RESET ROLE;
  UPDATE public.receipt_scan_results SET expires_at=now()+interval '30 minutes' WHERE id=sid;
  SET LOCAL ROLE authenticated;
  SELECT public.execute_store_action('create_wallet_topup_from_receipt',jsonb_set(payload,'{p_amount}','2'),gen_random_uuid()) INTO response;
  IF response->>'ok' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'FAIL altered amount accepted'; END IF; checks:=checks+1;
  SELECT public.execute_store_action('create_wallet_topup_from_receipt',payload,gen_random_uuid()) INTO response;
  IF response->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'FAIL valid server proof: %',response; END IF; checks:=checks+1;
  SELECT public.execute_store_action('create_wallet_topup_from_receipt',payload,gen_random_uuid()) INTO response;
  IF response->>'ok' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'FAIL replay accepted'; END IF; checks:=checks+1;
  RESET ROLE;
  IF NOT EXISTS(SELECT 1 FROM public.payment_receipts WHERE user_id=u AND amount_verified AND ref_verified AND NOT payment_verified)
     OR NOT EXISTS(SELECT 1 FROM public.wallets WHERE user_id=u AND balance=0)
     OR NOT EXISTS(SELECT 1 FROM public.wallet_topups WHERE user_id=u AND status='pending') THEN RAISE EXCEPTION 'FAIL OCR incorrectly settled a payment'; END IF; checks:=checks+1;
  -- An intentional exception rolls back the whole inner fixture transaction.
  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='fixture_complete';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN
  IF checks<>9 THEN RAISE EXCEPTION 'FAIL incomplete staging checks: %',checks; END IF;
 END;
 IF EXISTS(SELECT 1 FROM auth.users WHERE id=u) OR EXISTS(SELECT 1 FROM public.payment_methods WHERE id=method) THEN RAISE EXCEPTION 'FAIL fixture cleanup'; END IF;
END $test$;
SELECT '9 live staging SQL checks passed; fixtures rolled back; no Gemini/Storage byte test' AS result;
