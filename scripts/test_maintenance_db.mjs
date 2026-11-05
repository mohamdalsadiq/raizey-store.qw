import fs from 'node:fs';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();let n=0;
const run=sql=>db.exec(sql);
const check=async(name,sql)=>{assert.equal((await db.query(sql)).rows[0].ok,true,name);console.log('PASS '+name);n++;};
try {
await run(fs.readFileSync('db/tests/audit_baseline_schema.sql','utf8'));
await run(fs.readFileSync('supabase/migrations/20261018082730_comprehensive_security_audit_fixes.sql','utf8'));
await run('ALTER TABLE storage.buckets ADD COLUMN file_size_limit bigint, ADD COLUMN allowed_mime_types text[]');
for(const file of ['20261018200000_auth_onboarding_banner_controls.sql','20261019001000_phone_number_country_rules.sql','20261020211409_restrict_catalog_storage_permissions.sql','20261105084312_receipt_and_store_maintenance.sql']) await run(fs.readFileSync('supabase/migrations/'+file,'utf8'));
await run(fs.readFileSync('supabase/migrations/20261105090230_mandatory_receipt_validation.sql','utf8'));
await run(fs.readFileSync('supabase/migrations/20261105090230_mandatory_receipt_validation.sql','utf8'));
await run(fs.readFileSync('db/pending/receipt_scan_usage_policy.sql','utf8'));
const a='d6040000-0000-4000-8000-000000000001',b='d6040000-0000-4000-8000-000000000002',staff='d6040000-0000-4000-8000-000000000003',method='d6040000-0000-4000-8000-000000000010',path=a+'/verified/d6040000-0000-4000-8000-000000000020.png';
await run(`BEGIN; INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES('${a}','maintenance-a@example.invalid','{}'),('${b}','maintenance-b@example.invalid','{}'),('${staff}','maintenance-staff@example.invalid','{}');
SET LOCAL session_replication_role=replica; UPDATE profiles SET role='admin' WHERE id='${staff}'; SET LOCAL session_replication_role=origin;
INSERT INTO admin_permissions(profile_id,can_manage_wallets,can_manage_orders) VALUES('${staff}',true,true);
INSERT INTO payment_methods(id,name,account_info,is_active,account_number) VALUES('${method}','Fixture bank','Fixture only',true,'1234567');
CREATE FUNCTION pg_temp.try_sql(command text) RETURNS text LANGUAGE plpgsql AS $$ BEGIN EXECUTE command; RETURN 'accepted'; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;
INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('receipts','${path}','{"size":69,"mimetype":"image/png"}');
INSERT INTO receipt_attachments(user_id,object_path,receipt_hash,image_bytes,mime_type) VALUES('${a}','${path}',repeat('a',64),69,'image/png');`);
await check('missing object rejected',`SELECT pg_temp.try_sql($q$INSERT INTO receipt_attachments(user_id,object_path,receipt_hash,image_bytes,mime_type) VALUES('${a}','${a}/verified/d6040000-0000-4000-8000-000000000099.png',repeat('b',64),69,'image/png')$q$)='receipt_object_missing' AS ok`);
await check('foreign attachment rejected',`SELECT pg_temp.try_sql($q$SELECT private.assert_receipt_attachment('${b}','${path}',repeat('a',64))$q$)='receipt_attachment_not_found' AS ok`);
await check('forged hash rejected',`SELECT pg_temp.try_sql($q$SELECT private.assert_receipt_attachment('${a}','${path}',repeat('b',64))$q$)='receipt_attachment_hash_mismatch' AS ok`);
const payload={p_amount:1,p_payment_method_id:method,p_tx_ref:'MAINTAIN0001',p_receipt_hash:'a'.repeat(64),p_receipt_path:path,p_ocr_status:'passed',p_amount_detected:1,p_tx_ref_ocr:'MAINTAIN0001',p_ocr_data:{amount_verified:true,ref_verified:true},p_receipt_url:'https://evil.invalid/'};
await run(`SELECT set_config('request.jwt.claims','{"sub":"${a}","role":"authenticated","aal":"aal1"}',true); SET LOCAL ROLE authenticated;`);
await check('client cannot forge registry',`SELECT pg_temp.try_sql('SELECT * FROM receipt_attachments') LIKE '%permission denied%' AS ok`);
await check('client cannot upload replacement',`SELECT pg_temp.try_sql($q$INSERT INTO storage.objects(bucket_id,name) VALUES('receipts','${a}/x.png')$q$) LIKE '%row-level security%' AS ok`);
let response=await db.query('SELECT execute_store_action($1,$2,gen_random_uuid()) AS response',['create_wallet_topup_from_receipt',payload]);assert.equal(response.rows[0].response.ok,false,JSON.stringify(response.rows[0]));n++;console.log('PASS missing scan rejected');
await run('RESET ROLE');
const scanId='d6040000-0000-4000-8000-000000000030';
await run(`INSERT INTO receipt_scan_results(id,user_id,receipt_hash,image_bytes,mime_type,expected_amount,manual_ref,expected_account,decision,ocr_status,amount_detected,tx_ref_ocr,submission_allowed,expires_at,ocr_data)
VALUES('${scanId}','${a}',repeat('a',64),69,'image/png',1,'MAINTAIN0001','1234567','accept','passed',1,'MAINTAIN0001',true,now()+interval '30 minutes',jsonb_build_object('receipt_path','${path}','attachment_id',(SELECT id FROM receipt_attachments WHERE object_path='${path}'),'expected_method_id','${method}','receipt_policy','mandatory-visual-v1','automatic_check_complete',true,'ref_verified',true,'amount_verified',true));
`);
await run(`WITH j AS (INSERT INTO private.receipt_scan_jobs(user_id,context_key,receipt_hash,quota_day,status,expires_at,started_at,finished_at,scan_id) VALUES('${a}',repeat('a',64),repeat('a',64),(clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date,'completed',clock_timestamp()+interval '5 minutes',clock_timestamp(),clock_timestamp(),'${scanId}') RETURNING id) UPDATE receipt_scan_results SET ocr_data=ocr_data||jsonb_build_object('usage_lease_id',j.id,'completed_machine_check',true) FROM j WHERE receipt_scan_results.id='${scanId}'; SET LOCAL ROLE authenticated;`);
payload.p_ocr_data={edge_scan_id:scanId};
response=await db.query('SELECT execute_store_action($1,$2,gen_random_uuid()) AS response',['create_wallet_topup_from_receipt',payload]);
assert.equal(response.rows[0].response.ok,true,JSON.stringify(response.rows[0]));n++;console.log('PASS automatically checked topup accepted');
await run('RESET ROLE');
await check('checked topup remains pending without credit',`SELECT (SELECT count(*)=1 FROM wallet_topups WHERE user_id='${a}' AND status='pending' AND NOT amount_verified) AND (SELECT balance=0 FROM wallets WHERE user_id='${a}') AS ok`);
await check('server proof retained without payment settlement',`SELECT amount_verified AND ref_verified AND NOT payment_verified AND amount_detected=1 AND ocr_status='passed' AND ocr_data->>'receipt_policy'='mandatory-visual-v1' AS ok FROM payment_receipts WHERE user_id='${a}'`);
await check('permanent URL derived',`SELECT receipt_url='receipts/${path}' AS ok FROM wallet_topups WHERE user_id='${a}'`);
await check('numeric ID rejects letters',`SELECT pg_temp.try_sql($q$SELECT private.assert_order_fields('[{"key":"id","type":"numeric_id","min_length":5,"max_length":20}]','{"id":"AUDIT-NOT-A-PLAYER"}')$q$)='invalid_order_field_value' AS ok`);
await check('Arabic ID accepted',`SELECT pg_temp.try_sql($q$SELECT private.assert_order_fields('[{"key":"id","type":"numeric_id","min_length":5,"max_length":20}]','{"id":"١٢٣٤٥٦"}')$q$)='accepted' AS ok`);
await check('text fields still accept text',`SELECT pg_temp.try_sql($q$SELECT private.assert_order_fields('[{"key":"name","type":"text"}]','{"name":"customer"}')$q$)='accepted' AS ok`);
for(const discount of [0,95,96,100]) await check('coupon boundary '+discount,`SELECT (pg_temp.try_sql($q$INSERT INTO coupons(code,discount_percent) VALUES('MAINTENANCE${discount}',${discount})$q$)='accepted')=${discount===95} AS ok`);
await run(`SELECT set_config('request.jwt.claims','{"sub":"${staff}","role":"authenticated","aal":"aal1"}',true); SET LOCAL ROLE authenticated;`);
await check('approval requires bank review',`SELECT pg_temp.try_sql($q$SELECT admin_confirm_topup((SELECT id FROM wallet_topups WHERE user_id='${a}'))$q$)='bank_review_required' AS ok`);
await run(`SELECT admin_confirm_topup((SELECT id FROM wallet_topups WHERE user_id='${a}'),'LOCAL TEST bank ledger checked');`);
await check('repeat approval rejected',`SELECT pg_temp.try_sql($q$SELECT admin_confirm_topup((SELECT id FROM wallet_topups WHERE user_id='${a}'),'LOCAL TEST bank ledger checked')$q$)='already_processed' AS ok`);
await run('RESET ROLE');
await check('only one credit',`SELECT (SELECT balance=1 FROM wallets WHERE user_id='${a}') AND (SELECT count(*)=1 FROM wallet_transactions WHERE user_id='${a}' AND direction='credit') AS ok`);
await check('payment state separate from OCR',`SELECT payment_verified AND amount_verified AND payment_verified_by='${staff}'::uuid AS ok FROM payment_receipts WHERE user_id='${a}'`);

// Independent proof fixtures: trusted server inserts only, then adversarial client requests.
await run(`SELECT set_config('request.jwt.claims','{"sub":"${a}","role":"authenticated","aal":"aal1"}',true);`);
let fixture=100;
async function proof(amount,overrides={}) {
 const suffix=String(++fixture).padStart(12,'0'),sid='d6040000-0000-4000-8000-'+suffix;
 const imagePath=a+'/verified/'+sid+'.png',hash=fixture.toString(16).padStart(64,'0'),ref='PROOF'+fixture;
 await db.query(`INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('receipts',$1,'{"size":69,"mimetype":"image/png"}')`,[imagePath]);
 const attachment=(await db.query(`INSERT INTO receipt_attachments(user_id,object_path,receipt_hash,image_bytes,mime_type) VALUES($1,$2,$3,69,'image/png') RETURNING id`,[a,imagePath,hash])).rows[0].id;
 const metadata={receipt_path:imagePath,attachment_id:attachment,expected_method_id:method,receipt_policy:'mandatory-visual-v1',automatic_check_complete:true,ref_verified:true,amount_verified:true,...overrides.metadata};
 await db.query(`INSERT INTO receipt_scan_results(id,user_id,receipt_hash,image_bytes,mime_type,expected_amount,manual_ref,expected_account,decision,ocr_status,amount_detected,tx_ref_ocr,submission_allowed,expires_at,ocr_data) VALUES($1,$2,$3,69,'image/png',$4,$5,'1234567',$6,'passed',$4,$5,$7,now()+interval '30 minutes',$8)`,[sid,overrides.user||a,hash,amount,ref,overrides.decision||'accept',overrides.allowed??true,metadata]);
 await db.query(`WITH j AS (INSERT INTO private.receipt_scan_jobs(user_id,context_key,receipt_hash,quota_day,status,expires_at,started_at,finished_at,scan_id) VALUES($1,$2,$2,(clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date,'completed',clock_timestamp()+interval '5 minutes',clock_timestamp(),clock_timestamp(),$3) RETURNING id) UPDATE receipt_scan_results SET ocr_data=ocr_data||jsonb_build_object('usage_lease_id',j.id,'completed_machine_check',true) FROM j WHERE receipt_scan_results.id=$3`,[a,hash,sid]);
 if(overrides.expired) await db.query(`UPDATE receipt_scan_results SET expires_at=now()-interval '1 minute' WHERE id=$1`,[sid]);
 return {p_amount:amount,p_payment_method_id:method,p_tx_ref:ref,p_receipt_hash:hash,p_receipt_path:imagePath,p_receipt_url:'receipts/'+imagePath,p_ocr_data:{edge_scan_id:sid},sid};
}
async function action(name,payload) {
 await run('SET LOCAL ROLE authenticated');
 const res=(await db.query('SELECT execute_store_action($1,$2,gen_random_uuid()) AS result',[name,payload])).rows[0].result;
 await run('RESET ROLE');return res;
}
for(const [name,overrides] of Object.entries({legacy:{metadata:{receipt_policy:null}},technical:{allowed:false,decision:'review'},foreign:{user:b},expired:{expired:true},nonreceipt:{metadata:{automatic_check_complete:false}},incomplete:{metadata:{amount_verified:false}}})) {
 const item=await proof(10,overrides);const res=await action('create_wallet_topup_from_receipt',item);assert.equal(res.ok,false,name);n++;console.log('PASS '+name+' proof rejected');
 await check(name+' leaves scan unclaimed',`SELECT claimed_at IS NULL AS ok FROM receipt_scan_results WHERE id='${item.sid}'`);
}
const wrongAmount=await proof(100);wrongAmount.p_amount=100.02;assert.equal((await action('create_wallet_topup_from_receipt',wrongAmount)).ok,false);n++;console.log('PASS amount difference of 0.02 rejected');
const wrongRef=await proof(100);wrongRef.p_tx_ref='FORGED99999';assert.equal((await action('create_wallet_topup_from_receipt',wrongRef)).ok,false);n++;console.log('PASS forged reference rejected');
const replay=await proof(10);assert.equal((await action('create_wallet_topup_from_receipt',replay)).ok,true);assert.equal((await action('create_wallet_topup_from_receipt',replay)).ok,false);n++;console.log('PASS replay rejected');
// Server prices total 150. Neither client amounts nor partial commits can alter it.
const product='d6040000-0000-4000-8000-000000000080';
await run(`UPDATE profiles SET whatsapp_number='+249911234567' WHERE id='${a}'; INSERT INTO products(id,name,price_usd) VALUES('${product}','SPLIT TEST',1); INSERT INTO settings(key,value) VALUES('usd_to_sdg_rate','150'),('profit_margin_percent','0') ON CONFLICT(key) DO UPDATE SET value=excluded.value;`);
const bankPayload=(first,second)=>({p_items:[{product_id:product,quantity:1,field_values:{}}],p_receipt:{tx_ref:first.p_tx_ref,receipt_hash:first.p_receipt_hash,receipt_path:first.p_receipt_path,payment_method_id:method,ocr_status:'passed',ocr_data:first.p_ocr_data,...(second?{secondary_receipt:{tx_ref:second.p_tx_ref,receipt_hash:second.p_receipt_hash,receipt_path:second.p_receipt_path,payment_method_id:method,ocr_data:second.p_ocr_data}}:{})}});
const first=await proof(100),second=await proof(50);const split=await action('create_bank_orders_bulk',bankPayload(first,second));assert.equal(split.ok,true,JSON.stringify(split));n++;console.log('PASS split order accepted atomically');
await check('split sum equals server order charge',`SELECT (SELECT sum(amount_expected)=150 FROM payment_receipts WHERE tx_ref_raw IN ('${first.p_tx_ref}','${second.p_tx_ref}')) AND (SELECT sum(price_sdg_snapshot)=150 FROM orders WHERE product_id='${product}') AND (SELECT parent_receipt_id IS NOT NULL FROM payment_receipts WHERE tx_ref_raw='${second.p_tx_ref}') AS ok`);
await run(`SELECT set_config('request.jwt.claims','{"sub":"${staff}","role":"authenticated","aal":"aal1"}',true); SET LOCAL ROLE authenticated;`);
await check('split order cannot start without bank settlement review',`SELECT pg_temp.try_sql($q$SELECT admin_update_order_status((SELECT id FROM orders WHERE product_id='${product}' LIMIT 1),'in_progress')$q$)='bank_review_required' AS ok`);
await run(`SELECT admin_update_order_status((SELECT id FROM orders WHERE product_id='${product}' LIMIT 1),'in_progress','LOCAL TEST both transfers checked in ledger'); RESET ROLE;`);
await check('split settlement covers both receipts',`SELECT count(*)=2 AND bool_and(payment_verified) AS ok FROM payment_receipts WHERE tx_ref_raw IN ('${first.p_tx_ref}','${second.p_tx_ref}')`);
await run(`SELECT set_config('request.jwt.claims','{"sub":"${a}","role":"authenticated","aal":"aal1"}',true);`);
const failFirst=await proof(100),failSecond=await proof(49);const failedSplit=await action('create_bank_orders_bulk',bankPayload(failFirst,failSecond));assert.equal(failedSplit.ok,false);n++;console.log('PASS split with wrong total rejected');
await check('failed second receipt rolls back first claim',`SELECT claimed_at IS NULL AND NOT EXISTS(SELECT 1 FROM payment_receipts WHERE tx_ref_raw='${failFirst.p_tx_ref}') AS ok FROM receipt_scan_results WHERE id='${failFirst.sid}'`);
const single=await proof(150);assert.equal((await action('create_bank_orders_bulk',bankPayload(single))).ok,true);n++;console.log('PASS single payment still works');
await run('ROLLBACK');console.log(`${n} maintenance database checks passed; migration applied twice; disposable users rolled back.`);
} finally {await db.close();}
