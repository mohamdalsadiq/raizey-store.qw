import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const root={SUPABASE_URL:'https://dvcsdbsnnbdpzaiccjej.supabase.co'};
const ctx={window:root,document:{addEventListener(){}},URL,console};vm.createContext(ctx);
for(const f of ['store-rules','receipt-links'])vm.runInContext(fs.readFileSync(`assets/js/${f}.js`,'utf8'),ctx);
let n=0;const check=(name,ok)=>{assert.ok(ok,name);n++;console.log('PASS '+name)};
for(const q of [0,1,20,21,-1,1.5,'2'])check('quantity '+q,root.MeemStoreRules.validQuantity(q)===[1,20].includes(q));
check('internal field label hidden',!root.MeemStoreRules.fieldLabel({},'field_123').includes('field_'));
const object='d6040000-0000-4000-8000-000000000001/verified/test.png';
check('permanent receipt reference',root.MeemReceiptLinks.objectPath('receipts/'+object)===object);
check('legacy signed URL normalized',root.MeemReceiptLinks.objectPath(root.SUPABASE_URL+'/storage/v1/object/sign/receipts/'+object+'?token=expired')===object);
for(const bad of ['https://evil.invalid/storage/v1/object/sign/receipts/'+object,'javascript:alert(1)','receipts/'+object.replace('verified','..'),'receipts/'+object+'.svg'])check('unsafe receipt rejected',root.MeemReceiptLinks.objectPath(bad)===null);
let calls=0;root.supabaseClient={storage:{from:()=>({createSignedUrl:async(path,ttl)=>{calls++;assert.equal(ttl,300);return{data:{signedUrl:root.SUPABASE_URL+'/storage/v1/object/sign/receipts/'+path+'?token='+calls}}}})}};
check('fresh signed URL on every open',(await root.MeemReceiptLinks.signedUrl(object))!==(await root.MeemReceiptLinks.signedUrl(object)));
root.supabaseClient.storage.from=()=>({createSignedUrl:async()=>({error:{message:'denied'}})});
await assert.rejects(root.MeemReceiptLinks.signedUrl(object),/receipt_access_denied/);n++;

// Exercise the real shortfall renderer and button callback. This caught a
// payment state being cleared immediately after it had been constructed.
const checkoutSource=fs.readFileSync('assets/js/pages/checkout-v2-2.js','utf8');
const start=checkoutSource.indexOf('  function showShortfallCard(');
const end=checkoutSource.indexOf('  remainderBtn.onclick',start);
assert.ok(start>0&&end>start,'shortfall renderer exists');
const elements=new Map();
const element=id=>{if(!elements.has(id))elements.set(id,{style:{},classList:{remove(){},add(){}},focus(){this.focused=true;},textContent:'',innerHTML:''});return elements.get(id);};
const checkoutContext={window:{},document:{getElementById:element},console,ADMIN_WHATSAPP:'',
  shortfallBox:element('shortfallBox'),remainderStep:element('remainderStep'),remainderMsg:element('remainderMsg'),
  remainderInput:element('remainderInput'),fileBox:element('fileUploadBox'),logFraudAttempt(){},
  formatSDG:v=>String(v),encodeURIComponent};
vm.createContext(checkoutContext);
vm.runInContext(checkoutSource.replace(/\ninit\(\);\s*$/,'')+'\n'+checkoutSource.slice(start,end),checkoutContext);
vm.runInContext("savedTxRef='TEST123456'; showShortfallCard({}, {shortfall:{remaining:50,paid:100,target:150},riskFlags:[]});",checkoutContext);
check('shortfall retains the first payment',vm.runInContext('splitPayment.remaining===50 && splitPayment.paid===100 && scanResult===null',checkoutContext));
element('paidRestBtn').onclick();
check('remainder button opens without losing payment state',element('remainderStep').style.display==='block' && element('remainderMsg').textContent.includes('50'));
vm.runInContext('invalidateCheckoutReceipt()',checkoutContext);
check('changed checkout invalidates both payment proofs',vm.runInContext('splitPayment===null && scanResult===null && checkoutScanContext===null',checkoutContext));

console.log(`${n} maintenance client checks passed.`);
