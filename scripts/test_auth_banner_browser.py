"""Real bundled Supabase SDK + deterministic HTTP fixtures; no real emails or payments."""
import base64, json, os, time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parent.parent
OUT=Path(os.environ.get('SHOTS_DIR','/workspace/.skill-setup/auth-banner-shots'));OUT.mkdir(parents=True,exist_ok=True)
BASE=os.environ.get('BASE_URL','http://127.0.0.1:3000')
rows=json.loads((ROOT/'assets/banners/default-banners.json').read_text())
UID='b6180000-0000-4000-8000-000000000001'
FACTOR='b6180000-0000-4000-8000-000000000099'
sections=[{'id':f'b6180000-0000-4000-8000-{i+200:012d}','name':name,'icon_mode':'auto','display_order':i,'is_active':True} for i,name in enumerate(['الألعاب','AI','توثيقات','بطاقات فيزا'])]
categories=[{'id':f'b6180000-0000-4000-8000-{i+300:012d}','section_id':s['id'],'name':s['name'],'icon_mode':'auto','display_order':i,'is_active':True} for i,s in enumerate(sections)]
checks=[]
def check(name, ok=True):
 assert ok,name
 checks.append(name)
def jwt(aal):
 enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
 return enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':UID,'aal':aal,'exp':int(time.time())+3600,'role':'authenticated'})+'.c3ludGhldGlj'
def user(mfa=True):
 return {'id':UID,'email':'fixture@example.invalid','aud':'authenticated','role':'authenticated','app_metadata':{},'user_metadata':{},'created_at':'2026-10-18T00:00:00Z','factors':[{'id':FACTOR,'factor_type':'totp','status':'verified','friendly_name':'Test'}] if mfa else []}
def session(aal='aal1',mfa=True):
 return {'access_token':jwt(aal),'refresh_token':'synthetic-refresh','token_type':'bearer','expires_in':3600,'expires_at':int(time.time())+3600,'user':user(mfa)}
