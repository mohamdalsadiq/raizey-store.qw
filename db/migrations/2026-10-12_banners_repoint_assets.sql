-- MEEM STORE — point the three seeded slides at the canonical repo location
-- assets/banners/banner-N-{desktop,mobile}.webp and correct every alt_text.
--
-- The rows originally referenced /assets/img/banner-*.webp. Those copies stay
-- in the repo as a legacy alias so nothing 404s while this runs, then they can
-- be removed (see the note at the end).
--
-- ROLLBACK: db/rollback/2026-10-12_banners_repoint_assets_rollback.sql
begin;

update public.banners set image_desktop_url = '/assets/banners/banner-1-desktop.webp',
                          image_mobile_url  = '/assets/banners/banner-1-mobile.webp',
                          alt_text = 'دعم MEEM STORE عبر واتساب — هاتف ونص محادثة وسماعة دعم'
where title = 'تواصل معنا مباشرة على واتساب';

update public.banners set image_desktop_url = '/assets/banners/banner-2-desktop.webp',
                          image_mobile_url  = '/assets/banners/banner-2-mobile.webp',
                          alt_text = 'محفظة ذهبية وبطاقة بنكية وبنك — طرق الدفع في MEEM STORE'
where title = 'ادفع من محفظتك أو بتحويل بنكي مباشر';

update public.banners set image_desktop_url = '/assets/banners/banner-3-desktop.webp',
                          image_mobile_url  = '/assets/banners/banner-3-mobile.webp',
                          alt_text = 'يد تحكم وعملات ذهبية وجواهر — شحن الألعاب في MEEM STORE'
where title = 'اشحن رصيدك فوراً بأفضل الأسعار';

select id, sort_order,
       image_desktop_url like '/assets/banners/%' as desktop_ok,
       image_mobile_url  like '/assets/banners/%' as mobile_ok,
       coalesce(length(alt_text), 0) as alt_len
from public.banners order by sort_order;

commit;

-- After this migration is applied and the storefront is confirmed on the new
-- paths, the legacy copies below can be deleted in a follow-up commit:
--   assets/img/banner-1-desktop.webp   assets/img/banner-1-mobile.webp
--   assets/img/banner-2-desktop.webp   assets/img/banner-2-mobile.webp
--   assets/img/banner-3-desktop.webp   assets/img/banner-3-mobile.webp
-- (the @2x and PNG masters are only used by scripts/build_banner_assets.py)
