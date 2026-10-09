-- ============================================================================
-- RAIZEY STORE — dead / broken code removal
-- File: db/migrations/2026-10-08_dead_code_cleanup.sql
-- Applied: 2026-10-08
-- ============================================================================
-- create_bank_transfer_order(p_product_id uuid, p_field_values jsonb, p_payment_method_id uuid,
--                            p_receipt_path text, p_coupon_code text)
--   * superseded by create_bank_orders_bulk (atomic: claim + orders in one tx)
--   * provably broken: calls public.increment_coupon_usage() which does not exist
--     (verified against pg_proc), so it raises on any coupon usage
--   * zero client references in the repository and zero DB dependents (pg_depend)
DROP FUNCTION IF EXISTS public.create_bank_transfer_order(uuid, jsonb, uuid, text, text);

SELECT 'dead_code_cleanup_applied' AS status;
