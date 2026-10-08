-- RAIZEY STORE: Conditional Product Options + Absolute Pricing
-- Category → Subcategory/Package → Product → Option Group → Child Option
-- شغّل هذا الملف بعد supabase-SQL-إعادة-هيكلة-الكتالوج.sql.
-- لا يحذف options القديمة ولا products.category_id؛ option_tree هو المسار الجديد المتوافق.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS options_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS option_tree jsonb NOT NULL DEFAULT '[]'::jsonb;

-- المنتجات القديمة التي لديها options تستمر في إظهارها، إلى أن يراجعها المشرف.
UPDATE public.products
SET options_required = true
WHERE options_required = false
  AND jsonb_typeof(COALESCE(options, '[]'::jsonb)) = 'array'
  AND jsonb_array_length(COALESCE(options, '[]'::jsonb)) > 0
  AND jsonb_typeof(COALESCE(option_tree, '[]'::jsonb)) = 'array'
  AND jsonb_array_length(COALESCE(option_tree, '[]'::jsonb)) = 0;

CREATE OR REPLACE FUNCTION public.validate_product_option_tree()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  group_node jsonb;
  option_node jsonb;
  child_node jsonb;
  child_nodes jsonb;
  option_price numeric;
  child_price numeric;
BEGIN
  IF NEW.option_tree IS NULL OR jsonb_typeof(NEW.option_tree) <> 'array' THEN
    RAISE EXCEPTION 'option_tree must be a JSON array';
  END IF;

  IF jsonb_array_length(NEW.option_tree) > 50 THEN
    RAISE EXCEPTION 'option_tree has too many option groups';
  END IF;

  FOR group_node IN SELECT value FROM jsonb_array_elements(NEW.option_tree)
  LOOP
    IF jsonb_typeof(group_node) <> 'object'
       OR COALESCE(NULLIF(trim(group_node->>'id'), ''), '') = ''
       OR COALESCE(NULLIF(trim(group_node->>'label'), ''), '') = ''
       OR jsonb_typeof(COALESCE(group_node->'options', '[]'::jsonb)) <> 'array'
    THEN
      RAISE EXCEPTION 'Each option group requires id, label, and options[]';
    END IF;

    IF jsonb_array_length(COALESCE(group_node->'options', '[]'::jsonb)) > 100 THEN
      RAISE EXCEPTION 'An option group has too many options';
    END IF;

    FOR option_node IN SELECT value FROM jsonb_array_elements(group_node->'options')
    LOOP
      IF jsonb_typeof(option_node) <> 'object'
         OR COALESCE(NULLIF(trim(option_node->>'id'), ''), '') = ''
         OR COALESCE(NULLIF(trim(option_node->>'label'), ''), '') = ''
      THEN
        RAISE EXCEPTION 'Each product option requires id and label';
      END IF;

      option_price := NULLIF(option_node->>'price_usd', '')::numeric;
      IF option_price IS NULL OR option_price < 0 OR option_price > 1000000 THEN
        RAISE EXCEPTION 'Each product option requires a valid non-negative price_usd';
      END IF;

      child_nodes := COALESCE(option_node->'children', '[]'::jsonb);
      IF jsonb_typeof(child_nodes) <> 'array' OR jsonb_array_length(child_nodes) > 100 THEN
        RAISE EXCEPTION 'Option children must be an array with at most 100 items';
      END IF;

      FOR child_node IN SELECT value FROM jsonb_array_elements(child_nodes)
      LOOP
        IF jsonb_typeof(child_node) <> 'object'
           OR COALESCE(NULLIF(trim(child_node->>'id'), ''), '') = ''
           OR COALESCE(NULLIF(trim(child_node->>'label'), ''), '') = ''
        THEN
          RAISE EXCEPTION 'Each child option requires id and label';
        END IF;
        child_price := NULLIF(child_node->>'price_usd', '')::numeric;
        IF child_price IS NULL OR child_price < 0 OR child_price > 1000000 THEN
          RAISE EXCEPTION 'Each child option requires a valid non-negative price_usd';
        END IF;
        IF jsonb_typeof(COALESCE(child_node->'children', '[]'::jsonb)) <> 'array'
           OR jsonb_array_length(COALESCE(child_node->'children', '[]'::jsonb)) > 0
        THEN
          RAISE EXCEPTION 'Only one conditional child level is supported';
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  IF NEW.options_required = true AND jsonb_array_length(NEW.option_tree) = 0
     AND jsonb_array_length(COALESCE(NEW.options, '[]'::jsonb)) = 0
  THEN
    RAISE EXCEPTION 'options_required cannot be true without options';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_product_option_tree ON public.products;
CREATE TRIGGER trg_validate_product_option_tree
BEFORE INSERT OR UPDATE OF option_tree, options_required, options ON public.products
FOR EACH ROW EXECUTE FUNCTION public.validate_product_option_tree();

CREATE INDEX IF NOT EXISTS idx_products_option_tree_gin
  ON public.products USING gin (option_tree);

COMMENT ON COLUMN public.products.options_required IS
  'When true, the customer must complete the active option path before checkout.';
COMMENT ON COLUMN public.products.option_tree IS
  'Conditional product option groups. Each group has options[]. Each option may have children[]. All prices are absolute USD prices; the deepest selected price wins.';

NOTIFY pgrst, 'reload schema';
