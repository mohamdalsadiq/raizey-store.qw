-- RAIZEY STORE — Strict 3-tier catalog refactor
-- Category → Subcategory/Service → Product/Variant
-- شغّل هذا الملف في Supabase SQL Editor بعد مراجعة نسخة احتياطية.
-- لا يحذف category_id القديم في هذه المرحلة حتى لا تنكسر النسخ المنشورة أثناء الانتقال؛
-- الواجهات الجديدة لا تقرأه ولا تكتب إليه، وتستخدم subcategory_id فقط.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.subcategories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  name text NOT NULL,
  description text,
  image_url text,
  display_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.subcategories
  ADD COLUMN IF NOT EXISTS category_id uuid,
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS display_order integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'subcategories_category_id_fkey'
      AND conrelid = 'public.subcategories'::regclass
  ) THEN
    ALTER TABLE public.subcategories
      ADD CONSTRAINT subcategories_category_id_fkey
      FOREIGN KEY (category_id) REFERENCES public.categories(id)
      ON DELETE RESTRICT NOT VALID;
  END IF;
END $$;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS subcategory_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'products_subcategory_id_fkey'
      AND conrelid = 'public.products'::regclass
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_subcategory_id_fkey
      FOREIGN KEY (subcategory_id) REFERENCES public.subcategories(id)
      ON DELETE RESTRICT NOT VALID;
  END IF;
END $$;

-- ترحيل محافظ للبيانات القديمة: لا نحذف category_id، بل نضع المنتجات غير المرتبطة
-- مؤقتًا داخل تصنيف واضح يمكن للمشرف إعادة تسميته أو توزيع المنتجات منه لاحقًا.
INSERT INTO public.subcategories (category_id, name, description, display_order, is_active)
SELECT c.id, 'منتجات قديمة', 'تصنيف انتقالي لمنتجات المتجر الموجودة قبل تفعيل الهيكل الثلاثي.', 999999, true
FROM public.categories c
WHERE NOT EXISTS (
  SELECT 1 FROM public.subcategories s
  WHERE s.category_id = c.id AND lower(s.name) = lower('منتجات قديمة')
);

UPDATE public.products p
SET subcategory_id = s.id
FROM public.subcategories s
WHERE p.subcategory_id IS NULL
  AND p.category_id IS NOT NULL
  AND s.category_id = p.category_id
  AND lower(s.name) = lower('منتجات قديمة');

-- فهرس فريد غير حساس لحالة الأحرف يمنع تكرار اسم الباقة داخل القسم نفسه.
CREATE UNIQUE INDEX IF NOT EXISTS uq_subcategories_category_name_ci
  ON public.subcategories (category_id, lower(name));
CREATE INDEX IF NOT EXISTS idx_subcategories_category_active_order
  ON public.subcategories (category_id, is_active, display_order, name);
CREATE INDEX IF NOT EXISTS idx_products_subcategory_active_order
  ON public.products (subcategory_id, is_active, display_order, name);

-- لا نفرض أي options: المنتج البسيط بسعره الأساسي صالح بالكامل.
ALTER TABLE public.products
  ALTER COLUMN options SET DEFAULT '[]'::jsonb,
  ALTER COLUMN has_options SET DEFAULT false;

CREATE OR REPLACE FUNCTION public.touch_subcategories_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subcategories_updated_at ON public.subcategories;
CREATE TRIGGER trg_subcategories_updated_at
BEFORE UPDATE ON public.subcategories
FOR EACH ROW EXECUTE FUNCTION public.touch_subcategories_updated_at();

ALTER TABLE public.subcategories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subcategories_public_select ON public.subcategories;
CREATE POLICY subcategories_public_select
  ON public.subcategories FOR SELECT
  USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS subcategories_admin_manage ON public.subcategories;
CREATE POLICY subcategories_admin_manage
  ON public.subcategories FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

-- تقييد الكتابة الجديدة للمنتجات على طبقة التصنيف، مع إبقاء القراءة العامة للمنتجات الفعالة.
DROP POLICY IF EXISTS products_admin_all ON public.products;
DROP POLICY IF EXISTS products_admin_manage ON public.products;
CREATE POLICY products_admin_manage
  ON public.products FOR ALL
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (
    public.is_admin()
    AND public.has_admin_permission('manage_products')
    AND subcategory_id IS NOT NULL
  );

GRANT SELECT ON public.subcategories TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.subcategories TO authenticated;
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;

-- شجرة كتالوج عامة: معلومات العرض فقط، بلا بيانات خاصة.
CREATE OR REPLACE FUNCTION public.get_catalog_tree()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'description', c.description,
      'image_url', c.image_url,
      'display_order', c.display_order,
      'subcategories', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', s.id,
            'category_id', s.category_id,
            'name', s.name,
            'description', s.description,
            'image_url', s.image_url,
            'display_order', s.display_order,
            'products', COALESCE((
              SELECT jsonb_agg(
                jsonb_build_object(
                  'id', p.id,
                  'subcategory_id', p.subcategory_id,
                  'name', p.name,
                  'description', p.description,
                  'image_url', p.image_url,
                  'price_usd', p.price_usd,
                  'compare_at_price_usd', p.compare_at_price_usd,
                  'flash_sale_ends_at', p.flash_sale_ends_at,
                  'delivery_badge_text', p.delivery_badge_text,
                  'is_active', p.is_active,
                  'display_order', p.display_order
                ) ORDER BY p.display_order, p.name
              )
              FROM public.products p
              WHERE p.subcategory_id = s.id AND p.is_active = true
            ), '[]'::jsonb)
          ) ORDER BY s.display_order, s.name
        )
        FROM public.subcategories s
        WHERE s.category_id = c.id AND s.is_active = true
      ), '[]'::jsonb)
    ) ORDER BY c.display_order, c.name
  ), '[]'::jsonb)
  FROM public.categories c
  WHERE c.is_active = true;
$$;

REVOKE ALL ON FUNCTION public.get_catalog_tree() FROM public;
GRANT EXECUTE ON FUNCTION public.get_catalog_tree() TO anon, authenticated;

-- الأكثر شراءً يبقى على مستوى المنتجات، مع إرجاع subcategory_id للعرض الصحيح.
CREATE OR REPLACE FUNCTION public.get_popular_products(p_limit integer DEFAULT 8)
RETURNS TABLE (
  product_id uuid,
  subcategory_id uuid,
  category_id uuid,
  name text,
  description text,
  image_url text,
  price_usd numeric,
  compare_at_price_usd numeric,
  flash_sale_ends_at timestamptz,
  delivery_badge_text text,
  purchase_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.subcategory_id,
    s.category_id,
    p.name,
    p.description,
    p.image_url,
    p.price_usd,
    p.compare_at_price_usd,
    p.flash_sale_ends_at,
    p.delivery_badge_text,
    COUNT(o.id)::bigint
  FROM public.products p
  LEFT JOIN public.subcategories s ON s.id = p.subcategory_id
  LEFT JOIN public.orders o
    ON o.product_id = p.id AND o.status = 'completed'
  WHERE p.is_active = true AND s.is_active = true
  GROUP BY p.id, s.category_id
  ORDER BY COUNT(o.id) DESC, p.display_order ASC, p.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 8), 1), 24);
$$;

REVOKE ALL ON FUNCTION public.get_popular_products(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.get_popular_products(integer) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
