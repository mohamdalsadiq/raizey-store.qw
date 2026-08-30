begin;

-- These RPCs belonged to the reverted subcategory catalog and reference the
-- removed products.subcategory_id column. No active page calls them.
drop function if exists public.get_catalog_tree();
drop function if exists public.get_popular_products(integer);

commit;
