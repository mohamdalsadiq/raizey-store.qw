import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
let checks=0;
function context(pathname='/login.html', initial={}) {
 const values=new Map(Object.entries(initial)), redirects=[], callbacks=[];
 let aal='aal1';
 const ctx={URL,setTimeout,clearTimeout,location:{origin:'https://store.test',pathname,search:'',hash:'',replace:v=>redirects.push(v)},
  sessionStorage:{getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)},
  window:{supabaseClient:{auth:{mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:aal,nextLevel:'aal2'}})},onAuthStateChange:cb=>callbacks.push(cb)}}}};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync('assets/js/mfa-guard.js','utf8'),ctx);
 return {ctx,flow:ctx.window.MeemAuthFlow,values,redirects,callbacks,setAal:v=>aal=v};
}
for(const attack of ['https://evil.test/x','//evil.test','javascript:alert(1)','/login.html','/register.html','/verify.html','/mfa.html','/%6cogin.html','/forgot-password.html','/reset-password.html','https://store.test@evil.test/x','/\\evil.test/x']) {
 assert.equal(context().flow.safeReturn(attack),'/index.html',attack);checks++;
}
const login=context('/login.html',{redirect_after_login:'/cart.html'});
assert.equal(login.callbacks.length,0,'login events cannot race and save login as return target');checks++;
await login.flow.finishSignIn();assert.equal(login.redirects[0],'mfa.html');assert.equal(login.values.get('meem_mfa_return'),'/cart.html');checks+=2;
const completed=context('/mfa.html',{meem_mfa_return:'/cart.html'});completed.setAal('aal2');await completed.flow.finishSignIn();assert.equal(completed.redirects[0],'/cart.html');assert.equal(completed.values.size,0);checks+=2;
const legacy=context('/mfa.html',{meem_mfa_return:'/login.html'});legacy.setAal('aal2');await legacy.flow.finishSignIn();assert.equal(legacy.redirects[0],'/index.html');checks++;
let consentCalls=0,finishConsent;
const account=context('/login.html');account.ctx.window.MeemReceiptConsent={mode:'account',require:()=>{consentCalls++;return new Promise(resolve=>{finishConsent=resolve;});}};
await account.flow.finishSignIn();assert.equal(consentCalls,0,'MFA precedes account consent');checks++;
const verified=context('/verify.html');verified.setAal('aal2');verified.ctx.window.MeemReceiptConsent=account.ctx.window.MeemReceiptConsent;
const completing=verified.flow.finishSignIn();await new Promise(resolve=>setImmediate(resolve));
assert.equal(consentCalls,1);assert.equal(verified.redirects.length,0,'verification awaits the single consent action');checks+=2;
finishConsent(false);await completing;assert.equal(verified.redirects[0],'/index.html','decline permits browsing; server still denies receipt processing');checks++;
const utils={window:{}};vm.createContext(utils);vm.runInContext(fs.readFileSync('assets/js/banner-utils.js','utf8'),utils);const u=utils.window.MeemBannerUtils;
for(const tz of ['UTC','Africa/Khartoum','America/New_York','Asia/Tokyo']) {
 process.env.TZ=tz;
 assert.equal(u.khartoumToUtc('2026-10-18T18:30'),'2026-10-18T16:30:00.000Z');
 assert.equal(u.utcToKhartoum('2026-10-18T16:30:00Z'),'2026-10-18T18:30');checks+=2;
}
assert.throws(()=>u.khartoumToUtc('2026-02-31T12:00'));assert.throws(()=>u.khartoumToUtc('garbage'));checks+=2;
assert.equal(u.mobileBox('3:2').h,720);assert.equal(u.mobileBox('16:9').h,608);checks+=2;
// Slow factor discovery must not expose an actionable verification form.
let resolveFactors, submitted=0;
const nodes=Object.fromEntries(['error','verify','mfaForm','code','logout'].map(id=>[id,{disabled:false,value:'123456',addEventListener(type,handler){this[type]=handler;}}]));
const challengeContext={document:{getElementById:id=>nodes[id]},location:{replace(){}},window:{MeemAuthFlow:{finishSignIn:async()=>{}},supabaseClient:{auth:{getSession:async()=>({data:{session:{}}}),mfa:{
 getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:'aal1',nextLevel:'aal2'}}),
 listFactors:()=>new Promise(resolve=>{resolveFactors=resolve;}),
 challengeAndVerify:async()=>{submitted++;return {error:new Error('invalid')};}
}}}}};
vm.createContext(challengeContext);vm.runInContext(fs.readFileSync('assets/js/mfa.js','utf8'),challengeContext);
await new Promise(resolve=>setImmediate(resolve));
assert.equal(nodes.verify.disabled,true);await nodes.mfaForm.submit({preventDefault(){}});assert.equal(submitted,0);checks+=2;
resolveFactors({data:{totp:[{id:'test-factor',status:'verified'}]}});await new Promise(resolve=>setImmediate(resolve));
assert.equal(nodes.verify.disabled,false);await nodes.mfaForm.submit({preventDefault(){}});assert.equal(submitted,1);assert.equal(nodes.verify.disabled,false);checks+=3;
console.log(`Auth/banner client: ${checks} passed (MFA return paths, redirect attacks, Khartoum across four device timezones).`);
