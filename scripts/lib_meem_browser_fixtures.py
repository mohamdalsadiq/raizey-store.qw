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
