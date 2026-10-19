-- Contact completion after authentication; compact banners and strict media controls.
-- Additive migration: existing sessions and contact details are preserved.
CREATE OR REPLACE FUNCTION private.normalize_whatsapp(p_phone text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE v text := btrim(translate(coalesce(p_phone,''),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'));
BEGIN
 IF length(v)>32 OR v ~ '[^0-9+() .-]' THEN RETURN NULL; END IF;
 v := regexp_replace(v,'[() .-]','','g');
 IF v LIKE '00%' THEN v := '+' || substr(v,3);
 ELSIF v ~ '^0[19][0-9]{8}$' THEN v := '+249' || substr(v,2);
 ELSIF v ~ '^249[19][0-9]{8}$' THEN v := '+' || v;
 END IF;
 IF v !~ '^\+[1-9][0-9]{3,14}$' THEN RETURN NULL; END IF;
 IF v LIKE '+249%' AND v !~ '^\+249[19][0-9]{8}$' THEN RETURN NULL; END IF;
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION private.normalize_whatsapp(text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.validate_profile_contact()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v text;
BEGIN
 IF TG_OP='INSERT' THEN
  NEW.whatsapp_number := private.normalize_whatsapp(NEW.whatsapp_number);
 ELSIF NEW.whatsapp_number IS DISTINCT FROM OLD.whatsapp_number THEN
  v := private.normalize_whatsapp(NEW.whatsapp_number);
  IF v IS NULL THEN RAISE EXCEPTION 'invalid_whatsapp'; END IF;
  NEW.whatsapp_number := v;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.validate_profile_contact() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS trg_validate_profile_contact ON public.profiles;
CREATE TRIGGER trg_validate_profile_contact BEFORE INSERT OR UPDATE ON public.profiles
 FOR EACH ROW EXECUTE FUNCTION public.validate_profile_contact();

CREATE OR REPLACE FUNCTION public.get_own_onboarding_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_phone text;
BEGIN
 PERFORM private.assert_session_aal();
 IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
 SELECT whatsapp_number INTO v_phone FROM public.profiles WHERE id=auth.uid();
 RETURN jsonb_build_object('has_whatsapp',private.normalize_whatsapp(v_phone) IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.get_own_onboarding_status() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_own_onboarding_status() TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.complete_whatsapp_onboarding(p_phone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v text;
BEGIN
 PERFORM private.assert_session_aal();
 IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
 v := private.normalize_whatsapp(p_phone);
 IF v IS NULL THEN RAISE EXCEPTION 'invalid_whatsapp'; END IF;
 UPDATE public.profiles SET whatsapp_number=v WHERE id=auth.uid();
 IF NOT FOUND THEN RAISE EXCEPTION 'profile_missing'; END IF;
 RETURN jsonb_build_object('completed',true);
END $$;
REVOKE ALL ON FUNCTION public.complete_whatsapp_onboarding(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_whatsapp_onboarding(text) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.require_order_contact()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 -- Trusted background fulfillment may create orders without an interactive JWT.
 IF auth.role()='authenticated' THEN
  PERFORM private.assert_session_aal();
  IF NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
    AND private.normalize_whatsapp(p.whatsapp_number) IS NOT NULL) THEN
   RAISE EXCEPTION 'whatsapp_required';
  END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.require_order_contact() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS trg_require_order_contact ON public.orders;
CREATE TRIGGER trg_require_order_contact BEFORE INSERT ON public.orders
 FOR EACH ROW EXECUTE FUNCTION public.require_order_contact();

-- One project, fixed image formats, no percent-encoded traversal or arbitrary hosts.
CREATE OR REPLACE FUNCTION public.banners_validate_image_url(p_url text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(p_url !~ '\.\.' AND (
  p_url ~ '^/assets/banners/[A-Za-z0-9_@.-]+\.(webp|png|jpg|jpeg)$' OR
  p_url ~ '^https://rglbfizqolrenwfsndyv\.supabase\.co/storage/v1/object/public/banners/([A-Za-z0-9_-]+/)*[A-Za-z0-9_@.-]+\.(webp|png|jpg|jpeg)$'
 ),false);
$$;
REVOKE ALL ON FUNCTION public.banners_validate_image_url(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.banners_validate_image_url(text) TO service_role;
ALTER TABLE public.banners ALTER COLUMN status SET DEFAULT 'draft';
ALTER TABLE public.banners DROP CONSTRAINT IF EXISTS banners_published_alt_check;
ALTER TABLE public.banners ADD CONSTRAINT banners_published_alt_check
 CHECK(status <> 'published' OR length(btrim(alt_text)) BETWEEN 1 AND 160);
ALTER TABLE public.banners DROP CONSTRAINT IF EXISTS banners_trusted_images_check;
ALTER TABLE public.banners ADD CONSTRAINT banners_trusted_images_check
 CHECK(public.banners_validate_image_url(image_desktop_url) AND
       (image_mobile_url IS NULL OR public.banners_validate_image_url(image_mobile_url)));

-- Validate slider settings even if a client bypasses the admin form.
CREATE OR REPLACE FUNCTION public.validate_banner_setting()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF (NEW.key IN ('banner_mobile_ratio','banner_mobile_aspect') AND NEW.value NOT IN ('3:2','16:9','4:3','1:1','4:5','3:4')) OR
    (NEW.key='banner_autoplay' AND NEW.value NOT IN ('true','false')) OR
    (NEW.key='banner_interval' AND NEW.value !~ '^([3-9]|10)$') OR
    (NEW.key='banner_effect' AND NEW.value NOT IN ('slide','fade')) OR
    (NEW.key LIKE 'banner_%' AND NEW.value IS NULL) THEN
  RAISE EXCEPTION 'invalid_banner_setting';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.validate_banner_setting() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS trg_validate_banner_setting ON public.settings;
CREATE TRIGGER trg_validate_banner_setting BEFORE INSERT OR UPDATE ON public.settings
 FOR EACH ROW EXECUTE FUNCTION public.validate_banner_setting();
INSERT INTO public.settings(key,value) VALUES('banner_mobile_ratio','16:9'),('banner_mobile_aspect','16:9')
 ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value;

UPDATE storage.buckets SET file_size_limit=2097152,
 allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp'] WHERE id='banners';
DROP POLICY IF EXISTS banners_admin_write ON storage.objects;
CREATE POLICY banners_admin_write ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='banners' AND public.is_admin() AND public.has_admin_permission('manage_settings')
  AND name ~ '^([A-Za-z0-9_-]+/)*[A-Za-z0-9_@.-]+\.(webp|png|jpg|jpeg)$' AND name !~ '\.\.');
DROP POLICY IF EXISTS banners_admin_update ON storage.objects;
CREATE POLICY banners_admin_update ON storage.objects FOR UPDATE TO authenticated
 USING(bucket_id='banners' AND public.is_admin() AND public.has_admin_permission('manage_settings'))
 WITH CHECK(bucket_id='banners' AND public.is_admin() AND public.has_admin_permission('manage_settings')
  AND name ~ '^([A-Za-z0-9_-]+/)*[A-Za-z0-9_@.-]+\.(webp|png|jpg|jpeg)$' AND name !~ '\.\.');
DROP POLICY IF EXISTS banners_admin_delete ON storage.objects;
CREATE POLICY banners_admin_delete ON storage.objects FOR DELETE TO authenticated
 USING(bucket_id='banners' AND public.is_admin() AND public.has_admin_permission('manage_settings'));
