-- Rollback for db/migrations/2026-10-12_banners.sql
-- Run inside a transaction. Removes the banner feature and its seed rows only.
begin;

drop policy if exists banners_admin_delete on storage.objects;
drop policy if exists banners_admin_update on storage.objects;
drop policy if exists banners_admin_write  on storage.objects;
drop policy if exists banners_public_read_objects on storage.objects;

drop function if exists public.get_banners_public();
drop function if exists public.admin_reorder_banner(uuid, text);
drop function if exists public.admin_set_banner_active(uuid, boolean);
drop function if exists public.admin_delete_banner(uuid);
drop function if exists public.admin_save_banner(uuid, jsonb);
drop function if exists public.banners_validate(jsonb);

drop table if exists public.banners;

-- The bucket is only dropped when it is empty; uploaded files survive otherwise.
do $$
begin
  if exists (select 1 from storage.buckets where id = 'banners')
     and not exists (select 1 from storage.objects where bucket_id = 'banners') then
    delete from storage.buckets where id = 'banners';
  end if;
end $$;

commit;
