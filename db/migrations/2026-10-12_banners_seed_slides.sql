-- MEEM STORE — Phase 3: the first three storefront slides.
-- Data only. Idempotent (guarded by title). Nothing else is touched.
begin;

with src(banner_style,title,subtitle,cta_text,alt_text,image_desktop_url,image_mobile_url,
         link_type,link_target,whatsapp_message,sort_order) as (
  values
    ('image_text',
     'تواصل معنا مباشرة على واتساب',
     'فريقنا جاهز للرد على استفساراتك ومتابعة طلبك أولاً بأول',
     'ابدأ المحادثة',
     'دعم MEEM STORE عبر واتساب - هاتف وسماعة ومحادثة',
     '/assets/banners/banner-1-desktop.webp','/assets/banners/banner-1-mobile.webp',
     'whatsapp',null,'مرحباً MEEM STORE، عندي استفسار',1),
    ('image_text',
     'ادفع من محفظتك أو بتحويل بنكي مباشر',
     'محفظة داخلية لشحن أسرع، أو دفع مباشر لكل طلب بدون قيود',
     'طرق الدفع',
     'محفظة وبطاقة بنكية وتحويل بنكي - طرق الدفع في MEEM STORE',
     '/assets/banners/banner-2-desktop.webp','/assets/banners/banner-2-mobile.webp',
     'page','wallet.html',null,2),
    ('image_text',
     'اشحن رصيدك فوراً بأفضل الأسعار',
     'شحن ألعاب وبطاقات رقمية بتسليم سريع وأسعار مناسبة',
     'اشحن الآن',
     'يد تحكم وعملات ذهبية وجواهر - شحن الألعاب في MEEM STORE',
     '/assets/banners/banner-3-desktop.webp','/assets/banners/banner-3-mobile.webp',
     'page','index.html#products',null,3)
)
insert into public.banners (
  banner_style, title, subtitle, cta_text, alt_text,
  image_desktop_url, image_mobile_url, link_type, link_target, whatsapp_message,
  overlay_position_desktop, overlay_position_mobile, sort_order, is_active)
select s.banner_style, s.title, s.subtitle, s.cta_text, s.alt_text,
       s.image_desktop_url, s.image_mobile_url, s.link_type, s.link_target, s.whatsapp_message,
       'right', 'top', s.sort_order, true
from src s
where not exists (select 1 from public.banners b where b.title = s.title);

select id, sort_order, link_type, link_target, is_active from public.banners order by sort_order;

commit;
