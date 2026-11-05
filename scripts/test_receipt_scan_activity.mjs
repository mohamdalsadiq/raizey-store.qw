// Exercise the real checkout/wallet handlers with deferred network responses.
// This verifies duplicate-start prevention and cleanup, not browser layout.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
let checks=0;
const check=(label,ok)=>{assert.ok(ok,label);checks++;console.log('PASS '+label);};
class Element {
  constructor(tag='div'){
    this.tagName=tag;this.attrs=new Map();this.children=[];this.style={};this.dataset={};this.files=[];this.value='';this.checked=false;this.hidden=false;this._text='';this._class='';
    if(['button','input','select'].includes(tag))this.disabled=false;
    this.classList={contains:n=>this._class.split(' ').includes(n),add:n=>{if(!this.classList.contains(n))this._class+=' '+n;},remove:n=>{this._class=this._class.split(' ').filter(v=>v!==n).join(' ');},toggle:n=>{this.classList.contains(n)?this.classList.remove(n):this.classList.add(n);}};
  }
  get className(){return this._class;}set className(s){this._class=s;}
  get textContent(){return this._text+this.children.map(c=>c.textContent).join('');}
  set textContent(s){this._text=String(s);this.children=[];}
  set innerHTML(s){this._html=s;this._text='';this.children=[];}get innerHTML(){return this._html||'';}
  append(...nodes){this.children.push(...nodes);}
  replaceChildren(...nodes){this._text='';this.children=[...nodes];}
  contains(node){return node===this||this.children.some(c=>c.contains(node));}
  setAttribute(n,v){this.attrs.set(n,String(v));}getAttribute(n){return this.attrs.get(n)??null;}removeAttribute(n){this.attrs.delete(n);}
  addEventListener(){}querySelectorAll(){return [];}focus(){}click(){this.onclick?.();}
}
function load(page){
  const elements=new Map();
  const buttonIds=new Set(['submitTopupBtn','retryWalletReceiptBtn','retryCheckoutReceiptBtn','placeOrderBtn','remainderRefBtn','saveTxRefBtn']);
  const inputIds=new Set(['receiptInput','receiptInput3','amountInput','transactionRefInput','geminiConsent','geminiConsentWallet','remainderRefInput']);
  const get=id=>{
    if(!elements.has(id))elements.set(id,new Element(buttonIds.has(id)?'button':inputIds.has(id)?'input':id==='methodSelect'?'select':'div'));
    return elements.get(id);
  };
  const document={getElementById:get,createElement:tag=>new Element(tag),querySelectorAll:()=>[],addEventListener(){}};
  const context={document,Blob,AbortController,setTimeout,clearTimeout,console,URL,encodeURIComponent,
    formatSDG:String,escapeHtml:v=>String(v).replaceAll('<','&lt;'),rzIconMarkup:()=>'',
    supabaseClient:{rpc:async()=>({data:[],error:null})}};
  context.window=context;context.globalThis=context;vm.createContext(context);
  vm.runInContext(fs.readFileSync('assets/js/receipt-pipeline.js','utf8'),context);
  vm.runInContext(fs.readFileSync('assets/js/pages/'+page,'utf8').replace(/\ninit\(\);\s*$/,''),context);
  context.testFile=new Blob(['fixture'],{type:'image/png'});
  return {context,get,exec:s=>vm.runInContext(s,context)};
}
const rejected={decision:'reject',submissionAllowed:false,extracted:{},riskFlags:[],message:'الصورة غير مناسبة'};
const accepted={decision:'accept',submissionAllowed:true,receiptPolicy:'mandatory-visual-v1',automaticCheckComplete:true,scanId:'s',receiptPath:'owner/x.png',attachmentId:'a',receiptHash:'hash',refVerified:true,amountVerified:true,extracted:{amount:125000,txRef:'REF123456'},riskFlags:[],message:'اجتاز الإشعار الفحص'};
{
  const {context,get}=load('wallet-2.js');
  const activity=context.MeemReceiptPipeline.beginScanActivity(get('receiptScanStatus'),[get('retryWalletReceiptBtn'),get('submitTopupBtn')]);
  activity.update('<img src=x onerror=alert(1)>');
  check('status message is plain text',get('receiptScanStatus').children[1].children[1].textContent==='<img src=x onerror=alert(1)>');
  check('assistive technology receives busy state',get('receiptScanStatus').getAttribute('aria-busy')==='true');
  get('receiptScanStatus').textContent='تغيرت بيانات الدفع';
  activity.finish();activity.finish();
  check('cleanup preserves replacement result message',get('receiptScanStatus').textContent==='تغيرت بيانات الدفع');
  check('cleanup is idempotent and releases busy state',get('receiptScanStatus').getAttribute('aria-busy')==='false'&&!get('retryWalletReceiptBtn').disabled);
}
{
  const {context,get,exec}=load('wallet-2.js');
  get('amountInput').value='125000';get('methodSelect').value='method';get('geminiConsentWallet').checked=true;
  exec("savedWalletTxRef='REF123456';receiptFile=testFile;");
  let calls=0,pending;
  context.MeemReceiptPipeline.analyze=()=>{calls++;return new Promise((resolve,reject)=>{pending={resolve,reject};});};
  get('receiptInput').disabled=true;await context.runWalletReceiptScan();
  check('wallet cannot retry an older image during new-file validation',calls===0);
  get('receiptInput').disabled=false;
  get('submitTopupBtn').disabled=true; // must preserve an earlier disabled state
  const first=context.runWalletReceiptScan();await context.runWalletReceiptScan();
  check('wallet double start produces one scan',calls===1);
  check('wallet scan locks retry, upload and submit',get('retryWalletReceiptBtn').disabled&&get('receiptInput').disabled&&get('submitTopupBtn').disabled);
  pending.resolve(rejected);await first;
  check('wallet rejection unlocks retry',!get('retryWalletReceiptBtn').disabled&&!get('receiptInput').disabled);
  check('wallet keeps previously disabled submit disabled',get('submitTopupBtn').disabled);
  check('wallet rejection cannot become payment evidence',exec('receiptAnalysis===null && walletScanBusy===false'));
  const failed=context.runWalletReceiptScan();pending.reject(new Error('network failed'));await failed;
  check('wallet unexpected network failure unlocks retry',!get('retryWalletReceiptBtn').disabled&&exec('walletScanBusy===false'));
  const stale=context.runWalletReceiptScan();context.resetReceiptScan('تغير المبلغ');pending.resolve(accepted);await stale;
  check('wallet stale result is ignored and scan unlocks',exec('receiptAnalysis===null && walletScanBusy===false')&&get('receiptScanStatus').textContent==='تغير المبلغ');
  const success=context.runWalletReceiptScan();pending.resolve(accepted);await success;
  check('wallet accepts completed result and unlocks controls',exec('receiptAnalysis?.scanId==="s" && walletScanBusy===false')&&!get('retryWalletReceiptBtn').disabled);
}
{
  const {context,get,exec}=load('checkout-v2-2.js');
  exec("savedTxRef='REF123456';selectedMethodId='method';cart=[{quantity:1,price_sdg:125000}];");
  get('geminiConsent').checked=true;get('receiptInput').files=[context.testFile];
  let calls=0,pending;
  context.MeemReceiptPipeline.serverVerify=()=>{calls++;return new Promise(resolve=>{pending=resolve;});};
  context.attachCheckoutEvents(false);
  const first=get('receiptInput').onchange();await get('retryCheckoutReceiptBtn').onclick();
  check('checkout repeated click produces one scan',calls===1);
  check('checkout locks upload, retry and payment',get('receiptInput').disabled&&get('retryCheckoutReceiptBtn').disabled&&get('placeOrderBtn').disabled);
  pending(rejected);await first;
  check('checkout rejection unlocks controls',!get('retryCheckoutReceiptBtn').disabled&&!get('placeOrderBtn').disabled&&exec('checkoutScanBusy===false'));
  check('checkout rejection cannot authorize payment',exec('scanResult===null'));
  get('receiptInput').files=[context.testFile];
  const stale=get('receiptInput').onchange();context.invalidateCheckoutReceipt();pending(accepted);await stale;
  check('checkout stale result cannot authorize payment',exec('scanResult===null && checkoutScanBusy===false'));
  get('receiptInput').files=[context.testFile];
  const success=get('receiptInput').onchange();pending(accepted);await success;
  check('checkout success releases lock and retains proof',exec('scanResult?.scanId==="s" && checkoutScanBusy===false')&&!get('placeOrderBtn').disabled);
  exec("splitPayment={firstFile:testFile,paid:75000,remaining:50000,secondRef:'SECOND123456'};");
  get('receiptInput3').files=[context.testFile];
  const pendingSplit=[],splitAmounts=[];
  context.MeemReceiptPipeline.serverVerify=(file,options)=>{splitAmounts.push(options.expectedAmount);return new Promise(resolve=>pendingSplit.push(resolve));};
  const split=get('receiptInput3').onchange();await get('receiptInput3').onchange();
  check('split repeated click does not start another scan',splitAmounts.length===1&&get('receiptInput3').disabled);
  pendingSplit.shift()(accepted);await new Promise(resolve=>setImmediate(resolve));
  check('split keeps controls locked across both receipt checks',splitAmounts.length===2&&get('placeOrderBtn').disabled&&exec('checkoutScanBusy===true'));
  check('split scan preserves both expected amounts',splitAmounts.join(',')==='50000,75000');
  pendingSplit.shift()(accepted);await split;
  check('split completion unlocks controls once and retains both proofs',!get('placeOrderBtn').disabled&&exec('checkoutScanBusy===false && !!splitPayment.firstScan && !!splitPayment.secondScan'));
}
console.log(`${checks} scan activity checks passed; no live API calls.`);
