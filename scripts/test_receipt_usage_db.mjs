// Real SQL and RLS in embedded PostgreSQL. No provider calls or customer data.
// PGlite serializes connections: the 50-way admission test verifies invariants,
// not hosted PostgreSQL lock latency or Gemini throughput.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();let checks=0,serial=0;
const run=sql=>db.exec(sql);
const query=async(sql,params=[]) => (await db.query(sql,params)).rows;
const value=async(sql,params=[]) => (await query(sql,params))[0].v;
const check=(name,ok)=>{assert.ok(ok,name);checks++;console.log('PASS '+name);};
const uid=n=>'aabb0000-0000-4000-8000-'+String(n).padStart(12,'0');
const hash=n=>Number(n).toString(16).padStart(64,'0');
const method=uid(9000),admin=uid(9001),staff=uid(9002);
const rpc=(name,args)=>value(`SELECT public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) AS v`,args);
const begin=(user,n,context=n+100000)=>rpc('begin_receipt_scan_usage',[user,hash(n),hash(context)]);
const finish=(user,lease,scan=null)=>rpc('finish_receipt_scan_usage',[user,lease,scan]);
const state=user=>rpc('get_receipt_scan_usage',[user]);
async function actor(user,role='authenticated',aal='aal1'){
 await run('RESET ROLE');
 await query(`SELECT set_config('request.jwt.claims',$1,false)`,[JSON.stringify({sub:user,role,aal})]);
 if(role==='authenticated')await run('SET ROLE authenticated');
}
async function scan(user,lease,n,{unrelated=false,completed=true,accepted=false}={}){
 const sid=uid(20000+(++serial));const path=user+'/verified/'+sid+'.png',ref='USAGE'+serial;
 let attachment=null;
 if(accepted){
  await query(`INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('receipts',$1,'{"size":69,"mimetype":"image/png"}')`,[path]);
  attachment=(await query(`INSERT INTO receipt_attachments(user_id,object_path,receipt_hash,image_bytes,mime_type) VALUES($1,$2,$3,69,'image/png') RETURNING id`,[user,path,hash(n)]))[0].id;
 }
 const meta={usage_lease_id:lease,completed_machine_check:completed,non_receipt_confirmed:unrelated,usage_context_key:hash(n+100000),receipt_policy:'mandatory-visual-v1',automatic_check_complete:accepted,amount_verified:accepted,ref_verified:accepted,expected_method_id:method,receipt_path:accepted?path:null,attachment_id:attachment};
 await query(`INSERT INTO receipt_scan_results(id,user_id,receipt_hash,image_bytes,mime_type,expected_amount,manual_ref,expected_account,decision,ocr_status,amount_detected,tx_ref_ocr,submission_allowed,expires_at,ocr_data) VALUES($1,$2,$3,69,'image/png',1,$4,'1234567',$5,$6,1,$4,$7,clock_timestamp()+interval '30 minutes',$8)`,[sid,user,hash(n),ref,accepted?'accept':'reject',accepted?'passed':'rejected',accepted,meta]);
 return {sid,p_amount:1,p_payment_method_id:method,p_tx_ref:ref,p_receipt_hash:hash(n),p_receipt_path:path,p_ocr_data:{edge_scan_id:sid}};
}
async function topup(user,proof){
 await actor(user);
 const result=await rpc('execute_store_action',['create_wallet_topup_from_receipt',proof,uid(30000+(++serial))]);
 await run('RESET ROLE');return result;
}
try{
 await run(fs.readFileSync('db/tests/audit_baseline_schema.sql','utf8'));
 await run(fs.readFileSync('supabase/migrations/20261018082730_comprehensive_security_audit_fixes.sql','utf8'));
 await run('ALTER TABLE storage.buckets ADD COLUMN file_size_limit bigint, ADD COLUMN allowed_mime_types text[]');
 for(const f of ['20261018200000_auth_onboarding_banner_controls.sql','20261019001000_phone_number_country_rules.sql','20261020211409_restrict_catalog_storage_permissions.sql','20261105084312_receipt_and_store_maintenance.sql','20261105090230_mandatory_receipt_validation.sql'])await run(fs.readFileSync('supabase/migrations/'+f,'utf8'));
 const policy=fs.readFileSync('supabase/migrations/20261105191648_receipt_scan_usage_policy.sql','utf8');
 await run(policy);await run(policy);
await run(fs.readFileSync('supabase/migrations/20261105192028_receipt_scan_usage_indexes.sql','utf8'));
 await run(fs.readFileSync('db/tests/receipt_scan_usage_staging.sql','utf8'));
 check('policy defaults to 50 simultaneous admissions',(await value('SELECT concurrency_limit AS v FROM private.receipt_scan_policy'))===50);
 await run(`INSERT INTO auth.users(id,email,raw_user_meta_data) SELECT ('aabb0000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'usage'||n||'@example.invalid','{}' FROM generate_series(1,205) n;
 INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES('${admin}','usage-admin@example.invalid','{}'),('${staff}','usage-staff@example.invalid','{}');
 BEGIN;SET LOCAL session_replication_role=replica;UPDATE profiles SET role='admin' WHERE id IN ('${admin}','${staff}');SET LOCAL session_replication_role=origin;COMMIT;
 INSERT INTO admin_permissions(profile_id,can_manage_admins) VALUES('${admin}',true),('${staff}',false);
 INSERT INTO payment_methods(id,name,account_info,is_active,account_number) VALUES('${method}','TEST ONLY','TEST ONLY',true,'1234567');
 CREATE FUNCTION pg_temp.try_sql(command text) RETURNS text LANGUAGE plpgsql AS $$ BEGIN EXECUTE command; RETURN 'accepted'; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;`);

 await actor(uid(1));
 for(const [name,sql] of Object.entries({counters:'SELECT * FROM private.receipt_scan_jobs',policy:'UPDATE private.receipt_scan_policy SET user_daily_limit=20',admission:`SELECT public.begin_receipt_scan_usage('${uid(1)}','${hash(1)}','${hash(2)}')`,meter:`SELECT public.meter_receipt_scan_usage('${uid(1)}','${uid(2)}')`,finish:`SELECT public.finish_receipt_scan_usage('${uid(1)}','${uid(2)}',NULL)`})){
  check('customer cannot access '+name,(await value('SELECT pg_temp.try_sql($1) AS v',[sql])).includes('permission denied'));
 }
 check('customer cannot release suspension',(await value(`SELECT pg_temp.try_sql($q$SELECT public.admin_set_receipt_scan_suspension('${uid(1)}',false,'test release')$q$) AS v`))==='access_denied');
 await actor(staff);
 check('admin without permission cannot raise quotas',(await value(`SELECT pg_temp.try_sql('SELECT public.admin_update_receipt_scan_policy(5,1000,2500,50)') AS v`))==='access_denied');
 await run('RESET ROLE');

 const admissions=await Promise.all(Array.from({length:51},(_,i)=>begin(uid(i+1),i+1)));
 check('first 50 submitted admissions start without a queue',admissions.slice(0,50).every(x=>x.allowed===true));
 check('51st admission waits instead of exceeding limit',admissions[50].reason==='receipt_queued');
 check('exactly 50 leases active',(await value(`SELECT count(*)::integer AS v FROM private.receipt_scan_jobs WHERE status='active'`))===50);
 const duplicate=await begin(uid(1),1);
 check('duplicate active request cannot start second model run',duplicate.reason==='receipt_scan_in_progress');
 check('active reservation consumes one customer slot',(await state(uid(1))).remaining===4);
 await finish(uid(1),admissions[0].leaseId);
 check('technical failure returns daily slot',(await state(uid(1))).remaining===5);
 const poll=await rpc('poll_receipt_scan_usage',[uid(51),admissions[50].ticketId]);
 check('head ticket can immediately retry after a release',poll.canRetry===true);
 const newcomer=await begin(uid(52),52);
 check('newcomer cannot bypass existing ticket',newcomer.reason==='receipt_queued');
 const admitted=await begin(uid(51),51);
 check('queue head gets released slot',admitted.allowed===true);
 check('ticket cannot be polled by another customer',(await value(`SELECT pg_temp.try_sql($q$SELECT public.poll_receipt_scan_usage('${uid(52)}','${admissions[50].ticketId}')$q$) AS v`))==='scan_ticket_not_found');
 await run(`UPDATE private.receipt_scan_jobs SET status='failed',finished_at=clock_timestamp() WHERE status IN ('active','queued')`);

 // A full scan count and an actual provider-call count are deliberately separate.
 const user=uid(100);
 for(let i=0;i<5;i++){
  const job=await begin(user,1000+i);check('daily scan '+(i+1)+' admitted',job.allowed);
  await rpc('meter_receipt_scan_usage',[user,job.leaseId]);
  const proof=await scan(user,job.leaseId,1000+i,{accepted:i===0});
  if(i===0){
   check('stored scan is unusable before usage completion',!(await rpc('validate_receipt_scan_usage',[user,proof.sid])));
   check('claim cannot race unfinished usage completion',!(await topup(user,proof)).ok);
  }
  const done=await finish(user,job.leaseId,proof.sid);
  check('completion '+(i+1)+' counts once',done.remaining===4-i);
  check('repeat callback does not charge twice',(await finish(user,job.leaseId,proof.sid)).remaining===4-i);
  if(i===0){
   check('completed scan is reusable',await rpc('validate_receipt_scan_usage',[user,proof.sid]));
   check('cache/admission race cannot charge a second scan',(await begin(user,1000)).reason==='receipt_cached');
   check('completed proof creates pending topup',(await topup(user,proof)).ok);
   check('scan cannot be reused after claim',!(await rpc('validate_receipt_scan_usage',[user,proof.sid])));
  }
 }
 check('sixth daily scan denied',(await begin(user,2000)).reason==='receipt_daily_limit');
 check('rejected receipt is not an abuse strike',(await state(user)).violations===0);
 check('machine reading never credits wallet',(await value(`SELECT balance::integer AS v FROM wallets WHERE user_id='${user}'`))===0);
 const transient=uid(101),job=await begin(transient,2100);
 await rpc('meter_receipt_scan_usage',[transient,job.leaseId]);
 const incomplete=await scan(transient,job.leaseId,2100,{completed:false});
 check('technical result refunds completed-scan quota',(await finish(transient,job.leaseId,incomplete.sid)).remaining===5);
 check('technical calls still retained in provider budget',(await value(`SELECT provider_calls AS v FROM private.receipt_scan_jobs WHERE id='${job.leaseId}'`))===1);

 const abusive=uid(102);
 // Prepare one eligible proof before suspension; suspension must invalidate it.
 const validJob=await begin(abusive,2200),valid=await scan(abusive,validJob.leaseId,2200,{accepted:true});
 await finish(abusive,validJob.leaseId,valid.sid);
 for(let i=0;i<4;i++){
  const image=i===1?2300:2300+i; // same first hash again does not double strike
  const j=await begin(abusive,image,3300+i),s=await scan(abusive,j.leaseId,image,{unrelated:true});
  const done=await finish(abusive,j.leaseId,s.sid);
  check('distinct confirmed strikes '+i,done.violations===(i===0?1:i));
 }
 check('third distinct unrelated image freezes feature',(await state(abusive)).suspended);
 check('suspended account cannot call AI',(await begin(abusive,2400)).reason==='receipt_feature_suspended');
 check('previous accepted scan cannot be reused after suspension',!(await rpc('validate_receipt_scan_usage',[abusive,valid.sid])));
 check('previous accepted scan cannot create payment after suspension',!(await topup(abusive,valid)).ok);
 await actor(admin);
 await rpc('admin_set_receipt_scan_suspension',[abusive,false,'TEST ONLY reviewed false classification']);
 const states=await rpc('admin_receipt_scan_states',[[abusive]]);
 check('authorized admin release resets strikes',!states.customers[0].usage.suspended&&states.customers[0].usage.violations===0);
 check('release does not reset daily consumption',states.customers[0].usage.remaining===0);
 await run('RESET ROLE');
 check('admin release records reason and actor',(await value(`SELECT count(*)::integer AS v FROM audit_logs WHERE admin_id='${admin}' AND details->>'target_id'='${abusive}' AND details->>'reason'='TEST ONLY reviewed false classification'`))===1);
 await run(`INSERT INTO auth.mfa_factors(user_id,status,factor_type) VALUES('${admin}','verified','totp')`);
 await actor(admin);
 check('MFA-enrolled admin must use AAL2',(await value(`SELECT pg_temp.try_sql('SELECT public.admin_update_receipt_scan_policy(5,1000,2500,50)') AS v`))==='mfa_required');
 await actor(admin,'authenticated','aal2');
 check('admin cannot set concurrency beyond tested maximum',(await value(`SELECT pg_temp.try_sql('SELECT public.admin_update_receipt_scan_policy(5,1000,2500,51)') AS v`))!=='accepted');
 await run('RESET ROLE');

 const meterUser=uid(103),meterJob=await begin(meterUser,2500);
 const metered=await Promise.all(Array.from({length:13},()=>rpc('meter_receipt_scan_usage',[meterUser,meterJob.leaseId])));
 check('per-scan provider retry cap cannot be exceeded',metered.filter(Boolean).length===12);
 await finish(meterUser,meterJob.leaseId);
 const beforeCalls=await value('SELECT calls AS v FROM private.receipt_scan_provider_days');
 await query('UPDATE private.receipt_scan_policy SET provider_daily_limit=$1',[beforeCalls+1]);
 const last=await begin(uid(104),2600);
 check('last available provider attempt allowed',await rpc('meter_receipt_scan_usage',[uid(104),last.leaseId]));
 check('provider cap blocks next actual retry',!(await rpc('meter_receipt_scan_usage',[uid(104),last.leaseId])));
 await finish(uid(104),last.leaseId);
 check('provider cap blocks new image admission',(await begin(uid(105),2700)).reason==='receipt_provider_daily_limit');
 await run('UPDATE private.receipt_scan_policy SET provider_daily_limit=2500');

 const expired=await begin(uid(106),2800),expiredScan=await scan(uid(106),expired.leaseId,2800,{accepted:true});
 await query(`UPDATE private.receipt_scan_jobs SET expires_at=clock_timestamp()-interval '1 second' WHERE id=$1`,[expired.leaseId]);
 check('late model response does not complete expired lease',!(await finish(uid(106),expired.leaseId,expiredScan.sid)).leaseCompleted);
 check('expired lease revokes scan submission',!(await value('SELECT submission_allowed AS v FROM receipt_scan_results WHERE id=$1',[expiredScan.sid])));
 check('daily reset is next midnight in Khartoum',(await value(`SELECT (public.get_receipt_scan_usage('${uid(106)}')->>'resetAt')::timestamptz=((clock_timestamp() AT TIME ZONE 'Africa/Khartoum')::date+1)::timestamp AT TIME ZONE 'Africa/Khartoum' AS v`)));
 const started=await value(`SELECT count(*)::integer AS v FROM private.receipt_scan_jobs WHERE started_at IS NOT NULL`);
 await query('UPDATE private.receipt_scan_policy SET global_daily_limit=$1',[started]);
 check('global budget counts failures and denies further admission',(await begin(uid(107),2900)).reason==='receipt_store_daily_limit');
 check('every new private table has RLS',(await value(`SELECT bool_and(relrowsecurity) AS v FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relname IN ('receipt_scan_policy','receipt_scan_accounts','receipt_scan_jobs','receipt_scan_provider_days','receipt_scan_violations')`)));
 // A separate synthetic day: 200 customers x 5 images, in 50-admission waves.
 // Two metered calls/image model the normal OCR + visual verification path.
 await run(`TRUNCATE private.receipt_scan_jobs,private.receipt_scan_violations,private.receipt_scan_provider_days,private.receipt_scan_accounts CASCADE;
 UPDATE private.receipt_scan_policy SET user_daily_limit=5,global_daily_limit=1000,provider_daily_limit=2500,concurrency_limit=50;`);
 let allAdmitted=true;
 for(let round=0;round<5;round++){
  for(let batch=0;batch<4;batch++){
   const jobs=await Promise.all(Array.from({length:50},async(_,i)=>{
    const customer=uid(batch*50+i+1),image=10000+round*200+batch*50+i;
    return {customer,image,...await begin(customer,image)};
   }));
   allAdmitted&&=jobs.every(j=>j.allowed===true);
   for(const j of jobs){
    await rpc('meter_receipt_scan_usage',[j.customer,j.leaseId]);
    await rpc('meter_receipt_scan_usage',[j.customer,j.leaseId]);
    const proof=await scan(j.customer,j.leaseId,j.image);
    await finish(j.customer,j.leaseId,proof.sid);
   }
  }
 }
 check('200-customer synthetic day admits all 1000 scans',allAdmitted);
 check('1000 completed scans counted exactly',(await value(`SELECT count(*)::integer AS v FROM private.receipt_scan_jobs WHERE status='completed'`))===1000);
 check('normal two-stage day meters 2000 provider calls',(await value('SELECT calls AS v FROM private.receipt_scan_provider_days'))===2000);
 check('all 200 daily quotas complete without overcharging',(await value(`SELECT count(*)::integer AS v FROM (SELECT user_id FROM private.receipt_scan_jobs WHERE status='completed' GROUP BY user_id HAVING count(*)=5) x`))===200);
 check('1001st image is denied by global budget',(await begin(uid(201),12001)).reason==='receipt_store_daily_limit');
 console.log(`${checks} receipt usage database checks passed; no external model calls.`);
}finally{await db.close();}
