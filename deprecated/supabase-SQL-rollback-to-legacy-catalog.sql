-- RAIZEY STORE: rollback إلى كتالوج النسخة القديمة
-- شغّل هذا الملف بعد نشر ملفات الواجهة القديمة، وبعد أخذ نسخة احتياطية من قاعدة البيانات.
-- لا يحذف orders أو payment_receipts أو wallet_topups أو products.
-- يوقف التنفيذ إذا وجد منتجًا يعتمد على subcategory_id وحده دون category_id.

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.products') IS NULL THEN
    RAISE EXCEPTION 'public.products does not exist';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.products
    WHERE subcategory_id IS NOT NULL
      AND category_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Rollback stopped: some products have subcategory_id but no category_id. Map them before rollback.';
  END IF;
END $$;

-- إيقاف trigger والتحقق الخاصين بخيارات option_tree الجديدة.
DROP TRIGGER IF EXISTS trg_validate_product_option_tree ON public.products;
DROP FUNCTION IF EXISTS public.validate_product_option_tree();
DROP INDEX IF EXISTS public.idx_products_option_tree_gin;

-- الاحتفاظ بـ options القديمة التي تعتمد عليها واجهة النسخة القديمة.
ALTER TABLE public.products DROP COLUMN IF EXISTS options_required;
ALTER TABLE public.products DROP COLUMN IF EXISTS option_tree;

-- إزالة الربط الجديد فقط؛ category_id القديم يبقى كما هو.
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_subcategory_id_fkey;
ALTER TABLE public.products DROP COLUMN IF EXISTS subcategory_id;

-- لا نحذف subcategories تلقائيًا؛ هذا يحافظ على البيانات ويمكن حذفه يدويًا
-- بعد التأكد من عدم وجود صفحة أو وظيفة تعتمد عليه.
NOTIFY pgrst, 'reload schema';

COMMIT;
