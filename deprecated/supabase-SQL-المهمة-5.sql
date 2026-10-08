-- RAIZEY STORE — Task 5: categories, product grouping, and configurable delivery badges
-- Migration قابلة لإعادة التشغيل، وتحافظ على البيانات الموجودة ولا تنشئ تصنيفات افتراضية تلقائيًا.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  image_url text,
  display_order integer NOT NULL DEFAULT 0,
  commission_percent numeric(5,2) NOT NULL DEFAULT 3,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS name text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS image_url text,
  ADD COLUMN IF NOT EXISTS display_order integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_percent numeric(5,2) NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- لا نعدّل أسماء الأقسام القديمة؛ نملأ القيم المفقودة فقط.
UPDATE public.categories
SET name = COALESCE(NULLIF(btrim(name), ''), 'تصنيف')
WHERE name IS NULL OR btrim(name) = '';

ALTER TABLE public.categories
  ALTER COLUMN name SET NOT NULL;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS category_id uuid,
  ADD COLUMN IF NOT EXISTS delivery_badge_text text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'products_category_id_fkey'
      AND conrelid = 'public.products'::regclass
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_category_id_fkey
      FOREIGN KEY (category_id)
      REFERENCES public.categories(id)
      ON DELETE SET NULL
      NOT VALID;
  END IF;
END $$;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_delivery_badge_text_length;
ALTER TABLE public.products
  ADD CONSTRAINT products_delivery_badge_text_length
  CHECK (delivery_badge_text IS NULL OR char_length(delivery_badge_text) <= 120);

CREATE INDEX IF NOT EXISTS idx_categories_active_order
  ON public.categories (is_active, display_order, name);
CREATE INDEX IF NOT EXISTS idx_products_category_active_order
  ON public.products (category_id, is_active, display_order);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS categories_select_active ON public.categories;
DROP POLICY IF EXISTS categories_select ON public.categories;
CREATE POLICY categories_select_active
  ON public.categories FOR SELECT
  USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS categories_admin_all ON public.categories;
DROP POLICY IF EXISTS categories_admin ON public.categories;
CREATE POLICY categories_admin_all
  ON public.categories FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

GRANT SELECT ON public.categories TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.categories TO authenticated;
GRANT SELECT ON public.products TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;

NOTIFY pgrst, 'reload schema';