class API:
 def __init__(self): self.phone=False;self.empty=False;self.admin=False;self.mfa=True;self.calls=[];self.signup=None;self.status_error=False;self.saved=None
 def route(self,r):
  path=urlparse(r.request.url).path;method=r.request.method
  try: data=r.request.post_data_json
  except Exception: data=None
  self.calls.append((path,method,data))
  def reply(payload,status=200):r.fulfill(status=status,content_type='application/json',body=json.dumps(payload),headers={'access-control-allow-origin':'*'})
  if method=='OPTIONS':r.fulfill(status=204,headers={'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'*'});return
  if path.endswith('/token'):reply(session());return
  if path.endswith('/user'):reply(user(self.mfa));return
  if path.endswith('/challenge'):reply({'id':'challenge-test','type':'totp','expires_at':int(time.time())+120});return
  if '/factors/' in path and path.endswith('/verify'):
   reply(session('aal2') if data['code']=='123456' else {'msg':'Invalid code','code':'mfa_verification_failed'},200 if data['code']=='123456' else 422);return
  if path.endswith('/signup'):self.signup=data;reply({'user':user(False),'session':None});return
  if path.endswith('/verify'):reply(session('aal1',False));return
  if path.endswith('/otp'):reply({});return
  if path.endswith('/logout'):reply({});return
  if path.endswith('/get_own_onboarding_status'):reply({'has_whatsapp':self.phone} if not self.status_error else {'message':'connection failed'},200 if not self.status_error else 503);return
  if path.endswith('/complete_whatsapp_onboarding'):
   valid=data['p_phone']=='+249912345678';self.phone=valid
   reply({'completed':True} if valid else {'message':'invalid_whatsapp'},200 if valid else 400);return
  if path.endswith('/get_banners_public'):reply([] if self.empty else rows);return
  if path.endswith('/has_admin_permission'):reply(self.admin);return
  if path.endswith('/validate_referral_short_code'):reply([{'valid':True}]);return
  if path.endswith('/admin_save_banner'):self.saved=data;reply('b6180000-0000-4000-8000-000000000098');return
  if path.endswith('/profiles') and 'id=eq.' not in r.request.url:reply([]);return
  if path.endswith('/profiles'):reply({'role':'admin' if self.admin else 'customer','is_banned':False,'full_name':'Test','whatsapp_number':'+249912345678'});return
  if path.endswith('/get_top_ordered_products'):reply([{'id':'b6180000-0000-4000-8000-000000000055','name':'منتج الاختبار','image_url':'/assets/banners/banner-1-desktop.webp','price_usd':1,'order_count':3}]);return
  if path.endswith('/store_sections'):reply(sections);return
  if path.endswith('/categories'):reply(categories);return
  if path.endswith('/settings') and 'eq.catalog_icons_flag' in r.request.url:reply({'value':'true'});return
  if path.endswith('/settings') and 'eq.home_highlights_flag' in r.request.url:reply({'value':'true'});return
  if path.endswith('/settings') and 'eq.usd_to_sdg_rate' in r.request.url:reply({'value':'150'});return
  if path.endswith('/settings'):reply([{'key':'banner_mobile_ratio','value':'16:9'},{'key':'banner_autoplay','value':'true'},{'key':'banner_interval','value':'5'},{'key':'banner_effect','value':'slide'}]);return
  if path.endswith('/store_settings'):reply({'maintenance_mode':False});return
  if path.endswith('/banners'):reply([{**b,'status':'published','is_active':True,'id':'b6180000-0000-4000-8000-000000000020','starts_at':'2026-10-18T16:30:00Z','ends_at':None} for b in rows[:1]]);return
  if '/storage/v1/object/' in path:reply({'Key':'banners/upload.webp'});return
  if '/rest/v1/' in path:reply([]);return
  reply({})
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 def setup(width=393,height=852,session_data=None,**kwargs):
  ctx=browser.new_context(viewport={'width':width,'height':height},locale='ar',**kwargs)
  api=API();ctx.route('https://**',lambda r:r.abort());ctx.route('https://rglbfizqolrenwfsndyv.supabase.co/**',api.route)
  if session_data:ctx.add_init_script("if (!sessionStorage.getItem('fixture-seeded')) { localStorage.setItem('raizey-auth',"+json.dumps(json.dumps(session_data))+");sessionStorage.setItem('fixture-seeded','1'); }")
  page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  return ctx,api,page,errors
 ctx,api,page,errors=setup()
 page.goto(BASE+'/login.html');page.locator('#email').fill('fixture@example.invalid');page.locator('#password').fill('Synthetic8!password');page.locator('#submitBtn').click();page.wait_for_url('**/mfa.html')
 check('Password login preserves a non-auth MFA return target',page.evaluate("sessionStorage.getItem('meem_mfa_return')")=='/index.html')
 page.locator('#code').fill('000000');page.locator('#verify').click();page.wait_for_function("() => document.querySelector('#error').textContent.length>0")
 check('Wrong TOTP stays at challenge',page.url.endswith('/mfa.html'))
 page.locator('#code').fill('123456');page.locator('#verify').click();page.wait_for_url('**/index.html');page.locator('#whatsappOnboarding').wait_for(state='visible')
 check('Real SDK persists upgraded AAL2 session',page.evaluate("JSON.parse(atob(JSON.parse(localStorage.getItem('raizey-auth')).access_token.split('.')[1])).aal")=='aal2')
 page.keyboard.press('Escape');check('WhatsApp dialog remains mandatory',page.locator('#whatsappOnboarding').is_visible())
 page.locator('#waPhone').fill('123');page.locator('.wa-save').click();page.wait_for_function("() => document.querySelector('#waError').textContent.includes('رقمًا صحيحًا')")
 check('Server rejection is shown and dialog stays open')
 page.locator('#waCountryButton').click();check('Country list excludes Israel',page.locator('[data-country="IL"]').count()==0)
 page.locator('#waCountryPopup input').fill('فلسطين');check('Free Palestine is available',page.locator('[data-country="PS"]').inner_text().find('فلسطين الحرة')>=0)
 page.locator('#waCountryPopup input').fill('+966');page.locator('[data-country="SA"]').click();page.locator('#waPhone').fill('912345678');page.locator('.wa-save').click()
 check('Saudi selection rejects Sudan local number',page.locator('#waError').inner_text().find('السعودية')>=0)
 page.locator('#waCountryButton').click();page.locator('#waCountryPopup input').fill('السودان');page.locator('[data-country="SD"]').click()
 page.locator('#waPhone').fill('+249912345678');page.screenshot(path=str(OUT/'whatsapp-mobile.png'));page.locator('.wa-save').click();page.locator('#whatsappOnboarding').wait_for(state='hidden')
 check('Contact save closes dialog only after success')
 page.reload();page.wait_for_function("() => document.querySelector('#mmHeroSwiper').dataset.ready==='1'");check('Contact persists across reload',not page.locator('#whatsappOnboarding').count())
 check('Auth flow has no JavaScript exceptions',not errors);ctx.close()
 ctx,api,page,errors=setup()
 page.goto(BASE+'/register.html');check('Signup has only three required fields',page.locator('form input[required]').count()==3)
 page.locator('#fullName').fill('عميل الاختبار');page.locator('#email').fill('fixture@example.invalid');page.locator('#password').fill('Synthetic8!password');page.screenshot(path=str(OUT/'register-mobile.png'));page.locator('#submitBtn').click();page.wait_for_url('**/verify.html')
 check('Signup does not transmit phone or privilege fields',set(api.signup['data'])=={'full_name','referral_code_used'})
 for i,n in enumerate('123456'):page.locator('#otpBox input').nth(i).fill(n)
 page.wait_for_url('**/index.html');page.locator('#whatsappOnboarding').wait_for(state='visible');check('Email OTP signup reaches post-login WhatsApp gate')
 check('Signup flow has no JavaScript exceptions',not errors);ctx.close()
 for width,height,reduce in [(320,720,False),(393,852,False),(768,1024,False),(1440,900,False),(393,852,True)]:
  ctx,api,page,errors=setup(width,height,reduced_motion='reduce' if reduce else 'no-preference')
  page.goto(BASE+'/index.html');page.wait_for_function("() => document.querySelector('#mmHeroSwiper').dataset.ready==='1'")
  box=page.locator('#mmHeroSwiper').bounding_box();expected=16/9 if width<768 else 3
  check(f'Banner proportion {width}px',abs(box['width']/box['height']-expected)<.04)
  check(f'No horizontal overflow {width}px',page.evaluate('document.documentElement.scrollWidth<=innerWidth'))
  page.wait_for_function("() => [...document.querySelectorAll('#mmHeroSwiper .swiper-slide-active img')].every(n=>n.complete&&n.naturalWidth>0)");check(f'Active image decodes {width}px')
  check(f'First image priority {width}px',page.locator('#mmHeroSwiper img[fetchpriority="high"]').count()==1)
  if not reduce:
   check(f'No banner arrow or play buttons {width}px',page.locator('#mmHeroPlayPause, #mmHeroNext, #mmHeroPrev').count()==0)
   page.locator('#mmHeroSwiper').focus();page.keyboard.press('Space');page.mouse.move(0,0);page.locator('#mmHeroSwiper').dispatch_event('pointerleave')
   check(f'Explicit pause survives touch/hover {width}px',page.evaluate('!document.querySelector("#mmHeroSwiper").swiper.autoplay.running'))
   current=page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex');page.locator('#mmHeroSwiper').focus();page.keyboard.press('ArrowLeft');page.wait_for_timeout(650)
   check(f'Keyboard next slide {width}px',page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex')!=current)
  else:check('Reduced motion does not auto-play',page.evaluate('!document.querySelector("#mmHeroSwiper").swiper.autoplay.running'))
  page.locator('#sectionRow .section-chip').first.wait_for()
  check(f'Section icons before best sellers {width}px',page.evaluate("Boolean(document.querySelector('#sectionRow').compareDocumentPosition(document.querySelector('#homeTopOrdered')) & Node.DOCUMENT_POSITION_FOLLOWING)"))
  expected_keys=['gamepad-2','brain','badge-check','credit-card']
  actual=page.locator('#sectionRow use').evaluate_all('(nodes)=>nodes.map(n=>n.getAttribute("href"))')
  check(f'Specific new category artwork {width}px',actual==['assets/icons/category-sprite.svg#i-'+k for k in expected_keys])
  page.screenshot(path=str(OUT/f'banner-{width}-{reduce}.png'))
  check(f'Banner no JavaScript exceptions {width}px',not errors);ctx.close()
 ctx,api,page,errors=setup(has_touch=True,is_mobile=True)
 page.goto(BASE+'/index.html');page.wait_for_function("() => document.querySelector('#mmHeroSwiper').dataset.ready==='1'")
 page.locator('#homeTopOrdered h2').wait_for();check('Most purchased above categories',page.evaluate("Boolean(document.querySelector('#homeTopOrdered').compareDocumentPosition(document.querySelector('#categoriesContainer')) & Node.DOCUMENT_POSITION_FOLLOWING)"))
 page.locator('#mmHeroSwiper').focus();sequence=[]
 for _ in range(3):
  page.keyboard.press('ArrowLeft');page.wait_for_timeout(650);sequence.append(page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex'))
 check('Circular forward sequence last to first',sequence==[1,2,0])
 page.keyboard.press('ArrowRight');page.wait_for_timeout(650);check('Previous from first wraps to last',page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex')==2)
 page.evaluate('document.activeElement.blur()');page.mouse.move(0,0)
 hero=page.locator('#mmHeroSwiper').bounding_box();y=hero['y']+hero['height']*.8
 cdp=ctx.new_cdp_session(page)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':100,'y':y}]});page.wait_for_timeout(250)
 check('Holding a finger stops autoplay',page.evaluate('!document.querySelector("#mmHeroSwiper").swiper.autoplay.running'))
 before=page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex')
 for x in [130,180,230,290,340]:cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':x,'y':y}]});page.wait_for_timeout(35)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]});page.wait_for_timeout(700)
 after=page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex');check('Finger swipe changes slide',before!=after)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':340,'y':y}]})
 for x in [290,230,180,130,70]:cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':x,'y':y}]});page.wait_for_timeout(35)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]});page.wait_for_timeout(700)
 check('Reverse finger swipe returns to previous slide',page.evaluate('document.querySelector("#mmHeroSwiper").swiper.realIndex')==before)
 page.locator('#mmHeroSwiper').tap(position={'x':35,'y':hero['height']*.8});check('Tap on artwork pauses',page.locator('#mmHeroSwiper').get_attribute('data-motion')=='paused')
 page.locator('#mmHeroSwiper').tap(position={'x':35,'y':hero['height']*.8});check('Second tap resumes',page.locator('#mmHeroSwiper').get_attribute('data-motion')=='playing')
 ctx.close()
 ctx,api,page,errors=setup();api.empty=True;page.goto(BASE+'/index.html');page.wait_for_function("() => document.querySelector('#mmHeroSwiper').dataset.ready==='1'")
 check('Unpublished all banners does not resurrect fallback ads',page.locator('.mm-slide-default').count()==1);ctx.close()
 ctx,api,page,errors=setup(1280,900,session('aal2'),timezone_id='America/New_York');api.admin=True;api.phone=True
 page.goto(BASE+'/admin.html');page.locator('.admin-banner-shortcut').wait_for()
 check('Canonical navigation retains banner management',page.locator('.admin-nav a[href="admin-banners.html"]').count()==1)
 page.screenshot(path=str(OUT/'admin-banner-shortcut.png'))
 page.locator('.admin-banner-shortcut').click();page.wait_for_url('**/admin-banners.html')
 check('Banner nav is current after dashboard navigation',page.locator('.admin-nav a[aria-current="page"]').get_attribute('href')=='admin-banners.html')
 page.locator('#autoplaySelect').wait_for();page.locator('#addNewBtn').wait_for()
 check('Slider controls reachable from dashboard')
 page.locator('.bn-actions button').first.wait_for();page.locator('.bn-actions button').first.click()
 check('Schedule input is Khartoum in New York browser',page.locator('#startInput').input_value()=='2026-10-18T18:30')
 page.locator('#formSaveBtn').click();page.wait_for_function("() => !document.querySelector('#formModal').classList.contains('show')")
 check('Schedule saves exact UTC instant from any browser',api.saved['p_payload']['starts_at']=='2026-10-18T16:30:00.000Z')
 page.locator('#addNewBtn').click();check('New banner starts as draft',page.locator('#statusInput').input_value()=='draft')
 page.locator('#desktopFileInput').set_input_files(str(ROOT/'assets/banners/banner-1-desktop.webp'));page.wait_for_function("() => document.querySelector('#pvFrame img')?.naturalWidth>0")
 check('Uploaded local image preview renders')
 page.locator('#pvToggle [data-view="mobile"]').click();check('Mobile preview uses mobile dimensions',abs(page.locator('#pvFrame').bounding_box()['width']/page.locator('#pvFrame').bounding_box()['height']-16/9)<.02)
 page.locator('#desktopModeToggle [data-mode="contain"]').click();check('Crop controls survive form reset',not errors)
 page.screenshot(path=str(OUT/'admin-preview.png'))
 page.locator('#statusInput').select_option('published');page.locator('#formSaveBtn').click();page.wait_for_function("() => document.querySelector('#formError').textContent.includes('إلزامي')")
 check('Publishing without alt blocked before upload')
 check('Admin flow no JavaScript exceptions',not errors)
 page.locator('#formCancelBtn').click();page.locator('.admin-nav a[href="admin-sections.html"]').click();page.locator('#addNewBtn').click()
 page.locator('#nameInput').fill('توثيق حسابات');page.locator('.mip-seg-btn').filter(has_text='من المكتبة').click()
 page.locator('.mip-search').fill('فيزا');page.locator('.mip-cell').click()
 check('Arabic icon search selects Visa artwork',page.locator('.mip-preview use').get_attribute('href')=='assets/icons/category-sprite.svg#i-credit-card')
 page.locator('.mip-search').fill('AI');page.locator('.mip-cell').click()
 check('AI artwork selectable from admin',page.locator('.mip-preview use').get_attribute('href')=='assets/icons/category-sprite.svg#i-brain')
 page.locator('.mip-search').fill('');check('All 87 icons available',page.locator('.mip-cell').count()==87)
 page.screenshot(path=str(OUT/'admin-icon-library.png'))
 check('Admin icon picker no JavaScript exceptions',not errors);ctx.close()
 ctx,api,page,errors=setup(session_data=session('aal2'));api.phone=True
 page.goto(BASE+'/admin-banners.html');page.locator('#accessDenied.show').wait_for()
 check('Customer cannot reach banner controls',not page.locator('#addNewBtn').is_visible());ctx.close()
 browser.close()
(OUT/'results.json').write_text(json.dumps({'checks':checks,'count':len(checks)},ensure_ascii=False,indent=2))
print(f'Browser: {len(checks)} checks passed; screenshots: {OUT}')
