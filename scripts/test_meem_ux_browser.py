"""Deterministic browser layout fixtures. No provider, real account, payment or mail."""
import base64,json,time,os,tempfile,subprocess,socket,atexit
from pathlib import Path
from urllib.parse import urlparse,parse_qs
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'delivery/meem-ux/evidence';(OUT/'screenshots').mkdir(parents=True,exist_ok=True)
BASE='http://127.0.0.1:3010'
UID='a6180000-0000-4000-8000-0000000000a1';PID='5ed73edb-86df-4acf-afb0-fd01fb3a827e';CID='2896f109-eaba-4bf8-bc62-8f670ef19d89';SID='191fb43b-4063-48c4-be8a-6fcb9b2561b5'
product={'id':PID,'name':'منتج تجريبي باسم عربي طويل لاختبار التفاف النص','description':'بيانات اصطناعية للاختبار المحلي فقط','image_url':'/assets/img/meem-mark-192.png','price_usd':1,'category_id':CID,'required_fields':[],'options':[],'is_active':True}
category={'id':CID,'section_id':SID,'name':'قسم تجريبي طويل','description':'كتالوج اصطناعي','image_url':'/assets/img/meem-mark-192.png','display_order':1,'is_active':True,'icon_mode':'auto'}
method={'id':'a6180000-0000-4000-8000-000000000020','name':'بنك تجريبي باسم طويل جداً للاختبار','account_name':'اسم اصطناعي طويل جداً وليس بيانات عميل','account_number':'123456789012345678901234567890','icon_url':'/missing-bank-fixture.png','bank_key':'bankak','is_active':True}
def jwt():
 enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
 return enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':UID,'aal':'aal1','exp':int(time.time())+3600,'role':'authenticated'})+'.c3ludGhldGlj'
def fixture(route):
 u=urlparse(route.request.url);q=parse_qs(u.query);name=u.path.split('/')[-1];obj='application/vnd.pgrst.object+json' in route.request.headers.get('accept','')
 data=[]
 if name=='get_session_security_context':data={'allowed':True}
 elif name=='get_own_onboarding_status':data={'has_whatsapp':True}
 elif name=='get_banners_public':data=json.loads((ROOT/'assets/banners/default-banners.json').read_text())
 elif name in ['is_admin','has_admin_permission']:data=False
 elif name=='products':data=[product]
 elif name=='categories':data=[category]
 elif name=='store_sections':data=[{'id':SID,'name':'الخدمات التجريبية','display_order':1,'description':'اختبار'}]
 elif name=='payment_methods':data=[method,{'id':'a6180000-0000-4000-8000-000000000021','name':'وسيلة بلا شعار','account_number':'999999','is_active':True}]
 elif name=='wallets':data=[{'balance':15000}]
 elif name=='profiles':data=[{'id':UID,'full_name':'حساب اختبار اصطناعي','is_banned':False,'whatsapp_number':'+249912345678'}]
 elif name=='store_settings':data={'maintenance_mode':False}
 elif name=='settings':
  data=[{'key':'usd_to_sdg_rate','value':'1500'},{'key':'profit_margin_percent','value':'0'},{'key':'banner_mobile_ratio','value':'16:9'},{'key':'banner_autoplay','value':'false'}]
  if q.get('key',[''])[0].startswith('eq.'):data={'value':'false'}
 elif name=='user':data={'id':UID,'email':'fixture@example.invalid','aud':'authenticated','role':'authenticated','app_metadata':{},'user_metadata':{},'factors':[]}
 if obj and isinstance(data,list):data=data[0] if data else None
 route.fulfill(status=200,content_type='application/json',body=json.dumps(data),headers={'access-control-allow-origin':'*','content-range':'0-0/0'})
fixture_file=tempfile.NamedTemporaryFile(mode='w',suffix='.json',delete=False)
json.dump({'products':[product],'categories':[category]},fixture_file);fixture_file.close()
server=subprocess.Popen(['node',str(ROOT/'scripts/serve.mjs'),'--port=3010','--built','--catalog-fixture='+fixture_file.name],cwd=ROOT,stdout=subprocess.DEVNULL)
def cleanup():
 server.terminate();server.wait(timeout=10);Path(fixture_file.name).unlink(missing_ok=True)
atexit.register(cleanup)
for attempt in range(50):
 try:
  with socket.create_connection(('127.0.0.1',3010),timeout=.1):break
 except OSError:time.sleep(.1)
