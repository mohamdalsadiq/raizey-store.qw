-- RAIZEY STORE — المهمة 2
-- حفظ معرّفات اللاعب المفضّلة لكل مستخدم في profiles.
-- لا يحتاج هذا التغيير إلى سياسة RLS جديدة؛ سياسات profiles الحالية تسمح للمستخدم بتحديث ملفه،
-- مع بقاء الحقول الحساسة مثل role و referred_by محمية بالـ triggers والسياسات الموجودة.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS player_ids jsonb;

UPDATE public.profiles
SET player_ids = '{}'::jsonb
WHERE player_ids IS NULL;

ALTER TABLE public.profiles
  ALTER COLUMN player_ids SET DEFAULT '{}'::jsonb,
  ALTER COLUMN player_ids SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.profiles'::regclass
      AND conname = 'profiles_player_ids_object_check'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_player_ids_object_check
      CHECK (jsonb_typeof(player_ids) = 'object');
  END IF;
END
$$;

COMMENT ON COLUMN public.profiles.player_ids IS
  'Preferred player IDs by game, stored as a JSON object such as {"pubg":"123456789"}.';


-- صورة الملف الشخصي: رابط عام لعرض الصورة في واجهة المتجر.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_url text;

COMMENT ON COLUMN public.profiles.avatar_url IS
  'Public URL of the authenticated user profile avatar stored in the avatars bucket.';

-- مساحة الصور الشخصية. إذا كان bucket موجودًا، لا يفشل الملف.
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_owner_insert" ON storage.objects;
CREATE POLICY "avatars_owner_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "avatars_owner_update" ON storage.objects;
CREATE POLICY "avatars_owner_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "avatars_owner_delete" ON storage.objects;
CREATE POLICY "avatars_owner_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
