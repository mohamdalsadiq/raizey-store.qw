/* Account consent. Server RPCs are the evidence; memory is display cache only. */
(function () {
  'use strict';
  if (window.MeemReceiptConsent?.mode === 'account') return;
  const client = window.supabaseClient;
  let owner=null, generation=0, cached=null, cachedAt=0, reading=null, pending=null, dialog=null;
  let failure='';
  const DISPLAY_KEY='meem_receipt_prompt:';
  function displayUser(id) {
    try {
      if(sessionStorage.getItem(DISPLAY_KEY+'user')!==id) {
        for(const key of Object.keys(sessionStorage)) if(key.startsWith(DISPLAY_KEY)) sessionStorage.removeItem(key);
        if(id) sessionStorage.setItem(DISPLAY_KEY+'user',id);
      }
    } catch (_) { /* Display cache is optional, never authorization. */ }
  }
  const resetListeners=new Set();
  function reset(id=null) {
    const hadOwner=owner!==null;
    owner=id;displayUser(id);generation++;cached=null;cachedAt=0;reading=null;
    if (dialog?.open) dialog.close('account_changed');
    if(hadOwner || id===null) for (const listener of resetListeners) listener();
  }
  async function snapshot() {
    const before=generation;
    const {data,error}=await client.auth.getSession();
    if (error) throw new Error('consent_session_unavailable');
    const user=data?.session?.user;
    if(before!==generation && (user?.id||null)!==owner) throw new Error('consent_account_changed');
    if ((user?.id||null)!==owner) reset(user?.id||null);
    if (!user) throw new Error('auth_required');
    return data.session;
  }
  async function session() {return (await snapshot()).user;}
  async function rpc(name,body,expectedOwner=owner) {
    const current=await snapshot(), revision=generation;
    if(current.user.id!==expectedOwner) throw new Error('consent_account_changed');
    // Pin this action to the authenticated session that displayed the prompt.
    // A concurrent switch must never send A's acknowledgement with B's token.
    const response=await fetch(window.SUPABASE_URL+'/rest/v1/rpc/'+name,{method:'POST',credentials:'omit',
      headers:{apikey:window.SUPABASE_ANON_KEY,Authorization:'Bearer '+current.access_token,'Content-Type':'application/json'},
      body:JSON.stringify(body||{}),signal:AbortSignal.timeout(10000)});
    const data=await response.json();
    if(revision!==generation || current.user.id!==owner) throw new Error('consent_account_changed');
    return {data:response.ok?data:null,error:response.ok?null:data};
  }
  async function status(force=false) {
    await session();
    if (!force && cached && Date.now()-cachedAt<30000) return cached;
    if (reading) return reading;
    const revision=generation,id=owner;
    const task=(async()=>{
      const {data,error}=await rpc('get_receipt_policy_status');
      if (revision!==generation || id!==owner) throw new Error('consent_account_changed');
      if (error || !data || typeof data.configured!=='boolean') throw new Error('consent_unavailable');
      if (data.configured && (!data.version || data.policy_path!=='/privacy.html' || !/^[a-f0-9]{64}$/.test(data.content_sha256||''))) throw new Error('consent_unavailable');
      cached=data;cachedAt=Date.now();return data;
    })();
    reading=task;
    try {return await task;} finally {if(reading===task) reading=null;}
  }
  function element(tag,text,className) {
    const node=document.createElement(tag);if(text) node.textContent=text;if(className) node.className=className;return node;
  }
  async function prompt(user,initial) {
    const revision=generation,id=owner;
    const node=element('dialog',null,'policy-dialog');dialog=node;node.id='receiptPolicyDialog';node.dir='rtl';
    const isNew=Date.now()-Date.parse(user.created_at||'')<15*60*1000;
    const heading=element('h2',isNew?'استكمال إنشاء حسابك':'تحديث موافقة حسابك');heading.id='receiptPolicyHeading';
    node.setAttribute('aria-labelledby',heading.id);
    const copy=element('p','يتطلب الدفع البنكي وشحن المحفظة معالجة آلية إلزامية لصورة الإيصال. قد تتضمن الصورة أسماء وأرقام حسابات ومبلغاً ومرجعاً. القراءة الآلية لا تثبت وصول المال.');
    const policy=element('a','اقرأ سياسة معالجة الإيصالات كاملة');policy.href='/privacy.html?v='+encodeURIComponent(initial.version||'');policy.target='_blank';policy.rel='noopener';
    const version=element('p',initial.configured?'إصدار السياسة: '+initial.version:'معالجة الإيصالات غير متاحة إلى حين اكتمال مراجعة شروط المزود.');
    const label=element('label',null,'mm-check');const checkbox=element('input');checkbox.type='checkbox';checkbox.id='accountReceiptPolicy';
    label.append(checkbox,element('span','قرأت السياسة وأوافق صراحةً على معالجة الإيصالات وفق هذا الإصدار لحسابي.'));
    const error=element('p');error.id='receiptPolicyError';error.setAttribute('role','alert');
    const save=element('button','حفظ الموافقة ومتابعة','mm-btn mm-btn--primary');save.type='button';save.disabled=!initial.configured;
    const decline=element('button','المتابعة دون معالجة إيصالات','mm-btn');decline.type='button';
    node.append(heading,copy,policy,version,...(initial.configured?[label]:[]),error,...(initial.configured?[save]:[]),decline);document.body.appendChild(node);
    let saving=false;
    const result=new Promise(resolve=>node.addEventListener('close',()=>resolve(node.returnValue==='accepted' && revision===generation && id===owner),{once:true}));
    decline.addEventListener('click',()=>node.close('declined'));
    node.addEventListener('cancel',event=>{if(saving) event.preventDefault();});
    save.addEventListener('click',async()=>{
      if(saving || revision!==generation || id!==owner) return;
      if(!checkbox.checked){error.textContent='اقرأ السياسة ثم اختر الموافقة قبل الحفظ.';checkbox.focus();return;}
      saving=true;save.disabled=true;decline.disabled=true;error.textContent='';
      try {
        await session();
        if(revision!==generation || id!==owner) return;
        const {data,error:failure}=await rpc('accept_receipt_policy',{p_version:initial.version,p_method:isNew?'signup_confirmed':'account_prompt'});
        if(revision!==generation || id!==owner) return;
        if(failure || data?.configured!==true || data.accepted!==true || data.version!==initial.version || data.content_sha256!==initial.content_sha256) throw new Error('consent_save_failed');
        cached=data;cachedAt=Date.now();node.close('accepted');
      } catch (_) {cached=null;error.textContent='لم تُحفظ الموافقة. تحقق من الاتصال؛ إذا تغيّر إصدار السياسة فأغلق النافذة وأعد المحاولة.';}
      finally {saving=false;save.disabled=false;decline.disabled=false;}
    });
    // Do not stack this over contact onboarding or any other modal.
    while(document.querySelector('dialog[open]')) {
      if(revision!==generation || id!==owner){node.remove();return false;}
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    if(revision!==generation || id!==owner){node.remove();return false;}
    node.showModal();(initial.configured?checkbox:decline).focus();
    try{sessionStorage.setItem(DISPLAY_KEY+id+':'+(initial.version||'pending'),'seen');}catch(_){}
    try{return await result;}finally{node.remove();if(dialog===node) dialog=null;}
  }
  async function requireConsent() {
    if(pending) return pending;
    const task=(async()=>{
      try {
        const user=await session();
        if(window.MeemAuthFlow && !(await window.MeemAuthFlow.ensureMfa(location.pathname+location.search))) return false;
        const state=await status();
        if(state.configured && state.accepted===true) return true;
        const accepted=await prompt(user,state);
        failure=accepted?'':state.configured?'consent_declined':'receipt_provider_review_pending';return accepted;
      } catch (error) {failure=error.message;return false;}
    })();
    pending=task;try{return await task;}finally{if(pending===task) pending=null;}
  }
  window.MeemReceiptConsent=Object.freeze({mode:'account',require:requireConsent,status,
    context:()=>owner, userId:()=>owner,bindChange:callback=>resetListeners.add(callback),invalidate:()=>{cached=null;cachedAt=0;},
    message:()=>failure==='receipt_provider_review_pending'?'معالجة الإيصالات معلقة لحين اكتمال مراجعة شروط المزود. لم تبدأ المعالجة.':failure==='consent_declined'?'لم تُقبل سياسة معالجة الإيصالات؛ يمكنك التصفح دون إرسال صورة.':failure==='auth_required'?'سجل الدخول قبل معالجة الإيصال.':'تعذر التحقق من موافقة حسابك. تحقق من الاتصال وأعد المحاولة؛ لم تبدأ المعالجة.'});
  async function onboard() {
    try {
      await session();const state=await status();
      if(state.configured && state.accepted) return;
      try{if(sessionStorage.getItem(DISPLAY_KEY+owner+':'+(state.version||'pending'))==='seen') return;}catch(_){}
      await requireConsent();
    } catch (_) { /* Banking explicitly retries; no catalog dependency. */ }
  }
  client.auth.onAuthStateChange((event,current)=>{
    const id=current?.user?.id||null;
    if(id!==owner || event==='SIGNED_OUT') reset(id);
    // The SDK holds its auth lock in this callback; all RPC work is deferred.
    if(id && event==='SIGNED_IN' && !window.MeemAuthFlow?.isAuthPage()) setTimeout(async()=>{if(pending) await pending;await onboard();},0);
  });
  const signup=document.querySelector('.signup-consent');
  if(signup) signup.replaceChildren(document.createTextNode('بعد تأكيد هويتك بالبريد أو جوجل، ستظهر موافقة واحدة لحسابك على معالجة الإيصالات. يمكنك تصفح المتجر دون قبول المعالجة. '),Object.assign(element('a','سياسة الخصوصية'),{href:'/privacy.html'}));
  if(!window.MeemAuthFlow?.isAuthPage()) setTimeout(onboard,0);
})();
