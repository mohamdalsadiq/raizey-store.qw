begin;

-- Private state used only by trusted server code.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.chat_rate_limits (
  rate_key text primary key,
  window_started_at timestamptz not null default clock_timestamp(),
  request_count integer not null default 1 check (request_count > 0),
  updated_at timestamptz not null default clock_timestamp()
);

revoke all on private.chat_rate_limits from public, anon, authenticated;

create or replace function public.consume_chat_rate_limit(
  p_rate_key text,
  p_limit integer default 12,
  p_window_seconds integer default 600
)
returns table(allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_limit integer := least(greatest(coalesce(p_limit, 12), 1), 100);
  v_window_seconds integer := least(greatest(coalesce(p_window_seconds, 600), 60), 86400);
  v_window interval;
  v_count integer;
  v_started_at timestamptz;
begin
  if p_rate_key is null or length(p_rate_key) < 16 or length(p_rate_key) > 128 then
    raise exception 'invalid_rate_key';
  end if;

  v_window := make_interval(secs => v_window_seconds);

  insert into private.chat_rate_limits as limits (
    rate_key,
    window_started_at,
    request_count,
    updated_at
  )
  values (p_rate_key, v_now, 1, v_now)
  on conflict (rate_key) do update
  set
    window_started_at = case
      when limits.window_started_at <= v_now - v_window then v_now
      else limits.window_started_at
    end,
    request_count = case
      when limits.window_started_at <= v_now - v_window then 1
      else limits.request_count + 1
    end,
    updated_at = v_now
  returning request_count, window_started_at
  into v_count, v_started_at;

  allowed := v_count <= v_limit;
  retry_after_seconds := case
    when allowed then 0
    else greatest(
      1,
      ceil(extract(epoch from ((v_started_at + v_window) - v_now)))::integer
    )
  end;
  return next;
end;
$function$;

revoke all on function public.consume_chat_rate_limit(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_chat_rate_limit(text, integer, integer)
  to service_role;

-- The trigger/helper functions use qualified objects and do not need a mutable path.
alter function public.normalize_tx_ref(text) set search_path = '';
alter function public.generate_order_code() set search_path = '';
alter function public.set_order_code() set search_path = '';
alter function public.touch_subcategories_updated_at() set search_path = '';

-- Trigger and privileged administration functions must never be anonymous RPCs.
revoke execute on function public.apply_referral_signup_metadata() from public, anon;
revoke execute on function public.admin_reject_order(uuid, text) from public, anon;
revoke execute on function public.admin_set_customer_banned(uuid, boolean) from public, anon;
revoke execute on function public.admin_set_staff_permissions(uuid, text, jsonb) from public, anon;
revoke execute on function public.admin_update_order_status(uuid, text) from public, anon;

-- Catalog reads can respect RLS and no longer need SECURITY DEFINER.
alter function public.get_catalog_tree() security invoker;

-- Remove duplicate policies and scope all administration policies to signed-in users.
drop policy if exists categories_admin_all on public.categories;
alter policy coupons_admin on public.coupons to authenticated;
alter policy coupons_select_admin_only on public.coupons to authenticated;
alter policy gift_cards_admin on public.gift_cards to authenticated;
alter policy payment_codes_admin_manage on public.payment_codes to authenticated;
alter policy payment_methods_admin on public.payment_methods to authenticated;
alter policy referral_milestones_admin on public.referral_milestones to authenticated;
alter policy settings_admin on public.settings to authenticated;
alter policy store_sections_admin_delete on public.store_sections to authenticated;
alter policy store_sections_admin_insert on public.store_sections to authenticated;
alter policy store_sections_admin_update on public.store_sections to authenticated;
alter policy subcategories_admin_manage on public.subcategories to authenticated;
alter policy wallet_tx_select_own on public.wallet_transactions to authenticated;
drop policy if exists "users read own payment codes" on public.payment_codes;

-- Public catalog policies do not call privileged identity helpers for anonymous users.
drop policy if exists categories_select_active on public.categories;
create policy categories_select_active_anon
  on public.categories for select to anon
  using (is_active = true);
create policy categories_select_active_authenticated
  on public.categories for select to authenticated
  using (is_active = true or public.is_admin());

drop policy if exists products_select_active on public.products;
create policy products_select_active_anon
  on public.products for select to anon
  using (is_active = true);
create policy products_select_active_authenticated
  on public.products for select to authenticated
  using (is_active = true or public.is_admin());

drop policy if exists payment_methods_select on public.payment_methods;
create policy payment_methods_select_active_anon
  on public.payment_methods for select to anon
  using (is_active = true);
create policy payment_methods_select_authenticated
  on public.payment_methods for select to authenticated
  using (is_active = true or (
    public.is_admin() and public.has_admin_permission('manage_settings')
  ));

drop policy if exists store_sections_public_read on public.store_sections;
create policy store_sections_select_active_anon
  on public.store_sections for select to anon
  using (is_active = true);
create policy store_sections_select_authenticated
  on public.store_sections for select to authenticated
  using (is_active = true or (
    public.is_admin() and public.has_admin_permission('manage_products')
  ));

drop policy if exists subcategories_public_select on public.subcategories;
create policy subcategories_select_active_anon
  on public.subcategories for select to anon
  using (is_active = true);
create policy subcategories_select_authenticated
  on public.subcategories for select to authenticated
  using (is_active = true or public.is_admin());

revoke execute on function public.has_admin_permission(text) from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.is_banned() from public, anon;
revoke execute on function public.is_super_admin() from public, anon;

-- Cache auth.uid() once per statement instead of once per row.
alter policy admin_perms_super_admin on public.admin_permissions
  using (public.is_super_admin() and profile_id <> (select auth.uid()))
  with check (public.is_super_admin() and profile_id <> (select auth.uid()));
alter policy admin_perms_select on public.admin_permissions
  using (profile_id = (select auth.uid()) or public.is_super_admin());
alter policy admin_audit_insert on public.admin_audit_logs
  with check (public.is_admin() and admin_id = (select auth.uid()));
alter policy audit_logs_insert_customer on public.audit_logs
  with check ((select auth.uid()) is not null and admin_id is null);
alter policy coupon_redemptions_select_own on public.coupon_redemptions
  using (user_id = (select auth.uid()) or public.is_admin());
alter policy gift_cards_select_own on public.gift_cards
  using (redeemed_by = (select auth.uid()) or public.is_admin());
alter policy notifications_select_own on public.notifications
  using (user_id = (select auth.uid()) or public.is_admin());
alter policy notifications_update_own on public.notifications
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
alter policy orders_select on public.orders
  using (user_id = (select auth.uid()) or public.is_admin());
alter policy orders_insert_own on public.orders
  with check (
    user_id = (select auth.uid())
    and not public.is_banned()
    and status = any (array['pending_review'::text, 'in_progress'::text])
    and coalesce(referral_commission_paid, false) = false
  );
alter policy orders_cancel_own on public.orders
  using (user_id = (select auth.uid()) and status = 'pending_review')
  with check (user_id = (select auth.uid()) and status = 'cancelled');
alter policy payment_codes_select_own on public.payment_codes
  using (user_id = (select auth.uid()) or used_by = (select auth.uid()));
alter policy receipts_select_own on public.payment_receipts
  using (user_id = (select auth.uid()) or public.is_admin());
alter policy profiles_insert_own on public.profiles
  with check (id = (select auth.uid()));
alter policy profiles_select_own on public.profiles
  using (id = (select auth.uid()) or public.is_admin());
alter policy profiles_update_own on public.profiles
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
alter policy referral_payouts_select on public.referral_milestone_payouts
  using (referrer_id = (select auth.uid()) or public.is_admin());
alter policy topups_insert_own on public.wallet_topups
  with check (
    user_id = (select auth.uid())
    and not public.is_banned()
    and status = 'pending'
    and amount > 0
    and amount <= 10000000
    and reviewed_at is null
    and coalesce(amount_verified, false) = false
  );
alter policy topups_select_own on public.wallet_topups
  using (user_id = (select auth.uid()) or public.is_admin());
alter policy wallet_tx_select_own on public.wallet_transactions
  using (user_id = (select auth.uid()) or public.is_admin());
alter policy wallets_select_own on public.wallets
  using (user_id = (select auth.uid()) or public.is_admin());

-- Cover foreign keys used by joins and cascading integrity checks.
create index if not exists idx_admin_permissions_created_by
  on public.admin_permissions (created_by);
create index if not exists idx_admin_permissions_updated_by
  on public.admin_permissions (updated_by);
create index if not exists idx_audit_logs_admin_id
  on public.audit_logs (admin_id);
create index if not exists idx_coupon_redemptions_user_id
  on public.coupon_redemptions (user_id);
create index if not exists idx_gift_cards_redeemed_by
  on public.gift_cards (redeemed_by);
create index if not exists idx_orders_payment_method_id
  on public.orders (payment_method_id);
create index if not exists idx_payment_codes_created_by
  on public.payment_codes (created_by);
create index if not exists idx_payment_codes_order_id
  on public.payment_codes (order_id);
create index if not exists idx_payment_codes_used_by
  on public.payment_codes (used_by);
create index if not exists idx_profiles_referred_by
  on public.profiles (referred_by);
create index if not exists idx_referral_payouts_milestone_id
  on public.referral_milestone_payouts (milestone_id);
create index if not exists idx_store_settings_updated_by
  on public.store_settings (updated_by);
create index if not exists idx_wallet_topups_payment_method_id
  on public.wallet_topups (payment_method_id);

drop index if exists public.payment_codes_user_idx;
drop index if exists public.idx_wallet_topups_receipt_id;

-- Enforce the same upload contract on the server that the UI documents.
update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']::text[]
where id in ('avatars', 'product-images', 'receipts');

commit;
