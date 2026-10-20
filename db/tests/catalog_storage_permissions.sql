-- Synthetic fixtures only; safe to run against the local test database.
BEGIN;
-- Model the Storage API's transaction context. Newer Storage releases reject
-- all direct SQL deletes before evaluating RLS; no real objects exist here.
SET LOCAL storage.allow_delete_query='true';
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('c6200000-0000-4000-8000-000000000001','storage-staff@example.invalid','{}'),
 ('c6200000-0000-4000-8000-000000000002','storage-manager@example.invalid','{}');
SET LOCAL session_replication_role=replica;
UPDATE public.profiles SET role='admin' WHERE id::text LIKE 'c6200000-%';
SET LOCAL session_replication_role=origin;
INSERT INTO public.admin_permissions(profile_id,can_manage_products) VALUES
 ('c6200000-0000-4000-8000-000000000001',false),
 ('c6200000-0000-4000-8000-000000000002',true);
CREATE TEMP TABLE storage_checks(name text,passed boolean);
GRANT INSERT,SELECT ON storage_checks TO authenticated;
CREATE FUNCTION pg_temp.storage_write(command text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE affected integer;
BEGIN
 EXECUTE command; GET DIAGNOSTICS affected=ROW_COUNT; RETURN affected=1;
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END $$;
INSERT INTO storage.objects(bucket_id,name) VALUES
 ('product-images','audit-existing.png'),('category-icons','audit-existing.png');
SELECT set_config('request.jwt.claims','{"sub":"c6200000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
DO $$DECLARE bucket text; BEGIN
 FOREACH bucket IN ARRAY ARRAY['product-images','category-icons'] LOOP
  INSERT INTO storage_checks VALUES(bucket||': staff insert denied',NOT pg_temp.storage_write(format('INSERT INTO storage.objects(bucket_id,name) VALUES(%L,%L)',bucket,'audit-staff.png')));
  INSERT INTO storage_checks VALUES(bucket||': staff update denied',NOT pg_temp.storage_write(format('UPDATE storage.objects SET metadata=''{}'' WHERE bucket_id=%L AND name=''audit-existing.png''',bucket)));
  INSERT INTO storage_checks VALUES(bucket||': staff delete denied',NOT pg_temp.storage_write(format('DELETE FROM storage.objects WHERE bucket_id=%L AND name=''audit-existing.png''',bucket)));
 END LOOP;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"c6200000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',true);
SET LOCAL ROLE authenticated;
DO $$DECLARE bucket text; BEGIN
 FOREACH bucket IN ARRAY ARRAY['product-images','category-icons'] LOOP
  INSERT INTO storage_checks VALUES(bucket||': manager insert allowed',pg_temp.storage_write(format('INSERT INTO storage.objects(bucket_id,name) VALUES(%L,%L)',bucket,'audit-manager.png')));
  INSERT INTO storage_checks VALUES(bucket||': manager update allowed',pg_temp.storage_write(format('UPDATE storage.objects SET metadata=''{}'' WHERE bucket_id=%L AND name=''audit-manager.png''',bucket)));
  INSERT INTO storage_checks VALUES(bucket||': manager delete allowed',pg_temp.storage_write(format('DELETE FROM storage.objects WHERE bucket_id=%L AND name=''audit-manager.png''',bucket)));
 END LOOP;
END $$;
RESET ROLE;
SELECT name,passed FROM storage_checks ORDER BY name;
ROLLBACK;
