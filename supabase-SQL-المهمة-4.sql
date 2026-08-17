-- RAIZEY STORE — Task 4: short referral codes and secure validation
-- يحافظ على referral_code وروابط ?ref= القديمة ويضيف كودًا قصيرًا يدويًا.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_short_code text;

CREATE OR REPLACE FUNCTION public.generate_referral_short_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
VOLATILE
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_attempt integer := 0;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    -- RZY + ثلاث خانات أبجدية رقمية = 6 خانات سهلة العرض.
    v_code := 'RZY' || upper(substr(md5(random()::text || clock_timestamp()::text || v_attempt::text), 1, 3));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE referral_short_code = v_code
    );
    IF v_attempt > 20 THEN
      RAISE EXCEPTION 'referral_code_generation_failed';
    END IF;
  END LOOP;
  RETURN v_code;
END;
$$;

-- تعبئة الحسابات القديمة قبل إضافة الفهرس الفريد.
UPDATE public.profiles
SET referral_short_code = public.generate_referral_short_code()
WHERE referral_short_code IS NULL OR btrim(referral_short_code) = '';

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_referral_short_code_format;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_referral_short_code_format
  CHECK (referral_short_code IS NULL OR referral_short_code ~ '^[A-Z0-9]{5,6}$');

CREATE UNIQUE INDEX IF NOT EXISTS uq_profiles_referral_short_code
  ON public.profiles (referral_short_code)
  WHERE referral_short_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_referral_short_code
  ON public.profiles (referral_short_code);

-- تطبيق referral_code_used من auth.users عند إنشاء profile جديد.
CREATE OR REPLACE FUNCTION public.apply_referral_signup_metadata()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_used text;
  v_norm text;
  v_referrer uuid;
BEGIN
  IF NEW.referral_short_code IS NULL OR btrim(NEW.referral_short_code) = '' THEN
    NEW.referral_short_code := public.generate_referral_short_code();
  END IF;

  SELECT NULLIF(btrim(raw_user_meta_data ->> 'referral_code_used'), '')
    INTO v_used
  FROM auth.users
  WHERE id = NEW.id;

  v_norm := upper(regexp_replace(coalesce(v_used, ''), '[^A-Za-z0-9]', '', 'g'));
  IF v_norm <> '' THEN
    SELECT p.id INTO v_referrer
    FROM public.profiles p
    WHERE upper(coalesce(p.referral_short_code, '')) = v_norm
       OR upper(coalesce(p.referral_code, '')) = v_norm
    LIMIT 1;

    IF v_referrer IS NOT NULL AND v_referrer <> NEW.id THEN
      NEW.referred_by := v_referrer;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_referral_signup_metadata ON public.profiles;
CREATE TRIGGER trg_apply_referral_signup_metadata
BEFORE INSERT ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.apply_referral_signup_metadata();

-- أبقِ الكود القصير محميًا مثل referral_code القديم.
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  NEW.id                     := OLD.id;
  NEW.role                   := OLD.role;
  NEW.is_banned              := OLD.is_banned;
  NEW.referral_code          := OLD.referral_code;
  NEW.referral_short_code    := OLD.referral_short_code;
  NEW.referred_by            := OLD.referred_by;
  NEW.referral_rewarded      := OLD.referral_rewarded;
  NEW.referral_discount_used := OLD.referral_discount_used;
  NEW.milestone10_paid       := OLD.milestone10_paid;
  NEW.milestone25_paid       := OLD.milestone25_paid;
  NEW.loyalty_points         := OLD.loyalty_points;
  NEW.created_at             := OLD.created_at;
  RETURN NEW;
END;
$$;

-- يتحقق من كود قصير أو legacy referral_code دون كشف هوية صاحبه.
CREATE OR REPLACE FUNCTION public.validate_referral_short_code(p_code text)
RETURNS TABLE(valid boolean, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_referrer uuid;
BEGIN
  IF length(v_norm) < 5 OR length(v_norm) > 32 THEN
    RETURN QUERY SELECT false, 'invalid_format';
    RETURN;
  END IF;

  SELECT p.id INTO v_referrer
  FROM public.profiles p
  WHERE upper(coalesce(p.referral_short_code, '')) = v_norm
     OR upper(coalesce(p.referral_code, '')) = v_norm
  LIMIT 1;

  IF v_referrer IS NULL THEN
    RETURN QUERY SELECT false, 'not_found';
    RETURN;
  END IF;

  IF auth.uid() IS NOT NULL AND v_referrer = auth.uid() THEN
    RETURN QUERY SELECT false, 'self_referral';
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'valid';
END;
$$;

REVOKE ALL ON FUNCTION public.generate_referral_short_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_referral_short_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_referral_short_code(text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