results=[];errors=[]
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=os.environ.get('CHROME_PATH','/usr/bin/chromium'),headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
 for width in [360,390,412,768,1024,1440]:
  for theme in ['dark','light']:
   ctx=b.new_context(viewport={'width':width,'height':900},reduced_motion='reduce',locale='ar')
   ctx.route('https://**',lambda r:r.abort());ctx.route('https://rglbfizqolrenwfsndyv.supabase.co/**',fixture)
   session={'access_token':jwt(),'refresh_token':'synthetic','expires_in':3600,'expires_at':int(time.time())+3600,'token_type':'bearer','user':{'id':UID,'email':'fixture@example.invalid','aud':'authenticated','role':'authenticated','app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z','factors':[]}}
   ctx.add_init_script("localStorage.setItem('raizey-auth',"+json.dumps(json.dumps(session))+");localStorage.setItem('meem_store_cart',"+json.dumps(json.dumps([{'id':PID,'product_id':PID,'name':'منتج اصطناعي','quantity':1,'price':1500,'price_sdg':1500,'price_usd':1,'required_fields':{}}]))+");")
   page=ctx.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
   for name,url in [('home','/'),('category','/category.html?id='+CID),('product','/product.html?id='+PID),('cart','/cart.html'),('checkout','/checkout-v2.html'),('wallet','/wallet.html'),('register','/register.html')]:
    try:
     page.goto(BASE+url,wait_until='domcontentloaded');page.wait_for_timeout(180)
     page.evaluate('(theme)=>document.documentElement.setAttribute("data-theme",theme)',theme)
     if name=='checkout' and page.locator('#bankOption').is_visible():
      page.locator('#bankOption').click();page.locator('.method-card').first.click()
     if name=='wallet' and page.locator('#toggleFormBtn').is_visible():
      page.locator('#toggleFormBtn').click();page.locator('#methodSelect').select_option(method['id'])
     if name=='register' and '/register.html' not in page.url:continue
     page.evaluate("""()=>{let m=document.createElement('div');m.textContent='اختبار محلي — بيانات اصطناعية';m.style='position:fixed;top:0;left:0;z-index:99999;background:#fff;color:#000;font:12px sans-serif;padding:3px';document.body.append(m)}""")
     page.evaluate('document.fonts.ready')
     audit=page.evaluate("""()=>({overflow:document.documentElement.scrollWidth-innerWidth,bodyFont:getComputedStyle(document.body).fontSize,fontLoaded:document.fonts.check('400 16px Cairo'),fontRequests:performance.getEntriesByType('resource').filter(r=>r.name.includes('.woff2')).map(r=>({url:r.name.split('/').pop(),bytes:r.transferSize})),h1:document.querySelectorAll('h1').length,buttons:[...document.querySelectorAll('#saveTxRefBtn,#remainderRefBtn,.copy-account-btn')].filter(e=>e.checkVisibility()).map(e=>({id:e.id,text:e.textContent.trim(),fg:getComputedStyle(e).color,bg:getComputedStyle(e).backgroundColor,height:e.getBoundingClientRect().height}))})""")
     results.append({'page':name,'width':width,'theme':theme,**audit,'fixture':True})
     if width in [390,1440] and name in ['home','product','category','register','checkout','wallet']:
      page.screenshot(path=str(OUT/'screenshots'/f'{name}-{width}-{theme}.png'),full_page=True)
     if width==390 and name in ['checkout','wallet']:
      page.evaluate("document.documentElement.style.fontSize='200%'")
      results.append({'page':name,'width':width,'theme':theme,'zoom':'200% text','overflow':page.evaluate('document.documentElement.scrollWidth-innerWidth')})
      page.evaluate("document.documentElement.style.fontSize=''")
    except Exception as e:errors.append(name+': '+str(e)[:250])
   ctx.close()
 b.close()
(OUT/'browser-layout.json').write_text(json.dumps({'scope':'local deterministic fixtures; synthetic client session; no server authorization or actual device verification','results':results,'errors':errors},ensure_ascii=False,indent=2))
print(json.dumps({'views':len(results),'errors':errors,'overflow':[r for r in results if r.get('overflow',0)>2],'fontFailures':[r for r in results if r.get('fontLoaded') is False]},ensure_ascii=False))
assert not errors
assert not any(r.get('overflow',0)>2 for r in results)
