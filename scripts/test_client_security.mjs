import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
const calls=[]; const storage=new Map();let attempt=0;
const client={
  auth:{getSession:async()=>({data:{session:{user:{id:'audit-user'}}}}),onAuthStateChange:()=>{}},
  rpc:async(name,args)=>{calls.push({name,args});attempt++;
    return attempt===1?{data:null,error:{message:'network error'}}:{data:{ok:true,data:[{id:'audit-order'}]},error:null};}
};
const context={window:{location:{hostname:'test.invalid',origin:'https://test.invalid'},supabase:{createClient:()=>client}},
  document:{readyState:'loading',addEventListener:()=>{}},sessionStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},
  console,crypto:webcrypto,TextEncoder,Intl,URL,setTimeout,clearTimeout};
vm.createContext(context);vm.runInContext(fs.readFileSync(new URL('../assets/js/supabase-client.js',import.meta.url),'utf8'),context);
const args={p_items:[{product_id:'audit-product',quantity:1}]};
await client.rpc('create_wallet_orders_bulk',args);await client.rpc('create_wallet_orders_bulk',args);await client.rpc('create_wallet_orders_bulk',args);
assert.equal(calls[0].name,'execute_store_action');
assert.equal(calls[0].args.p_request_id,calls[1].args.p_request_id,'uncertain network retry keeps its idempotency key');
assert.notEqual(calls[1].args.p_request_id,calls[2].args.p_request_id,'a confirmed purchase ends its intent; a later identical purchase is allowed');
assert.equal(storage.size,0,'completed intents leave no customer payload in browser storage');
const getFunction=(text,name)=>text.match(new RegExp('(?:async )?function '+name+'\\([^]*?(?=\\n(?:async )?function |\\ninit\\(\\);|$)'))[0];
const settings=fs.readFileSync(new URL('../assets/js/pages/admin-settings-2.js',import.meta.url),'utf8');
let writes=0;let rpcError=null;
const nodes={formError:{textContent:''},formSuccess:{textContent:''},rateInput:{value:'200'},marginInput:{value:'10'},whatsappInput:{value:'123'}};
const settingsContext={document:{getElementById:id=>nodes[id]},supabaseClient:{rpc:async()=>{writes++;return{error:rpcError}}},getFriendlyError:()=> 'تعذر الحفظ'};
vm.createContext(settingsContext);vm.runInContext(getFunction(settings,'saveRate'),settingsContext);
await settingsContext.saveRate();assert.equal(writes,0,'invalid contact data cannot partially change prices');
nodes.whatsappInput.value='249123456789';rpcError={message:'denied'};await settingsContext.saveRate();assert.equal(nodes.formSuccess.textContent,'','failed mutations never display success');
rpcError=null;await settingsContext.saveRate();assert.ok(nodes.formSuccess.textContent,'valid settings still save');
for (const [file,fn] of [
  ['admin-products-2.js','deleteProduct'],
  ['admin-coupons-2.js','deleteCoupon'],
  ['admin-referral-milestones-2.js','deleteMilestone']
]) {
  const source=fs.readFileSync(new URL(`../assets/js/pages/${file}`,import.meta.url),'utf8');
  let deleteError={message:'denied'}, reloaded=0, notified=0;
  const ctx={confirm:()=>true,alert:()=>{notified++},getFriendlyError:e=>e.message,loadProducts:async()=>{reloaded++},loadCoupons:async()=>{reloaded++},loadMilestones:async()=>{reloaded++},
    supabaseClient:{from:()=>({delete:()=>({eq:async()=>({error:deleteError})})})}};
  vm.createContext(ctx);vm.runInContext(getFunction(source,fn),ctx);
  await ctx[fn]('audit-id');assert.equal(reloaded,0,`${fn}: denied deletion must not look successful`);assert.equal(notified,1,`${fn}: the operator sees the error`);
  deleteError=null;await ctx[fn]('audit-id');assert.equal(reloaded,1,`${fn}: legitimate deletion reloads`);
}
console.log('Client security: 16 passed (idempotent retry, settings atomicity, CRUD error and success paths).');
