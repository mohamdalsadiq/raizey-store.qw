-- RAIZEY STORE — تراجع تغييرات الكتالوج الأخيرة فقط
-- هذا الملف لا يحذف orders أو products أو wallet_topups أو profiles.
-- شغّله في Supabase SQL Editor إذا أردت إعادة بيانات الكتالوج إلى ما قبل commit 7c9191d.
BEGIN;

-- إزالة trigger والدالة والقيد الذي أُضيفت في آخر إصلاح.
DROP TRIGGER IF EXISTS trg_products_normalize_options_state ON public.products;
DROP FUNCTION IF EXISTS public.normalize_product_options_state();
DROP INDEX IF EXISTS public.uq_categories_active_name_ci;

-- إعادة اسم وترتيب قسم الألعاب إلى القيمة السابقة.
UPDATE public.categories
SET name = 'قسم الالعاب', display_order = 3, is_active = true
WHERE id = 'd1a7a9cf-13fc-492a-b091-50d24d60f482';

-- إعادة تفعيل قسم PUBG القديم الذي كان يحمل منتجات 660 و1800 UC.
UPDATE public.categories
SET is_active = true
WHERE id = 'fe140dfa-b730-4187-b7d1-4dfd2f8b8e3d';

-- إعادة المنتجات التي نُقلت في آخر migration إلى قسمها السابق.
UPDATE public.products
SET category_id = 'fe140dfa-b730-4187-b7d1-4dfd2f8b8e3d'
WHERE id IN (
  '89050728-b72b-439a-be45-7e4d46d084ed',
  'b3e636e5-5d2f-4c34-ba64-0be3364340ab'
)
AND category_id = 'd1a7a9cf-13fc-492a-b091-50d24d60f482';

-- إعادة تفعيل التصنيفات الانتقالية كما كانت قبل آخر إصلاح.
UPDATE public.subcategories
SET is_active = true
WHERE is_active IS DISTINCT FROM true;

COMMIT;

-- ملاحظة: migration الخيارات لم تمسح خيارات فعلية وقت التراجع؛
-- كان عدد المنتجات ذات has_options=false وoptions غير الفارغة يساوي صفراً.
