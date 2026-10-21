-- Catalog asset writes require the same permission as catalog management RPCs.
-- No data changes; public reads and owner avatar/receipt policies are unchanged.
BEGIN;

ALTER POLICY product_images_admin_write ON storage.objects TO authenticated WITH CHECK ((bucket_id = 'product-images' AND public.is_admin() AND public.has_admin_permission('manage_products')));

ALTER POLICY product_images_admin_update ON storage.objects TO authenticated USING ((bucket_id = 'product-images' AND public.is_admin() AND public.has_admin_permission('manage_products'))) WITH CHECK ((bucket_id = 'product-images' AND public.is_admin() AND public.has_admin_permission('manage_products')));

ALTER POLICY product_images_admin_delete ON storage.objects TO authenticated USING ((bucket_id = 'product-images' AND public.is_admin() AND public.has_admin_permission('manage_products')));

ALTER POLICY category_icons_admin_write ON storage.objects TO authenticated WITH CHECK ((bucket_id = 'category-icons' AND public.is_admin() AND public.has_admin_permission('manage_products')));

ALTER POLICY category_icons_admin_update ON storage.objects TO authenticated USING ((bucket_id = 'category-icons' AND public.is_admin() AND public.has_admin_permission('manage_products'))) WITH CHECK ((bucket_id = 'category-icons' AND public.is_admin() AND public.has_admin_permission('manage_products')));

ALTER POLICY category_icons_admin_delete ON storage.objects TO authenticated USING ((bucket_id = 'category-icons' AND public.is_admin() AND public.has_admin_permission('manage_products')));

COMMIT;
