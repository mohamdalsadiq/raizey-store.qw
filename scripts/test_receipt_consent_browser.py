"""Native SDK/browser + deterministic HTTP consent fixtures, zero provider calls."""
import json,os,time,tempfile,subprocess,socket,base64
from pathlib import Path
from playwright.sync_api import sync_playwright
from lib_meem_browser_fixtures import ROOT,UID,PID,CID,product,category,fixture
OUT=ROOT/'delivery/meem-ux/evidence/consent';OUT.mkdir(parents=True,exist_ok=True)
BASE='http://127.0.0.1:3020';BID='a6180000-0000-4000-8000-0000000000b2'
def token(uid):
 enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
 return enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':uid,'aal':'aal1','exp':int(time.time())+3600,'role':'authenticated'})+'.c3ludGhldGlj'
def user(uid=UID,new=False,google=False):return {'id':uid,'email':'fixture@example.invalid','aud':'authenticated','role':'authenticated','app_metadata':{'provider':'google' if google else 'email'},'user_metadata':{},'created_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()) if new else '2026-01-01T00:00:00Z','factors':[]}
def session(uid=UID,new=False,google=False):return {'access_token':token(uid),'refresh_token':'synthetic-refresh','expires_in':3600,'expires_at':int(time.time())+3600,'token_type':'bearer','user':user(uid,new,google)}
class API:
 def __init__(self):self.accepted=set();self.version='fixture-v1';self.configured=True;self.fail=False;self.fail_status=False;self.hold=False;self.held=None;self.calls=[];self.provider=0
 def status(self,uid):return {'configured':self.configured,'accepted':(uid,self.version) in self.accepted,'version':self.version,'policy_path':'/privacy.html','content_sha256':'a'*64}
 def route(self,r):
  name=r.request.url.split('?')[0].split('/')[-1]
  def reply(data,status=200):r.fulfill(status=status,content_type='application/json',body=json.dumps(data),headers={'access-control-allow-origin':'*'})
  auth=r.request.headers.get('authorization','')
  try:uid=json.loads(base64.urlsafe_b64decode(auth.split(' ')[1].split('.')[1]+'===' )).get('sub',UID)
  except Exception:uid=UID
  if '/functions/v1/' in r.request.url:self.provider+=1;reply({'message':'provider_must_not_be_called'},503);return
  if name=='user':reply(user(uid));return
  if name=='verify':reply(session(new=True));return
  if name=='logout':reply({});return
  if name=='get_receipt_policy_status':
   self.calls.append(('status',uid));reply({'message':'network_unavailable'} if self.fail_status else self.status(uid),503 if self.fail_status else 200);return
  if name=='accept_receipt_policy':
   self.calls.append(('accept',uid));body=r.request.post_data_json
   assert set(body)=={'p_version','p_method'}
   if self.hold:self.held=r;return
   if self.fail:reply({'message':'fixture_save_failed'},500);return
   if body['p_version']!=self.version:reply({'message':'policy_not_current'},400);return
   self.accepted.add((uid,self.version));reply(self.status(uid));return
  fixture(r)
checks=[];errors=[]
def check(name,condition=True):assert condition,name;checks.append(name)
f=tempfile.NamedTemporaryFile(mode='w',suffix='.json',delete=False);json.dump({'products':[product],'categories':[category]},f);f.close()
server=subprocess.Popen(['node',str(ROOT/'scripts/serve.mjs'),'--port=3020','--built','--catalog-fixture='+f.name],cwd=ROOT,stdout=subprocess.DEVNULL)
try:
 for attempt in range(50):
  try:
   with socket.create_connection(('127.0.0.1',3020),timeout=.1):break
  except OSError:time.sleep(.1)
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path=os.environ.get('CHROME_PATH','/usr/bin/chromium'),args=['--no-sandbox','--disable-dev-shm-usage'])
  def setup(data=None):
   ctx=browser.new_context(viewport={'width':390,'height':844},locale='ar',reduced_motion='reduce');api=API()
   ctx.route('https://**',lambda r:r.abort());ctx.route('https://rglbfizqolrenwfsndyv.supabase.co/**',api.route)
   if data:ctx.add_init_script("if(!sessionStorage.getItem('fixture-started')){localStorage.setItem('raizey-auth',"+json.dumps(json.dumps(data))+");sessionStorage.setItem('fixture-started','1')}")
   page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)));return ctx,api,page
  ctx,api,page=setup();page.add_init_script("sessionStorage.setItem('pending_email','fixture@example.invalid')")
  page.goto(BASE+'/verify.html');inputs=page.locator('.otp-digit')
  for i in range(6):inputs.nth(i).fill(str(i+1))
  page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('Email activation waits at a single account prompt',page.url.endswith('/verify.html'))
  page.locator('#receiptPolicyDialog button.mm-btn--primary').click()
  check('Explicit unchecked acknowledgement cannot save',not any(c[0]=='accept' for c in api.calls))
  page.locator('#accountReceiptPolicy').check();page.locator('#receiptPolicyDialog button.mm-btn--primary').click();page.wait_for_url(BASE+'/')
  page.wait_for_timeout(100);check('Email completion saved once then navigated',len([c for c in api.calls if c[0]=='accept'])==1)
  page.goto(BASE+'/wallet.html');page.wait_for_function("() => window.MeemReceiptConsent?.mode==='account'")
  check('Another receipt action reuses server consent',page.evaluate('window.MeemReceiptConsent.require()'))
  check('Repeated wallet action needs no checkbox',page.locator('#geminiConsentWallet').count()==0 and page.locator('#receiptPolicyDialog').count()==0)
  check('Cached display status does not add serial reads',len([c for c in api.calls if c[0]=='accept'])==1);ctx.close()
  ctx,api,page=setup(session(new=True,google=True));page.goto(BASE+'/index.html');page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('Google callback session cannot bypass acceptance',not api.accepted)
  page.evaluate('window.concurrentConsents=[MeemReceiptConsent.require(),MeemReceiptConsent.require()];true')
  check('Concurrent actions share one prompt and one status read',page.locator('dialog[open]').count()==1 and len([c for c in api.calls if c[0]=='status'])==1)
  check('New account gets completion copy','استكمال' in page.locator('#receiptPolicyHeading').inner_text())
  page.locator('#receiptPolicyDialog button').last.click();page.goto(BASE+'/product.html?id='+PID);page.wait_for_timeout(150)
  check('Decline is remembered for display only within session',page.locator('#receiptPolicyDialog').count()==0)
  page.evaluate('window.consentResult=window.MeemReceiptConsent.require();true');page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('A banking action still requires real acceptance after display dismissal',not api.accepted)
  api.fail=True;page.locator('#accountReceiptPolicy').check();page.locator('#receiptPolicyDialog button.mm-btn--primary').click();page.wait_for_function("() => document.querySelector('#receiptPolicyError').textContent.length>0")
  check('Save failure is never shown as accepted',not api.accepted and page.locator('#receiptPolicyDialog').is_visible())
  api.fail=False;page.locator('#receiptPolicyDialog button.mm-btn--primary').click();page.wait_for_function("() => !document.querySelector('#receiptPolicyDialog')")
  check('Retry saves a single server acceptance',len(api.accepted)==1)
  api.version='fixture-v2';page.evaluate('MeemReceiptConsent.invalidate();window.consentResult=MeemReceiptConsent.require();true');page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('New version prompts once and is not backfilled',(UID,'fixture-v2') not in api.accepted)
  page.locator('#accountReceiptPolicy').check();page.locator('#receiptPolicyDialog button.mm-btn--primary').click();page.wait_for_function("() => !document.querySelector('#receiptPolicyDialog')")
  check('Only explicitly approved version recorded',(UID,'fixture-v2') in api.accepted)
  check('No provider called during onboarding tests',api.provider==0);ctx.close()
  ctx,api,page=setup(session());page.goto(BASE+'/index.html');page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('Returning account gets update copy','تحديث' in page.locator('#receiptPolicyHeading').inner_text())
  api.hold=True;page.locator('#accountReceiptPolicy').check();page.locator('#receiptPolicyDialog button.mm-btn--primary').click()
  for _ in range(50):
   if api.held:break
   page.wait_for_timeout(10)
  check('Acceptance request bound to displayed user',api.calls[-1]==('accept',UID))
  page.evaluate('(s)=>supabaseClient.auth.setSession(s)',{'access_token':token(BID),'refresh_token':'synthetic-refresh'})
  api.hold=False;api.accepted.add((UID,api.version));api.held.fulfill(status=200,content_type='application/json',body=json.dumps(api.status(UID)),headers={'access-control-allow-origin':'*'})
  page.wait_for_function("() => MeemReceiptConsent.userId()=== '"+BID+"'");page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('Late A response cannot approve switched account B',(BID,api.version) not in api.accepted)
  page.locator('#receiptPolicyDialog button').last.click();check('No provider called across account switch',api.provider==0)
  check('Account switch clears the previous display cache',not page.evaluate("Object.keys(sessionStorage).some(k=>k.includes('"+UID+"'))"))
  page.evaluate("supabaseClient.auth.signOut({scope:'local'})");page.wait_for_function("() => MeemReceiptConsent.userId()===null")
  check('Sign out clears display memory and session cache',page.evaluate("Object.keys(sessionStorage).filter(k=>k.startsWith('meem_receipt_prompt:')).length") == 0);ctx.close()
  ctx,api,page=setup(session());api.configured=False;page.goto(BASE+'/index.html');page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('Unpublished provider review exposes no acceptance checkbox',page.locator('#accountReceiptPolicy').count()==0)
  check('Draft provider state cannot write acceptance',not api.accepted)
  for theme in ['dark','light']:
   page.evaluate('(t)=>document.documentElement.setAttribute("data-theme",t)',theme)
   page.evaluate("()=>{const n=document.createElement('p');n.textContent='اختبار محلي — بيانات اصطناعية';document.querySelector('#receiptPolicyDialog').prepend(n)}")
   page.screenshot(path=str(OUT/f'pending-provider-{theme}.png'))
  check('No provider called when review pending',api.provider==0);ctx.close()
  ctx,api,page=setup(session());api.fail_status=True;page.goto(BASE+'/wallet.html')
  page.wait_for_function("() => MeemReceiptConsent?.mode==='account'")
  check('Technical status failure blocks processing',page.evaluate('MeemReceiptConsent.require()') is False)
  check('Technical status failure remains explanatory','تعذر' in page.evaluate('MeemReceiptConsent.message()'))
  check('Failed lookup cannot save consent or call provider',not api.accepted and api.provider==0);ctx.close()
  ctx,api,page=setup(session());page.add_init_script("document.addEventListener('DOMContentLoaded',()=>{let d=document.createElement('dialog');d.id='fixtureOtherModal';document.body.append(d);d.showModal();})")
  page.goto(BASE+'/index.html');page.locator('#fixtureOtherModal[open]').wait_for(state='visible');page.wait_for_timeout(250)
  check('Account prompt does not stack over an open modal',page.locator('dialog[open]').count()==1 and not page.locator('#receiptPolicyDialog').is_visible())
  page.evaluate("document.querySelector('#fixtureOtherModal').close()");page.locator('#receiptPolicyDialog').wait_for(state='visible')
  check('Queued prompt opens after the other modal closes',page.locator('dialog[open]').count()==1);ctx.close();browser.close()
 check('No browser JavaScript errors',not errors)
 (OUT/'browser-consent.json').write_text(json.dumps({'scope':'local HTTP/SDK fixtures; not live Google or email or model','checks':checks,'errors':errors,'provider_calls':0},ensure_ascii=False,indent=2))
 print(json.dumps({'passed':len(checks),'checks':checks,'errors':errors,'provider_calls':0},ensure_ascii=False))
finally:
 server.terminate();server.wait(timeout=10);Path(f.name).unlink(missing_ok=True)
