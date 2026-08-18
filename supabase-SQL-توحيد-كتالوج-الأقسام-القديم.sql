-- RAIZEY STORE — توحيد كتالوج Category -> Products
-- هذا الملف يعالج سجلات الكتالوج الانتقالية فقط.
-- لا يحذف orders أو wallet_topups أو products؛ ينقل منتجات PUBG إلى قسم الألعاب ثم يعطّل الأقسام المكررة.
BEGIN;

-- القسم الذي يحتوي المنتج القديم ذي الخيارات هو القسم canonical للألعاب.
UPDATE public.categories
SET name = 'الألعاب', display_order = 1, is_active = true
WHERE id = 'd1a7a9cf-13fc-492a-b091-50d24d60f482';

-- نقل منتجات PUBG من القسم المكرر إلى قسم الألعاب قبل تعطيل القسم المكرر.
UPDATE public.products
SET category_id = 'd1a7a9cf-13fc-492a-b091-50d24d60f482'
WHERE category_id = 'fe140dfa-b730-4187-b7d1-4dfd2f8b8e3d';

-- الأقسام المكررة/الفارغة لا تظهر للعميل، مع إبقاء السجلات للتراجع والمراجعة.
UPDATE public.categories
SET is_active = false
WHERE id IN (
  '1ac029af-8fef-4870-9702-697ac2cac883',
  'fe140dfa-b730-4187-b7d1-4dfd2f8b8e3d'
);

-- صفحة التصنيفات القديمة لم تعد جزءاً من المسار النشط؛ عطّل سجلاتها الانتقالية.
UPDATE public.subcategories
SET is_active = false
WHERE is_active IS DISTINCT FROM false;

-- امنع إنشاء قسمين نشطين بالاسم نفسه مع تجاهل حالة الأحرف والمسافات.
CREATE UNIQUE INDEX IF NOT EXISTS uq_categories_active_name_ci
ON public.categories (lower(btrim(name)))
WHERE is_active = true;

COMMIT;
