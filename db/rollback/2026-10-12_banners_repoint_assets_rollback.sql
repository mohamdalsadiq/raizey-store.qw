-- Restore the legacy /assets/img/banner-*.webp paths.
begin;
update public.banners set image_desktop_url = replace(image_desktop_url, '/assets/banners/', '/assets/img/')
where image_desktop_url like '/assets/banners/%';
update public.banners set image_mobile_url = replace(image_mobile_url, '/assets/banners/', '/assets/img/')
where image_mobile_url like '/assets/banners/%';
commit;
