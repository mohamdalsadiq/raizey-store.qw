-- RAIZEY STORE — توحيد حالة الخيارات الاختيارية
-- آمن على الطلبات: يضيف trigger على products فقط ولا يغيّر orders أو wallet_topups.
BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_product_options_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.has_options, false) IS NOT TRUE THEN
    NEW.has_options := false;
    NEW.options := '[]'::jsonb;
  ELSE
    IF NEW.options IS NULL OR jsonb_typeof(NEW.options) <> 'array' THEN
      NEW.options := '[]'::jsonb;
    END IF;
    IF jsonb_array_length(NEW.options) = 0 THEN
      NEW.has_options := false;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_normalize_options_state ON public.products;
CREATE TRIGGER trg_products_normalize_options_state
BEFORE INSERT OR UPDATE OF options, has_options ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.normalize_product_options_state();

-- تصحيح آمن للبيانات الحالية: لا يلمس المنتجات التي لديها خيارات مفعلة.
UPDATE public.products
SET options = '[]'::jsonb, has_options = false
WHERE COALESCE(has_options, false) = false
  AND options IS DISTINCT FROM '[]'::jsonb;

COMMIT;
