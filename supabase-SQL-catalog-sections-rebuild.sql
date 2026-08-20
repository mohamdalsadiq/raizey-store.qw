-- RAIZEY catalog rebuild: sections -> categories -> products
-- This migration archives the old catalog instead of deleting rows, preserving orders.

CREATE TABLE IF NOT EXISTS public.store_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  display_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT store_sections_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT store_sections_name_unique UNIQUE (name)
);

ALTER TABLE public.categories
  ADD COLUMN IF NOT EXISTS section_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'categories_section_id_fkey'
      AND conrelid = 'public.categories'::regclass
  ) THEN
    ALTER TABLE public.categories
      ADD CONSTRAINT categories_section_id_fkey
      FOREIGN KEY (section_id)
      REFERENCES public.store_sections(id)
      ON DELETE RESTRICT;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS store_sections_active_order_idx
  ON public.store_sections (is_active, display_order, name);

CREATE INDEX IF NOT EXISTS categories_section_active_order_idx
  ON public.categories (section_id, is_active, display_order, name);

ALTER TABLE public.store_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS store_sections_public_read ON public.store_sections;
CREATE POLICY store_sections_public_read
  ON public.store_sections
  FOR SELECT
  USING (is_active = true OR (public.is_admin() AND public.has_admin_permission('manage_products')));

DROP POLICY IF EXISTS store_sections_admin_insert ON public.store_sections;
CREATE POLICY store_sections_admin_insert
  ON public.store_sections
  FOR INSERT
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

DROP POLICY IF EXISTS store_sections_admin_update ON public.store_sections;
CREATE POLICY store_sections_admin_update
  ON public.store_sections
  FOR UPDATE
  USING (public.is_admin() AND public.has_admin_permission('manage_products'))
  WITH CHECK (public.is_admin() AND public.has_admin_permission('manage_products'));

DROP POLICY IF EXISTS store_sections_admin_delete ON public.store_sections;
CREATE POLICY store_sections_admin_delete
  ON public.store_sections
  FOR DELETE
  USING (public.is_admin() AND public.has_admin_permission('manage_products'));

GRANT SELECT ON public.store_sections TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.store_sections TO authenticated;

-- Archive the existing catalog only. Orders, profiles, wallets, payments, and logs stay untouched.
UPDATE public.products
SET is_active = false
WHERE is_active = true;

UPDATE public.subcategories
SET is_active = false
WHERE is_active = true;

UPDATE public.categories
SET is_active = false,
    section_id = NULL
WHERE is_active = true;

-- Keep updated_at current for future section edits.
CREATE OR REPLACE FUNCTION public.set_store_sections_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS store_sections_updated_at ON public.store_sections;
CREATE TRIGGER store_sections_updated_at
  BEFORE UPDATE ON public.store_sections
  FOR EACH ROW EXECUTE FUNCTION public.set_store_sections_updated_at();

GRANT EXECUTE ON FUNCTION public.set_store_sections_updated_at() TO authenticated;

-- This trigger helper is internal; clients never need to call it directly.
REVOKE EXECUTE ON FUNCTION public.set_store_sections_updated_at() FROM PUBLIC, authenticated;
