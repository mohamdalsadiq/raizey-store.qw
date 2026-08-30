-- Keep internal and retired SECURITY DEFINER functions off the public API.
-- These functions remain executable by the database owner/service role, so
-- triggers and the active wrapper RPCs continue to work.

revoke execute on function public.apply_referral_signup_metadata() from authenticated;
revoke execute on function public.admin_refund_wallet(uuid, numeric, uuid) from authenticated;
revoke execute on function public.create_wallet_order(uuid, jsonb, jsonb, text, text) from authenticated;

-- One-time bootstrap and legacy RPCs are not called by the current storefront.
revoke execute on function public.bootstrap_super_admin() from authenticated;
revoke execute on function public.get_my_admin_context() from authenticated;
revoke execute on function public.create_bank_transfer_order(uuid, jsonb, uuid, text, text) from authenticated;
revoke execute on function public.create_code_orders_bulk(jsonb, text, text) from authenticated;
revoke execute on function public.redeem_loyalty_points(integer) from authenticated;
revoke execute on function public.set_store_exchange_rate(numeric) from authenticated;
revoke execute on function public.set_store_maintenance(boolean, text) from authenticated;
revoke execute on function public.upsert_admin_permissions(
  uuid, boolean, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, boolean, boolean
) from authenticated;
revoke execute on function public.admin_cancel_payment_code(uuid) from authenticated;
revoke execute on function public.admin_create_payment_code(
  numeric, uuid, text, timestamptz
) from authenticated;
