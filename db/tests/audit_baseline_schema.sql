-- TEST ONLY: metadata snapshot 2026-10-18, no customer rows or secrets.
-- auth/storage shims model only the APIs used by the application tests.
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA storage;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,raw_user_meta_data jsonb,raw_app_meta_data jsonb,created_at timestamptz DEFAULT now(),email_confirmed_at timestamptz);
CREATE TABLE auth.mfa_factors(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES auth.users(id), factor_type text, status text, secret text, friendly_name text, created_at timestamptz, updated_at timestamptz);
CREATE TABLE storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),bucket_id text,name text,owner uuid,metadata jsonb DEFAULT '{}');
CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.sub',true),''),NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role',true),''),auth.jwt()->>'role') $$;
CREATE FUNCTION storage.foldername(name text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1] $$;
GRANT USAGE ON SCHEMA public,auth,storage TO anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated,service_role;
GRANT SELECT ON storage.objects TO anon;
SET check_function_bodies=off;
CREATE TABLE "private"."chat_rate_limits"("rate_key" text NOT NULL,"window_started_at" timestamp with time zone DEFAULT clock_timestamp() NOT NULL,"request_count" integer DEFAULT 1 NOT NULL,"updated_at" timestamp with time zone DEFAULT clock_timestamp() NOT NULL);
CREATE TABLE "public"."admin_audit_logs"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"admin_id" uuid NOT NULL,"action" text NOT NULL,"target_table" text,"target_id" text,"details" jsonb DEFAULT '{}'::jsonb NOT NULL,"created_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL);
CREATE TABLE "public"."admin_permissions"("profile_id" uuid NOT NULL,"is_super_admin" boolean DEFAULT false NOT NULL,"can_manage_orders" boolean DEFAULT false NOT NULL,"can_manage_wallets" boolean DEFAULT false NOT NULL,"can_manage_products" boolean DEFAULT false NOT NULL,"can_manage_settings" boolean DEFAULT false NOT NULL,"can_manage_maintenance" boolean DEFAULT false NOT NULL,"can_manage_admins" boolean DEFAULT false NOT NULL,"can_manage_coupons" boolean DEFAULT false NOT NULL,"can_manage_gift_cards" boolean DEFAULT false NOT NULL,"can_view_audit_logs" boolean DEFAULT false NOT NULL,"created_by" uuid,"updated_by" uuid,"created_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,"updated_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL);
CREATE TABLE "public"."audit_logs"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"admin_id" uuid,"action" text NOT NULL,"details" jsonb DEFAULT '{}'::jsonb NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"source" text DEFAULT 'admin_action'::text NOT NULL);
CREATE TABLE "public"."banners"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"banner_style" text DEFAULT 'image_only'::text NOT NULL,"title" text,"subtitle" text,"cta_text" text,"alt_text" text DEFAULT ''::text NOT NULL,"image_desktop_url" text NOT NULL,"image_mobile_url" text,"link_type" text DEFAULT 'none'::text NOT NULL,"link_target" text,"whatsapp_message" text,"overlay_position_desktop" text DEFAULT 'right'::text NOT NULL,"overlay_position_mobile" text DEFAULT 'top'::text NOT NULL,"hide_if_target_inactive" boolean DEFAULT true NOT NULL,"sort_order" integer DEFAULT 0 NOT NULL,"is_active" boolean DEFAULT true NOT NULL,"starts_at" timestamp with time zone,"ends_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"created_by" uuid,"updated_by" uuid,"status" text DEFAULT 'published'::text NOT NULL);
CREATE TABLE "public"."categories"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"name" text NOT NULL,"display_order" integer DEFAULT 0 NOT NULL,"is_active" boolean DEFAULT true NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"commission_percent" numeric(5,2) DEFAULT 3 NOT NULL,"image_url" text,"description" text,"section_id" uuid,"icon_mode" text DEFAULT 'auto'::text NOT NULL,"icon_key" text,"icon_image_url" text);
CREATE TABLE "public"."coupon_redemptions"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"coupon_id" uuid NOT NULL,"user_id" uuid NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."coupons"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"code" text NOT NULL,"discount_percent" numeric(5,2) NOT NULL,"max_uses" integer,"uses_count" integer DEFAULT 0 NOT NULL,"expires_at" timestamp with time zone,"is_active" boolean DEFAULT true NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"min_order_sdg" numeric DEFAULT 0);
CREATE TABLE "public"."gift_cards"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"code" text NOT NULL,"amount" numeric(12,2) NOT NULL,"is_redeemed" boolean DEFAULT false NOT NULL,"redeemed_by" uuid,"redeemed_at" timestamp with time zone,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"expires_at" timestamp with time zone);
CREATE TABLE "public"."notifications"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"user_id" uuid,"title" text NOT NULL,"message" text NOT NULL,"type" text DEFAULT 'general'::text NOT NULL,"is_read" boolean DEFAULT false NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."orders"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"user_id" uuid NOT NULL,"product_id" uuid,"product_name_snapshot" text NOT NULL,"price_sdg_snapshot" numeric(12,2) NOT NULL,"field_values" jsonb DEFAULT '{}'::jsonb NOT NULL,"payment_type" text NOT NULL,"payment_method_id" uuid,"receipt_url" text,"status" text DEFAULT 'pending_review'::text NOT NULL,"rejection_reason" text,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"transaction_reference" text,"receipt_hash" text,"ocr_status" text DEFAULT 'needs_review'::text,"amount_verified" boolean DEFAULT false,"selected_option" jsonb,"coupon_id" uuid,"field_labels" jsonb DEFAULT '{}'::jsonb,"referral_commission_paid" boolean DEFAULT false,"refunded" boolean DEFAULT false,"receipt_id" uuid,"order_code" text,"review_reason" text,"review_severity" text,"payment_code_id" uuid);
CREATE TABLE "public"."payment_codes"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"code" text NOT NULL,"amount" numeric NOT NULL,"user_id" uuid,"note" text,"status" text DEFAULT 'active'::text NOT NULL,"expires_at" timestamp with time zone,"used_by" uuid,"used_at" timestamp with time zone,"order_id" uuid,"created_by" uuid,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."payment_methods"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"name" text NOT NULL,"account_info" text NOT NULL,"instructions" text,"is_active" boolean DEFAULT true NOT NULL,"display_order" integer DEFAULT 0 NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"account_name" text,"account_number" text,"bin_prefixes" text DEFAULT ''::text,"bank_key" text DEFAULT ''::text,"icon_url" text);
CREATE TABLE "public"."payment_receipts"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"user_id" uuid NOT NULL,"purpose" text NOT NULL,"provider" text,"payment_method_id" uuid,"tx_ref_raw" text NOT NULL,"tx_ref_norm" text NOT NULL,"tx_ref_ocr" text,"receipt_hash" text NOT NULL,"receipt_path" text,"amount_expected" numeric,"amount_detected" numeric,"amount_verified" boolean DEFAULT false NOT NULL,"ref_verified" boolean DEFAULT false NOT NULL,"ocr_status" text DEFAULT 'needs_review'::text NOT NULL,"ocr_confidence" numeric,"risk_flags" text[] DEFAULT '{}'::text[] NOT NULL,"ocr_data" jsonb DEFAULT '{}'::jsonb NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"parent_receipt_id" uuid);
CREATE TABLE "public"."products"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"category_id" uuid,"name" text NOT NULL,"description" text,"image_url" text,"price_usd" numeric(12,2) NOT NULL,"required_fields" jsonb DEFAULT '[]'::jsonb NOT NULL,"is_active" boolean DEFAULT true NOT NULL,"display_order" integer DEFAULT 0 NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"instructions" text,"compare_at_price_usd" numeric(12,2),"flash_sale_ends_at" timestamp with time zone,"options" jsonb DEFAULT '[]'::jsonb,"has_options" boolean DEFAULT false NOT NULL,"delivery_badge_text" text,"is_on_offer" boolean DEFAULT false NOT NULL);
CREATE TABLE "public"."profiles"("id" uuid NOT NULL,"full_name" text,"whatsapp_number" text,"role" text DEFAULT 'customer'::text NOT NULL,"is_banned" boolean DEFAULT false NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"referral_code" text,"referred_by" uuid,"referral_rewarded" boolean DEFAULT false NOT NULL,"milestone10_paid" boolean DEFAULT false NOT NULL,"milestone25_paid" boolean DEFAULT false NOT NULL,"referral_discount_used" boolean DEFAULT false NOT NULL,"loyalty_points" integer DEFAULT 0 NOT NULL,"player_ids" jsonb DEFAULT '{}'::jsonb NOT NULL,"avatar_url" text,"referral_short_code" text);
CREATE TABLE "public"."receipt_fraud_attempts"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"user_id" uuid,"entered_reference" text,"normalized_reference" text,"reason" text NOT NULL,"provider" text,"ocr_excerpt" text,"order_amount" numeric,"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL);
CREATE TABLE "public"."receipt_scan_results"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"user_id" uuid NOT NULL,"receipt_hash" text NOT NULL,"image_bytes" integer NOT NULL,"mime_type" text NOT NULL,"expected_amount" numeric,"manual_ref" text,"expected_account" text,"decision" text DEFAULT 'review'::text NOT NULL,"ocr_status" text DEFAULT 'needs_review'::text NOT NULL,"amount_detected" numeric,"tx_ref_ocr" text,"provider" text,"provider_name" text,"ocr_confidence" numeric,"risk_flags" text[] DEFAULT '{}'::text[] NOT NULL,"ocr_data" jsonb DEFAULT '{}'::jsonb NOT NULL,"submission_allowed" boolean DEFAULT false NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"expires_at" timestamp with time zone NOT NULL,"claimed_at" timestamp with time zone,"claimed_receipt_id" uuid,"consumed_at" timestamp with time zone,"consumed_by_table" text,"consumed_record_id" uuid);
CREATE TABLE "public"."referral_milestone_payouts"("referrer_id" uuid NOT NULL,"milestone_id" uuid NOT NULL,"paid_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."referral_milestones"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"threshold" integer NOT NULL,"bonus" numeric(12,2) NOT NULL,"label" text,"is_active" boolean DEFAULT true NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."settings"("key" text NOT NULL,"value" text NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."store_sections"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"name" text NOT NULL,"display_order" integer DEFAULT 0 NOT NULL,"is_active" boolean DEFAULT true NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL,"description" text,"icon_mode" text DEFAULT 'auto'::text NOT NULL,"icon_key" text,"icon_image_url" text);
CREATE TABLE "public"."store_settings"("id" bigint NOT NULL,"singleton_key" boolean DEFAULT true NOT NULL,"maintenance_mode" boolean DEFAULT false NOT NULL,"maintenance_message" text DEFAULT 'الموقع قيد الصيانة والتحديث حالياً، وسنسعد بخدمتكم مجدداً في أقرب وقت ممكن.'::text NOT NULL,"usd_to_sdg_rate" numeric(12,2) DEFAULT 0 NOT NULL,"updated_by" uuid,"created_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,"updated_at" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL);
CREATE TABLE "public"."subcategories"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"category_id" uuid NOT NULL,"name" text NOT NULL,"description" text,"image_url" text,"display_order" integer DEFAULT 0 NOT NULL,"is_active" boolean DEFAULT true NOT NULL,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."wallet_topups"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"user_id" uuid NOT NULL,"amount" numeric(12,2) NOT NULL,"payment_method_id" uuid,"receipt_url" text,"status" text DEFAULT 'pending'::text NOT NULL,"rejection_reason" text,"created_at" timestamp with time zone DEFAULT now() NOT NULL,"reviewed_at" timestamp with time zone,"transaction_reference" text,"receipt_hash" text,"ocr_status" text DEFAULT 'needs_review'::text,"amount_verified" boolean DEFAULT false,"receipt_id" uuid);
CREATE TABLE "public"."wallet_transactions"("id" uuid DEFAULT gen_random_uuid() NOT NULL,"user_id" uuid NOT NULL,"amount" numeric NOT NULL,"direction" text NOT NULL,"balance_after" numeric,"source" text NOT NULL,"reference_id" uuid,"performed_by" uuid,"details" jsonb,"created_at" timestamp with time zone DEFAULT now() NOT NULL);
CREATE TABLE "public"."wallets"("user_id" uuid NOT NULL,"balance" numeric(12,2) DEFAULT 0 NOT NULL,"updated_at" timestamp with time zone DEFAULT now() NOT NULL);
-- admin_cancel_payment_code(p_code_id uuid); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_cancel_payment_code(p_code_id uuid)
 RETURNS payment_codes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_row public.payment_codes;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'access_denied'; END IF;
  UPDATE public.payment_codes SET status = 'cancelled'
  WHERE id = p_code_id AND status = 'active'
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'code_not_active'; END IF;
  PERFORM public.append_admin_audit_log('cancel_payment_code', 'payment_codes', p_code_id::text, '{}'::jsonb);
  RETURN v_row;
END;
$function$;


-- admin_confirm_topup(p_topup_id uuid, p_override_reason text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_confirm_topup(p_topup_id uuid, p_override_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_topup       public.wallet_topups%ROWTYPE;
  v_detected    numeric;
  v_diff        numeric;
  v_tolerance   numeric;
  v_overrode    boolean := false;
  v_new_balance numeric;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_wallets') THEN
    RAISE EXCEPTION 'access_denied: manage_wallets permission required';
  END IF;

  SELECT * INTO v_topup FROM public.wallet_topups WHERE id = p_topup_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'topup_not_found'; END IF;
  IF v_topup.status <> 'pending' THEN RAISE EXCEPTION 'already_processed'; END IF;

  IF v_topup.receipt_id IS NOT NULL THEN
    SELECT pr.amount_detected INTO v_detected
    FROM public.payment_receipts pr
    WHERE pr.id = v_topup.receipt_id;
  END IF;

  -- ── Hall #C2: no receipt / no detected amount ⇒ explicit override only ──
  IF v_topup.receipt_id IS NULL OR v_detected IS NULL THEN
    IF p_override_reason IS NULL OR btrim(p_override_reason) = '' THEN
      RAISE EXCEPTION 'topup_requires_verified_receipt: receipt_id=% amount_detected=%',
        v_topup.receipt_id, v_detected;
    END IF;
    v_overrode := true;
  ELSE
    v_diff      := abs(v_detected - v_topup.amount);
    v_tolerance := GREATEST(v_detected * 0.01, 2);
    IF v_diff > v_tolerance THEN
      IF p_override_reason IS NULL OR btrim(p_override_reason) = '' THEN
        RAISE EXCEPTION 'topup_amount_mismatch: receipt detected % but topup requests %',
          v_detected, v_topup.amount;
      END IF;
      v_overrode := true;
    END IF;
  END IF;

  UPDATE public.wallet_topups
  SET status = 'confirmed', reviewed_at = now()
  WHERE id = p_topup_id;

  INSERT INTO public.wallets (user_id, balance)
  VALUES (v_topup.user_id, v_topup.amount)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = public.wallets.balance + EXCLUDED.balance, updated_at = now()
  RETURNING public.wallets.balance INTO v_new_balance;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_topup.user_id, v_topup.amount, 'credit', v_new_balance, 'topup', p_topup_id, auth.uid());

  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (v_topup.user_id, 'تم تأكيد شحن المحفظة', 'تمت إضافة مبلغ الشحن إلى محفظتك بنجاح.', 'wallet');

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (auth.uid(), 'تأكيد شحن محفظة',
    jsonb_build_object(
      'topup_id', p_topup_id,
      'user_id', v_topup.user_id,
      'amount', v_topup.amount,
      'amount_detected', v_detected,
      'amount_overridden', v_overrode,
      'override_reason', p_override_reason
    ),
    'admin_action');
END
$function$;


-- admin_copy_banner(p_id uuid); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_copy_banner(p_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_new uuid;
  v_max integer;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;

  select coalesce(max(sort_order),0) + 1 into v_max from public.banners;

  insert into public.banners (
    banner_style, status, title, subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
    link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
    hide_if_target_inactive, sort_order, is_active, starts_at, ends_at, created_by, updated_by)
  select banner_style, 'draft',
         coalesce(title,'') || ' (نسخة)',
         subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
         link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
         hide_if_target_inactive, v_max, false, starts_at, ends_at, v_uid, v_uid
  from public.banners where id = p_id
  returning id into v_new;

  if v_new is null then raise exception 'BANNER_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('banner_copy','banners',v_new::text,
    jsonb_build_object('copied_from', p_id));
  return v_new;
end;
$function$;


-- admin_create_payment_code(p_amount numeric, p_user_id uuid, p_note text, p_expires_at timestamp with time zone); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_create_payment_code(p_amount numeric, p_user_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS payment_codes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_code text;
  v_row  public.payment_codes;
  v_try  int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  LOOP
    v_try := v_try + 1;
    v_code := 'RZY-' ||
      upper(substr(replace(encode(gen_random_bytes(4), 'hex'), '0', 'G'), 1, 4)) || '-' ||
      upper(substr(replace(encode(gen_random_bytes(4), 'hex'), '1', 'H'), 1, 4));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.payment_codes WHERE code = v_code);
    IF v_try > 10 THEN RAISE EXCEPTION 'code_generation_failed'; END IF;
  END LOOP;

  INSERT INTO public.payment_codes (code, amount, user_id, note, expires_at, created_by)
  VALUES (v_code, ROUND(p_amount), p_user_id, NULLIF(trim(p_note), ''), p_expires_at, auth.uid())
  RETURNING * INTO v_row;

  PERFORM public.append_admin_audit_log('create_payment_code', 'payment_codes', v_row.id::text,
    jsonb_build_object('code', v_row.code, 'amount', v_row.amount, 'user_id', p_user_id));

  RETURN v_row;
END;
$function$;


-- admin_delete_banner(p_id uuid); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_delete_banner(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  delete from public.banners where id = p_id;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
  perform public.append_admin_audit_log('banner_delete','banners',p_id::text,jsonb_build_object('id',p_id));
end;
$function$;


-- admin_refund_wallet(p_order_id uuid, p_reason text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_refund_wallet(p_order_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order   public.orders%ROWTYPE;
  v_new_balance numeric;
  v_admin   uuid := auth.uid();
  v_debited boolean := false;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'invalid_refund_input: order required';
  END IF;

  -- Lock the order; amount + user are server-derived from this row only.
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.refunded THEN
    RAISE EXCEPTION 'already_refunded';
  END IF;

  -- [FIX 2026-10-11] كان هنا: IF v_order.status <> 'completed' THEN RAISE …
  -- الشرط كان يجعل مساري الإلغاء والرفض مستحيلين (الحالة تكون قد تغيّرت بالفعل).
  -- البديل: إثبات مالي من دفتر المحفظة بدل شرط الحالة.
  IF v_order.price_sdg_snapshot IS NULL OR v_order.price_sdg_snapshot <= 0 THEN
    RAISE EXCEPTION 'invalid_refund_amount';
  END IF;

  v_debited := EXISTS (
    SELECT 1
    FROM public.wallet_transactions t
    WHERE t.user_id = v_order.user_id
      AND t.direction = 'debit'
      AND (t.reference_id = p_order_id OR t.details->'order_ids' ? p_order_id::text)
  );

  -- طلب محفظة بلا أي خصم موثّق = لا استرداد (منع تكوين رصيد من الهواء)
  IF v_order.payment_type = 'wallet' AND NOT v_debited THEN
    RAISE EXCEPTION 'refund_without_debit: no wallet debit recorded for order %', p_order_id;
  END IF;

  UPDATE public.wallets
  SET balance = balance + v_order.price_sdg_snapshot, updated_at = now()
  WHERE user_id = v_order.user_id
  RETURNING balance INTO v_new_balance;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'wallet_not_found for user %', v_order.user_id;
  END IF;

  UPDATE public.orders SET refunded = true WHERE id = p_order_id;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_order.user_id, v_order.price_sdg_snapshot, 'credit', v_new_balance, 'admin_refund', p_order_id, v_admin);

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (v_admin, 'admin_refund_wallet',
          jsonb_build_object('order_id', p_order_id,
                             'amount', v_order.price_sdg_snapshot,
                             'order_user_id', v_order.user_id,
                             'order_status_at_refund', v_order.status,
                             'wallet_debit_evidence', v_debited,
                             'reason', NULLIF(trim(coalesce(p_reason, '')), '')),
          'admin_action');
END
$function$;


-- admin_reject_order(p_order_id uuid, p_reason text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_reject_order(p_order_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order public.orders%ROWTYPE;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  v_reason := left(v_reason, 500);

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.status NOT IN ('pending_review', 'in_progress') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  UPDATE public.orders
  SET status = 'rejected', rejection_reason = v_reason, updated_at = now()
  WHERE id = p_order_id;

  IF v_order.payment_type = 'wallet' THEN
    PERFORM public.admin_refund_wallet(p_order_id, 'order_rejected: ' || v_reason);
  END IF;

  INSERT INTO public.notifications (user_id, title, message, type)
  VALUES (
    v_order.user_id,
    'تم رفض طلبك',
    'طلبك (' || left(COALESCE(v_order.product_name_snapshot, 'المنتج'), 160) || ') رُفض. السبب: ' || v_reason,
    'order'
  );

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (
    auth.uid(),
    'رفض طلب',
    jsonb_build_object('order_id', p_order_id, 'user_id', v_order.user_id, 'reason', v_reason, 'refunded', v_order.payment_type = 'wallet')
  );
END;
$function$;


-- admin_reject_topup(p_topup_id uuid, p_reason text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_reject_topup(p_topup_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_topup RECORD;
  v_admin uuid := auth.uid();
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  if not public.is_admin() then raise exception 'access_denied: admin only'; end if;
  if not public.has_admin_permission('manage_wallets') then
    raise exception 'access_denied: manage_wallets permission required';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then v_reason := left(v_reason, 500); end if;

  select * into v_topup from wallet_topups where id = p_topup_id for update;
  if not found then raise exception 'topup_not_found'; end if;
  if v_topup.status <> 'pending' then raise exception 'already_processed'; end if;

  update wallet_topups
  set status='rejected', rejection_reason=v_reason, reviewed_at=now()
  where id=p_topup_id;

  insert into audit_logs (admin_id, action, details)
  values (v_admin, 'رفض شحن محفظة',
          jsonb_build_object('topup_id', p_topup_id, 'user_id', v_topup.user_id, 'amount', v_topup.amount, 'reason', v_reason));

  insert into notifications (user_id, title, message, type)
  values (v_topup.user_id, 'تم رفض طلب الشحن',
          'طلب شحن ' || trim(to_char(round(v_topup.amount), 'FM999999999999')) || ' ج.س رُفض. السبب: ' || v_reason, 'wallet');
end;
$function$;


-- admin_release_receipt(p_receipt_id uuid, p_reason text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_release_receipt(p_receipt_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_r      public.payment_receipts%ROWTYPE;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION 'reason_required'; END IF;

  SELECT * INTO v_r FROM public.payment_receipts WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'receipt_not_found'; END IF;

  IF EXISTS (SELECT 1 FROM public.orders        o WHERE o.receipt_id = p_receipt_id)
     OR EXISTS (SELECT 1 FROM public.wallet_topups t WHERE t.receipt_id = p_receipt_id) THEN
    RAISE EXCEPTION 'receipt_in_use: linked to an order or topup';
  END IF;
  IF v_r.ocr_status <> 'needs_review' THEN
    RAISE EXCEPTION 'receipt_not_releasable: only unverified (needs_review) claims can be released';
  END IF;

  DELETE FROM public.payment_receipts WHERE id = p_receipt_id;

  PERFORM public.append_admin_audit_log(
    'release_receipt', 'payment_receipts', p_receipt_id::text,
    jsonb_build_object('reason', v_reason,
                       'tx_ref_norm', v_r.tx_ref_norm,
                       'receipt_path', v_r.receipt_path,
                       'user_id', v_r.user_id));
END
$function$;


-- admin_reorder_banner(p_id uuid, p_direction text); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_reorder_banner(p_id uuid, p_direction text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_cur integer;
  v_other uuid;
  v_other_order integer;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  if p_direction not in ('up','down') then raise exception 'INVALID_DIRECTION'; end if;

  select sort_order into v_cur from public.banners where id = p_id;
  if v_cur is null then raise exception 'BANNER_NOT_FOUND'; end if;

  if p_direction = 'up' then
    select id, sort_order into v_other, v_other_order from public.banners
      where (sort_order, id) < (v_cur, p_id) order by sort_order desc, id desc limit 1;
  else
    select id, sort_order into v_other, v_other_order from public.banners
      where (sort_order, id) > (v_cur, p_id) order by sort_order asc, id asc limit 1;
  end if;
  if v_other is null then return; end if;

  update public.banners set sort_order = v_other_order, updated_by = v_uid where id = p_id;
  update public.banners set sort_order = v_cur, updated_by = v_uid where id = v_other;
  perform public.append_admin_audit_log('banner_reorder','banners',p_id::text,
    jsonb_build_object('direction',p_direction,'swapped_with',v_other));
end;
$function$;


-- admin_reorder_banners(p_order jsonb); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_reorder_banners(p_order jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_count integer;
  v_ids   uuid[];
  v_id    uuid;
  v_pos   integer := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'array' then raise exception 'INVALID_ORDER'; end if;

  select array_agg(value::uuid) into v_ids from jsonb_array_elements_text(p_order);
  v_count := coalesce(array_length(v_ids, 1), 0);
  if v_count = 0 then raise exception 'EMPTY_ORDER'; end if;

  -- every id must exist and there must be no duplicates / omissions
  if exists (select 1 from unnest(v_ids) u(id) group by id having count(*) > 1) then
    raise exception 'DUPLICATE_ID';
  end if;
  if v_count <> (select count(*) from public.banners where id = any(v_ids)) then
    raise exception 'UNKNOWN_ID';
  end if;
  if v_count <> (select count(*) from public.banners) then
    raise exception 'INCOMPLETE_ORDER';
  end if;

  foreach v_id in array v_ids loop
    v_pos := v_pos + 1;
    update public.banners set sort_order = v_pos, updated_by = v_uid where id = v_id;
  end loop;

  perform public.append_admin_audit_log('banner_reorder_all','banners',null,
    jsonb_build_object('order', p_order));
end;
$function$;


-- admin_save_banner(p_id uuid, p_payload jsonb); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_save_banner(p_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v     jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;

  v := public.banners_validate(coalesce(p_payload,'{}'::jsonb));

  if p_id is null then
    insert into public.banners (
      banner_style, status, title, subtitle, cta_text, alt_text, image_desktop_url, image_mobile_url,
      link_type, link_target, whatsapp_message, overlay_position_desktop, overlay_position_mobile,
      hide_if_target_inactive, sort_order, is_active, starts_at, ends_at, created_by, updated_by)
    values (
      v->>'banner_style', v->>'status', v->>'title', v->>'subtitle', v->>'cta_text', v->>'alt_text',
      v->>'image_desktop_url', v->>'image_mobile_url', v->>'link_type', v->>'link_target',
      v->>'whatsapp_message', v->>'overlay_position_desktop', v->>'overlay_position_mobile',
      (v->>'hide_if_target_inactive')::boolean, (v->>'sort_order')::integer, (v->>'is_active')::boolean,
      (v->>'starts_at')::timestamptz, (v->>'ends_at')::timestamptz, v_uid, v_uid)
    returning id into v_id;
  else
    update public.banners set
      banner_style=v->>'banner_style', status=v->>'status', title=v->>'title', subtitle=v->>'subtitle',
      cta_text=v->>'cta_text', alt_text=v->>'alt_text',
      image_desktop_url=v->>'image_desktop_url', image_mobile_url=v->>'image_mobile_url',
      link_type=v->>'link_type', link_target=v->>'link_target', whatsapp_message=v->>'whatsapp_message',
      overlay_position_desktop=v->>'overlay_position_desktop', overlay_position_mobile=v->>'overlay_position_mobile',
      hide_if_target_inactive=(v->>'hide_if_target_inactive')::boolean,
      sort_order=(v->>'sort_order')::integer, is_active=(v->>'is_active')::boolean,
      starts_at=(v->>'starts_at')::timestamptz, ends_at=(v->>'ends_at')::timestamptz, updated_by=v_uid
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'BANNER_NOT_FOUND'; end if;
  end if;

  perform public.append_admin_audit_log(
    case when p_id is null then 'banner_create' else 'banner_update' end,
    'banners', v_id::text, v);
  return v_id;
end;
$function$;


-- admin_set_banner_active(p_id uuid, p_active boolean); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_banner_active(p_id uuid, p_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  update public.banners set is_active = coalesce(p_active,false), updated_by = v_uid where id = p_id;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;
  perform public.append_admin_audit_log('banner_set_active','banners',p_id::text,
    jsonb_build_object('is_active',coalesce(p_active,false)));
end;
$function$;


-- admin_set_banner_status(p_id uuid, p_status text); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_banner_status(p_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_settings') then raise exception 'PERMISSION_REQUIRED'; end if;
  if p_status not in ('draft','published') then raise exception 'INVALID_STATUS'; end if;

  -- publishing requires alt_text so the storefront never ships an alt-less image
  if p_status = 'published'
     and not exists (select 1 from public.banners b where b.id = p_id and coalesce(btrim(b.alt_text),'') <> '') then
    raise exception 'ALT_REQUIRED';
  end if;

  update public.banners set status = p_status, updated_by = v_uid where id = p_id;
  if not found then raise exception 'BANNER_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('banner_set_status','banners',p_id::text,
    jsonb_build_object('status', p_status));
end;
$function$;


-- admin_set_category_icon(p_id uuid, p_mode text, p_key text, p_image text); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_category_icon(p_id uuid, p_mode text, p_key text, p_image text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_products') then raise exception 'PERMISSION_REQUIRED'; end if;

  perform public.icon_fields_validate(p_mode, p_key, p_image);

  update public.categories set
    icon_mode = coalesce(nullif(btrim(p_mode),''),'auto'),
    icon_key = case when p_mode = 'preset' then nullif(btrim(coalesce(p_key,'')),'') else null end,
    icon_image_url = case when p_mode = 'custom' then nullif(btrim(coalesce(p_image,'')),'') else null end
  where id = p_id;
  if not found then raise exception 'CATEGORY_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('category_set_icon','categories',p_id::text,
    jsonb_build_object('mode',p_mode,'key',p_key,'image',p_image));
end;
$function$;


-- admin_set_customer_banned(p_profile_id uuid, p_banned boolean); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_customer_banned(p_profile_id uuid, p_banned boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_admins') THEN
    RAISE EXCEPTION 'access_denied: manage_admins permission required';
  END IF;
  IF p_profile_id IS NULL OR p_profile_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot_modify_self';
  END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  UPDATE public.profiles SET is_banned = COALESCE(p_banned, false) WHERE id = p_profile_id;
  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (auth.uid(), CASE WHEN p_banned THEN 'حظر عميل' ELSE 'إلغاء حظر عميل' END, jsonb_build_object('target_id', p_profile_id, 'banned', p_banned));
END;
$function$;


-- admin_set_section_icon(p_id uuid, p_mode text, p_key text, p_image text); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_section_icon(p_id uuid, p_mode text, p_key text, p_image text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if not public.has_admin_permission('manage_products') then raise exception 'PERMISSION_REQUIRED'; end if;

  perform public.icon_fields_validate(p_mode, p_key, p_image);

  update public.store_sections set
    icon_mode = coalesce(nullif(btrim(p_mode),''),'auto'),
    icon_key = case when p_mode = 'preset' then nullif(btrim(coalesce(p_key,'')),'') else null end,
    icon_image_url = case when p_mode = 'custom' then nullif(btrim(coalesce(p_image,'')),'') else null end
  where id = p_id;
  if not found then raise exception 'SECTION_NOT_FOUND'; end if;

  perform public.append_admin_audit_log('section_set_icon','store_sections',p_id::text,
    jsonb_build_object('mode',p_mode,'key',p_key,'image',p_image));
end;
$function$;


-- admin_set_staff_permissions(p_profile_id uuid, p_role text, p_permissions jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_set_staff_permissions(p_profile_id uuid, p_role text, p_permissions jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_role text := lower(btrim(COALESCE(p_role, '')));
  v_all boolean := lower(COALESCE(p_permissions->>'all', 'false')) = 'true';
  v_is_super boolean := v_all OR lower(COALESCE(p_permissions->>'is_super_admin', 'false')) = 'true';
  v_target_role text;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'access_denied: super admin required';
  END IF;
  IF p_profile_id IS NULL OR p_profile_id = auth.uid() THEN
    RAISE EXCEPTION 'cannot_modify_self';
  END IF;
  IF v_role NOT IN ('admin', 'customer') THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  SELECT role INTO v_target_role FROM public.profiles WHERE id = p_profile_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;

  IF v_role = 'customer' THEN
    IF v_target_role = 'admin' AND EXISTS (
      SELECT 1 FROM public.admin_permissions WHERE profile_id = p_profile_id AND is_super_admin = true
    ) THEN
      IF (SELECT COUNT(*) FROM public.admin_permissions WHERE is_super_admin = true) <= 1 THEN
        RAISE EXCEPTION 'cannot_remove_last_super_admin';
      END IF;
    END IF;
    UPDATE public.profiles SET role = 'customer' WHERE id = p_profile_id;
    DELETE FROM public.admin_permissions WHERE profile_id = p_profile_id;
  ELSE
    UPDATE public.profiles SET role = 'admin' WHERE id = p_profile_id;
    INSERT INTO public.admin_permissions (
      profile_id, is_super_admin, can_manage_orders, can_manage_wallets, can_manage_products,
      can_manage_settings, can_manage_maintenance, can_manage_admins, can_manage_coupons,
      can_manage_gift_cards, can_view_audit_logs, created_by, updated_by
    ) VALUES (
      p_profile_id, v_is_super, v_all OR lower(COALESCE(p_permissions->>'can_manage_orders', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_wallets', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_products', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_settings', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_maintenance', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_admins', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_coupons', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_manage_gift_cards', 'false')) = 'true',
      v_all OR lower(COALESCE(p_permissions->>'can_view_audit_logs', 'false')) = 'true',
      auth.uid(), auth.uid()
    )
    ON CONFLICT (profile_id) DO UPDATE SET
      is_super_admin = EXCLUDED.is_super_admin,
      can_manage_orders = EXCLUDED.can_manage_orders,
      can_manage_wallets = EXCLUDED.can_manage_wallets,
      can_manage_products = EXCLUDED.can_manage_products,
      can_manage_settings = EXCLUDED.can_manage_settings,
      can_manage_maintenance = EXCLUDED.can_manage_maintenance,
      can_manage_admins = EXCLUDED.can_manage_admins,
      can_manage_coupons = EXCLUDED.can_manage_coupons,
      can_manage_gift_cards = EXCLUDED.can_manage_gift_cards,
      can_view_audit_logs = EXCLUDED.can_view_audit_logs,
      updated_by = auth.uid(), updated_at = now();
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (auth.uid(), 'تحديث صلاحيات مشرف', jsonb_build_object('target_id', p_profile_id, 'role', v_role, 'is_super_admin', v_is_super));
END;
$function$;


-- admin_update_order_status(p_order_id uuid, p_status text, p_override_reason text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.admin_update_order_status(p_order_id uuid, p_status text, p_override_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order    public.orders%ROWTYPE;
  v_status   text := lower(btrim(COALESCE(p_status, '')));
  v_reason   text := NULLIF(btrim(COALESCE(p_override_reason, '')), '');
  v_evidence boolean := false;
  v_overrode boolean := false;
BEGIN
  IF NOT public.is_admin() OR NOT public.has_admin_permission('manage_orders') THEN
    RAISE EXCEPTION 'access_denied: manage_orders permission required';
  END IF;

  IF v_status NOT IN ('in_progress', 'completed', 'cancelled') THEN
    RAISE EXCEPTION 'invalid_order_status';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF v_status = 'in_progress' AND v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  IF v_status = 'completed' AND v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  IF v_status = 'cancelled' AND v_order.status NOT IN ('pending_review', 'in_progress') THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;

  -- ── Payment evidence is mandatory to complete an order ──
  IF v_status = 'completed' THEN
    IF v_order.payment_type = 'bank' THEN
      v_evidence := v_order.receipt_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_receipts pr
        WHERE pr.id = v_order.receipt_id
          AND pr.user_id = v_order.user_id
          AND (pr.amount_verified IS TRUE OR pr.ocr_status = 'needs_admin_check')
      );
    ELSIF v_order.payment_type = 'wallet' THEN
      v_evidence := EXISTS (
        SELECT 1 FROM public.wallet_transactions t
        WHERE t.direction = 'debit'
          AND t.user_id = v_order.user_id
          AND (t.reference_id = v_order.id OR t.details->'order_ids' ? v_order.id::text)
      );
    ELSIF v_order.payment_type = 'code' THEN
      v_evidence := v_order.payment_code_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.payment_codes pc
        WHERE pc.id = v_order.payment_code_id
          AND pc.status = 'used'
          AND pc.used_by = v_order.user_id
      );
    END IF;

    IF NOT v_evidence THEN
      IF v_reason IS NULL THEN
        RAISE EXCEPTION 'unverified_payment_evidence: order % (%) has no verifiable payment evidence', p_order_id, v_order.payment_type;
      END IF;
      v_overrode := true;
    END IF;
  END IF;

  UPDATE public.orders
  SET status = v_status, updated_at = now()
  WHERE id = p_order_id;

  IF v_status = 'cancelled'
     AND v_order.payment_type = 'wallet'
     AND COALESCE(v_order.refunded, false) = false THEN
    PERFORM public.admin_refund_wallet(p_order_id, 'order_cancelled');
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details)
  VALUES (
    auth.uid(),
    'تغيير حالة طلب',
    jsonb_build_object('order_id', p_order_id, 'from', v_order.status, 'to', v_status,
                       'payment_type', v_order.payment_type,
                       'evidence_ok', v_evidence, 'overridden', v_overrode,
                       'override_reason', v_reason)
  );
END
$function$;


-- append_admin_audit_log(p_action text, p_target_table text, p_target_id text, p_details jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.append_admin_audit_log(p_action text, p_target_table text DEFAULT NULL::text, p_target_id text DEFAULT NULL::text, p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    v_log_id uuid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      v_admin_id uuid := auth.uid();
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        IF v_admin_id IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                IF NOT public.is_admin() THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    RAISE EXCEPTION 'ADMIN_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        INSERT INTO public.admin_audit_logs (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            admin_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                action,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    target_table,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        target_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            details
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                VALUES (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    v_admin_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        trim(p_action),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            NULLIF(trim(COALESCE(p_target_table, '')), ''),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                NULLIF(trim(COALESCE(p_target_id, '')), ''),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    COALESCE(p_details, '{}'::jsonb)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        RETURNING id INTO v_log_id;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          RETURN v_log_id;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          END;
$function$;


-- apply_referral_signup_metadata(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.apply_referral_signup_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;


-- assert_wallet_ledger_entry(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.assert_wallet_ledger_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- wallet creation with zero balance needs no ledger entry
  IF TG_OP = 'INSERT' AND NEW.balance = 0 THEN
    RETURN NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.wallet_transactions t
    WHERE t.user_id = NEW.user_id
      AND t.balance_after = NEW.balance
      AND t.created_at >= transaction_timestamp()
  ) THEN
    RAISE EXCEPTION
      'wallet_ledger_entry_required: balance of % changed to % without a matching wallet_transactions row in the same transaction',
      NEW.user_id, NEW.balance;
  END IF;

  RETURN NULL;
END
$function$;


-- attach_secondary_receipt(p_parent_tx_ref text, p_order_id uuid, p_receipt jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.attach_secondary_receipt(p_parent_tx_ref text, p_order_id uuid, p_receipt jsonb)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_claim   RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  -- الطلب يجب أن يكون لهذا المستخدم
  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.id = p_order_id AND o.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'receipt_not_owned';
  END IF;

  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    NULLIF(p_receipt->>'payment_method_id', '')::uuid,
    NULLIF(p_receipt->>'expected_amount', '')::numeric,
    NULLIF(p_receipt->>'amount_detected', '')::numeric,
    NULLIF(p_receipt->>'tx_ref_ocr', ''),
    COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_admin_check'),
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
       || jsonb_build_object(
            'split_parent_tx_ref', p_parent_tx_ref,
            'split_parent_order',  p_order_id,
            'is_secondary',        true)
  ) c;

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  -- الإشعار الثاني لا يُعتبر مقبولاً تلقائياً أبداً
  UPDATE payment_receipts pr
  SET ocr_status = 'needs_admin_check'
  WHERE pr.id = v_claim.id;

  RETURN QUERY SELECT v_claim.id;
END;
$function$;


-- award_loyalty_points(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.award_loyalty_points()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rate numeric;
  v_points integer;
begin
  if NEW.status = 'completed' and OLD.status is distinct from 'completed' then
    select coalesce(value::numeric, 0) into v_rate from public.settings where key = 'loyalty_points_per_sdg';
    v_points := floor(NEW.price_sdg_snapshot * coalesce(v_rate, 0));
    if v_points > 0 then
      update public.profiles set loyalty_points = loyalty_points + v_points where id = NEW.user_id;
    end if;
  end if;
  return NEW;
end;
$function$;


-- banners_validate(p_payload jsonb); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.banners_validate(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_style   text := coalesce(p_payload->>'banner_style','image_only');
  v_status  text := coalesce(p_payload->>'status','published');
  v_image_d text := btrim(coalesce(p_payload->>'image_desktop_url',''));
  v_image_m text := nullif(btrim(coalesce(p_payload->>'image_mobile_url','')),'');
  v_link    text := coalesce(p_payload->>'link_type','none');
  v_target  text := nullif(btrim(coalesce(p_payload->>'link_target','')),'');
  v_title   text := nullif(btrim(coalesce(p_payload->>'title','')),'');
  v_sub     text := nullif(btrim(coalesce(p_payload->>'subtitle','')),'');
  v_cta     text := nullif(btrim(coalesce(p_payload->>'cta_text','')),'');
  v_alt     text := nullif(btrim(coalesce(p_payload->>'alt_text','')),'');
  v_ovd     text := coalesce(p_payload->>'overlay_position_desktop','right');
  v_ovm     text := coalesce(p_payload->>'overlay_position_mobile','top');
begin
  if v_style not in ('image_only','image_text') then raise exception 'INVALID_STYLE'; end if;
  if v_status not in ('draft','published')      then raise exception 'INVALID_STATUS'; end if;
  if v_link not in ('none','page','product','category','offers','whatsapp','url') then
    raise exception 'INVALID_LINK_TYPE';
  end if;
  if v_ovd not in ('right','left') or v_ovm not in ('top','bottom') then
    raise exception 'INVALID_OVERLAY_POSITION';
  end if;

  if not public.banners_validate_image_url(v_image_d) then raise exception 'INVALID_IMAGE_DESKTOP_URL'; end if;
  if v_image_m is not null and not public.banners_validate_image_url(v_image_m) then
    raise exception 'INVALID_IMAGE_MOBILE_URL';
  end if;
  if v_image_d ilike 'javascript:%' or v_image_d ilike 'data:%'
     or coalesce(v_image_m,'') ilike 'javascript:%' or coalesce(v_image_m,'') ilike 'data:%' then
    raise exception 'INVALID_IMAGE_DESKTOP_URL';
  end if;

  if v_title is not null and char_length(v_title) > 45 then raise exception 'TITLE_TOO_LONG'; end if;
  if v_sub   is not null and char_length(v_sub)   > 90 then raise exception 'SUBTITLE_TOO_LONG'; end if;
  if v_cta   is not null and char_length(v_cta)   > 20 then raise exception 'CTA_TOO_LONG'; end if;
  if v_style = 'image_text' and v_title is null then raise exception 'TITLE_REQUIRED'; end if;
  -- alt_text is mandatory before a slide may go live
  if v_status = 'published' and v_alt is null then raise exception 'ALT_REQUIRED'; end if;

  if v_target is not null and (v_target ilike 'javascript:%' or v_target ilike 'data:%') then
    raise exception 'INVALID_LINK_TARGET';
  end if;

  if v_link = 'none' then
    v_target := null;
  elsif v_link = 'offers' then
    v_target := null;
  elsif v_link = 'whatsapp' then
    v_target := null;
  elsif v_link = 'product' then
    if v_target is null or v_target !~ '^[0-9a-fA-F-]{36}$' then raise exception 'INVALID_PRODUCT_ID'; end if;
    if not exists (select 1 from public.products where id = v_target::uuid) then raise exception 'PRODUCT_NOT_FOUND'; end if;
  elsif v_link = 'category' then
    if v_target is null or v_target !~ '^[0-9a-fA-F-]{36}$' then raise exception 'INVALID_CATEGORY_ID'; end if;
    if not exists (select 1 from public.categories where id = v_target::uuid) then raise exception 'CATEGORY_NOT_FOUND'; end if;
  elsif v_link = 'page' then
    if v_target is null
       or v_target !~ '^[a-z0-9-]+\.html(#[A-Za-z0-9_-]+)?$'
       or split_part(v_target,'#',1) not in (
      'index.html','offers.html','wallet.html','cart.html','my-orders.html','product.html',
      'category.html','search.html','referrals.html','notifications.html','account.html',
      'privacy.html') then
      raise exception 'PAGE_NOT_ALLOWED';
    end if;
  elsif v_link = 'url' then
    if v_target is null or v_target !~ '^https://[^[:space:]]+$' then raise exception 'INVALID_URL'; end if;
  end if;

  return jsonb_build_object(
    'banner_style', v_style, 'status', v_status,
    'title', v_title, 'subtitle', v_sub, 'cta_text', v_cta,
    'alt_text', left(coalesce(btrim(p_payload->>'alt_text'),''), 160),
    'image_desktop_url', v_image_d, 'image_mobile_url', v_image_m,
    'link_type', v_link, 'link_target', v_target,
    'whatsapp_message', left(nullif(btrim(coalesce(p_payload->>'whatsapp_message','')),''), 400),
    'overlay_position_desktop', v_ovd, 'overlay_position_mobile', v_ovm,
    'hide_if_target_inactive', coalesce((p_payload->>'hide_if_target_inactive')::boolean, true),
    'sort_order', coalesce((p_payload->>'sort_order')::integer, 0),
    'is_active', coalesce((p_payload->>'is_active')::boolean, true),
    'starts_at', nullif(btrim(coalesce(p_payload->>'starts_at','')),'')::timestamptz,
    'ends_at',   nullif(btrim(coalesce(p_payload->>'ends_at','')),'')::timestamptz
  );
end;
$function$;


-- banners_validate_image_url(p_url text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.banners_validate_image_url(p_url text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_url is null then false
    when p_url ~ '^/assets/banners/[A-Za-z0-9._@-]+$' then true
    when p_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/banners/[A-Za-z0-9._/@%-]+$' then true
    else false
  end;
$function$;


-- bootstrap_super_admin(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.bootstrap_super_admin()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               v_user_id uuid := auth.uid();
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 v_existing_super_admin uuid;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   v_status text := 'bootstrapped';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     IF v_user_id IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             -- يمنع أي مستخدم عادي من الاستحواذ على أول Super Admin
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               IF NOT EXISTS (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   SELECT 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       FROM public.profiles p
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           WHERE p.id = v_user_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 AND p.role = 'admin'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ) THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       RAISE EXCEPTION 'BOOTSTRAP_REQUIRES_LEGACY_ADMIN_ROLE';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           PERFORM pg_advisory_xact_lock(hashtext('raiz3y_store_super_admin_bootstrap'));

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             SELECT ap.profile_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               INTO v_existing_super_admin
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 FROM public.admin_permissions ap
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   WHERE ap.is_super_admin = true
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     LIMIT 1;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       IF v_existing_super_admin IS NOT NULL AND v_existing_super_admin <> v_user_id THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           RAISE EXCEPTION 'SUPER_ADMIN_ALREADY_EXISTS';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               IF v_existing_super_admin = v_user_id THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   v_status := 'already_super_admin';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       INSERT INTO public.admin_permissions (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           profile_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               is_super_admin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_manage_orders,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       can_manage_wallets,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           can_manage_products,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_manage_settings,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_manage_maintenance,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       can_manage_admins,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           can_manage_coupons,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_manage_gift_cards,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_view_audit_logs,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       created_by,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           updated_by
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               VALUES (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   v_user_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               v_user_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   v_user_id
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       ON CONFLICT (profile_id) DO UPDATE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         SET is_super_admin = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_manage_orders = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     can_manage_wallets = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           can_manage_products = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 can_manage_settings = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       can_manage_maintenance = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             can_manage_admins = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_manage_coupons = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         can_manage_gift_cards = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_view_audit_logs = true,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     updated_by = v_user_id;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       PERFORM public.append_admin_audit_log(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           'bootstrap_super_admin',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               'admin_permissions',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   v_user_id::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       jsonb_build_object('profile_id', v_user_id, 'bootstrap', true)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         );

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           RETURN jsonb_build_object(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               'status', v_status,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   'profile_id', v_user_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       'is_super_admin', true
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         );
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         END;
$function$;


-- cancel_my_order(p_order_id uuid); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.cancel_my_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_order   public.orders%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'invalid_order';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.user_id <> v_user_id THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_order.status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_status_transition';
  END IF;
  -- wallet orders are charged up-front and move to in_progress immediately;
  -- refunding one is an admin decision (admin_update_order_status → cancel).
  IF v_order.payment_type = 'wallet' THEN
    RAISE EXCEPTION 'wallet_order_requires_support';
  END IF;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;
END
$function$;


-- check_tx_ref_available(p_tx_ref text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.check_tx_ref_available(p_tx_ref text)
 RETURNS TABLE(available boolean, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_norm    text;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  -- حد معدل موحّد: يمنع استخدام الدالة كأداة تعداد مكثّفة
  SELECT * INTO v_rate
  FROM public.consume_chat_rate_limit('txref:' || v_user_id::text, 30, 3600);
  IF NOT v_rate.allowed THEN
    RETURN QUERY SELECT false, 'rate_limited'::text;
    RETURN;
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RETURN QUERY SELECT false, 'invalid_tx_ref'::text;
    RETURN;
  END IF;

  -- نطاق الفحص: صفوف المستخدم نفسه فقط.
  -- الحماية الحقيقية من إعادة استخدام أرقام الآخرين تبقى قيدًا فريدًا على القاعدة.
  IF EXISTS (
       SELECT 1 FROM public.payment_receipts r
       WHERE r.tx_ref_norm = v_norm AND r.user_id = v_user_id
     )
     OR EXISTS (
       SELECT 1 FROM public.orders o
       WHERE public.normalize_tx_ref(o.transaction_reference) = v_norm
         AND o.user_id = v_user_id
     )
     OR EXISTS (
       SELECT 1 FROM public.wallet_topups t
       WHERE public.normalize_tx_ref(t.transaction_reference) = v_norm
         AND t.user_id = v_user_id
     ) THEN
    RETURN QUERY SELECT false, 'duplicate_transaction_ref'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'available'::text;
END
$function$;


-- claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_payment_method_id uuid, p_amount_expected numeric, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text DEFAULT NULL::text, p_provider text DEFAULT NULL::text, p_payment_method_id uuid DEFAULT NULL::uuid, p_amount_expected numeric DEFAULT NULL::numeric, p_amount_detected numeric DEFAULT NULL::numeric, p_tx_ref_ocr text DEFAULT NULL::text, p_ocr_status text DEFAULT 'needs_review'::text, p_ocr_confidence numeric DEFAULT NULL::numeric, p_risk_flags text[] DEFAULT '{}'::text[], p_ocr_data jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id uuid, ocr_status text, amount_verified boolean, ref_verified boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id   uuid := auth.uid();
  v_norm      text;
  v_hash      text;
  v_amount_v  boolean := false;
  v_ref_v     boolean := false;
  v_status    text;
  v_id        uuid;
  v_scan_id   uuid;
  v_scan      public.receipt_scan_results%ROWTYPE;
  v_status_in text;
  v_rate      RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  -- ── Anti-abuse: bounded claim attempts per user ──
  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('claim:' || v_user_id::text, 30, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'receipt_rate_limited';
  END IF;

  IF p_purpose NOT IN ('order', 'topup') THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  v_hash := lower(trim(coalesce(p_receipt_hash, '')));

  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;
  IF v_hash = '' OR v_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  IF coalesce(p_ocr_status, '') = 'rejected' THEN
    RAISE EXCEPTION 'receipt_rejected';
  END IF;

  v_scan_id   := NULLIF(p_ocr_data->>'edge_scan_id', '')::uuid;
  v_status_in := coalesce(p_ocr_status, 'needs_review');

  IF v_scan_id IS NOT NULL THEN
    SELECT * INTO v_scan
    FROM public.receipt_scan_results rs
    WHERE rs.id = v_scan_id
      AND rs.user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'receipt_scan_not_found';
    END IF;
    IF v_scan.expires_at <= now() THEN
      RAISE EXCEPTION 'receipt_scan_expired';
    END IF;
    IF NOT v_scan.submission_allowed
       OR v_scan.decision = 'reject'
       OR v_scan.ocr_status = 'rejected' THEN
      RAISE EXCEPTION 'receipt_rejected';
    END IF;
    IF lower(trim(coalesce(v_scan.receipt_hash, ''))) <> v_hash THEN
      RAISE EXCEPTION 'receipt_scan_hash_mismatch';
    END IF;
    IF v_scan.claimed_at IS NOT NULL THEN
      RAISE EXCEPTION 'receipt_scan_already_used';
    END IF;

    p_amount_detected := v_scan.amount_detected;
    p_tx_ref_ocr      := v_scan.tx_ref_ocr;
    p_ocr_confidence  := v_scan.ocr_confidence;
    p_provider        := COALESCE(NULLIF(trim(coalesce(p_provider, '')), ''), v_scan.provider);
  ELSE
    -- ⛔ FIX (H1): without a server-side scan the client may NOT choose any
    -- elevated status. Everything lands in quarantine (needs_review) and no
    -- server-derived values are accepted.
    p_amount_detected := NULL;
    p_tx_ref_ocr      := NULL;
    p_ocr_confidence  := NULL;
    p_provider        := NULLIF(trim(coalesce(p_provider, '')), '');
    v_status_in       := 'needs_review';
  END IF;

  -- Historical duplicate protection (legacy rows included)
  IF EXISTS (SELECT 1 FROM orders WHERE public.normalize_tx_ref(transaction_reference) = v_norm)
     OR EXISTS (SELECT 1 FROM wallet_topups WHERE public.normalize_tx_ref(transaction_reference) = v_norm) THEN
    RAISE EXCEPTION 'duplicate_transaction_ref';
  END IF;

  IF EXISTS (SELECT 1 FROM orders        WHERE lower(receipt_hash) = v_hash)
     OR EXISTS (SELECT 1 FROM wallet_topups WHERE lower(receipt_hash) = v_hash) THEN
    RAISE EXCEPTION 'duplicate_receipt_image';
  END IF;

  IF p_amount_expected IS NOT NULL AND p_amount_detected IS NOT NULL
     AND p_amount_expected > 0 THEN
    v_amount_v := abs(p_amount_detected - p_amount_expected) <= GREATEST(p_amount_expected * 0.01, 2);
  END IF;

  v_ref_v := public.normalize_tx_ref(p_tx_ref_ocr) IS NOT NULL
             AND public.normalize_tx_ref(p_tx_ref_ocr) = v_norm;

  IF v_amount_v AND v_ref_v THEN
    IF v_status_in = 'needs_admin_check' THEN
      v_status := 'needs_admin_check';
    ELSE
      v_status := 'passed';
    END IF;
  ELSIF v_status_in = 'needs_admin_check' AND v_scan_id IS NOT NULL THEN
    v_status := 'needs_admin_check';
  ELSE
    v_status := 'needs_review';
  END IF;

  BEGIN
    INSERT INTO payment_receipts (
      user_id, purpose, provider, payment_method_id,
      tx_ref_raw, tx_ref_norm, tx_ref_ocr,
      receipt_hash, receipt_path,
      amount_expected, amount_detected,
      amount_verified, ref_verified,
      ocr_status, ocr_confidence, risk_flags, ocr_data
    ) VALUES (
      v_user_id, p_purpose, nullif(trim(coalesce(p_provider,'')),''), p_payment_method_id,
      trim(p_tx_ref), v_norm, nullif(trim(coalesce(p_tx_ref_ocr,'')),''),
      v_hash, p_receipt_path,
      p_amount_expected, p_amount_detected,
      v_amount_v, v_ref_v,
      v_status, p_ocr_confidence, coalesce(p_risk_flags, '{}'), coalesce(p_ocr_data, '{}'::jsonb)
    )
    RETURNING payment_receipts.id INTO v_id;
  EXCEPTION
    WHEN unique_violation THEN
      IF EXISTS (SELECT 1 FROM payment_receipts WHERE tx_ref_norm = v_norm) THEN
        RAISE EXCEPTION 'duplicate_transaction_ref';
      ELSE
        RAISE EXCEPTION 'duplicate_receipt_image';
      END IF;
  END;

  IF v_scan_id IS NOT NULL THEN
    UPDATE public.receipt_scan_results rs
    SET claimed_at         = COALESCE(rs.claimed_at, now()),
        claimed_receipt_id = COALESCE(rs.claimed_receipt_id, v_id)
    WHERE rs.id = v_scan_id;
  END IF;

  RETURN QUERY SELECT v_id, v_status, v_amount_v, v_ref_v;
END
$function$;


-- consume_chat_rate_limit(p_rate_key text, p_limit integer, p_window_seconds integer); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.consume_chat_rate_limit(p_rate_key text, p_limit integer DEFAULT 12, p_window_seconds integer DEFAULT 600)
 RETURNS TABLE(allowed boolean, retry_after_seconds integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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


-- create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id      uuid := auth.uid();
  v_rate         numeric;
  v_margin       numeric;
  v_coupon_id    uuid;
  v_discount_pct numeric := 0;
  v_total        numeric := 0;
  v_item         jsonb;
  v_product      RECORD;
  v_option       jsonb;
  v_option_usd   numeric;
  v_unit         numeric;
  v_qty          int;
  v_name         text;
  v_order_id     uuid;
  v_lines        jsonb := '[]'::jsonb;
  v_line         jsonb;
  v_ids          uuid[] := '{}';
  v_claim        RECORD;
  v_method_id    uuid;
  v_receipt_url  text;
  v_tx_ref_raw   text;
  v_receipt_hash text;
  v_ocr_in       text;
  v_ocr_final    text;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings ss WHERE ss.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN
    RAISE EXCEPTION 'cart_too_large';
  END IF;
  IF p_receipt IS NULL OR jsonb_typeof(p_receipt) <> 'object' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_method_id   := NULLIF(p_receipt->>'payment_method_id', '')::uuid;
  v_receipt_url := NULLIF(p_receipt->>'receipt_url', '');
  v_ocr_in      := COALESCE(NULLIF(p_receipt->>'ocr_status', ''), 'needs_review');

  IF v_method_id IS NULL THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  -- ── المرور الأول: التحقق وحساب الأسعار من القاعدة فقط ──
  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN
      RAISE EXCEPTION 'invalid_quantity';
    END IF;

    SELECT p.* INTO v_product FROM products p
    WHERE p.id = (v_item->>'product_id')::uuid AND p.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(btrim(v_item->>'option_id'), '') = '' THEN
        RAISE EXCEPTION 'option_required';
      END IF;

      SELECT opt INTO v_option
      FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id')
      LIMIT 1;

      IF v_option IS NULL THEN
        RAISE EXCEPTION 'option_not_found';
      END IF;

      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN
        RAISE EXCEPTION 'price_calculation_error';
      END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;

    v_lines := v_lines || jsonb_build_object(
      'product_id',   v_product.id,
      'name',         v_name,
      'unit',         v_unit,
      'quantity',     v_qty,
      'option',       v_option,
      'field_values', COALESCE(v_item->'field_values', '{}'::jsonb),
      'field_labels', COALESCE(v_item->'field_labels', '{}'::jsonb)
    );

    v_total := v_total + (v_unit * v_qty);
  END LOOP;

  -- ── الكوبون: مرة واحدة فقط للسلة كاملة ──
  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

  -- ── حجز الإيصال داخل نفس المعاملة (المبلغ المتوقع يُحسب هنا) ──
  SELECT c.* INTO v_claim
  FROM public.claim_payment_receipt(
    'order',
    p_receipt->>'tx_ref',
    p_receipt->>'receipt_hash',
    NULLIF(p_receipt->>'receipt_path', ''),
    NULLIF(p_receipt->>'provider', ''),
    v_method_id,
    v_total,
    NULLIF(p_receipt->>'amount_detected', '')::numeric,
    NULLIF(p_receipt->>'tx_ref_ocr', ''),
    v_ocr_in,
    NULLIF(p_receipt->>'ocr_confidence', '')::numeric,
    CASE
      WHEN jsonb_typeof(p_receipt->'risk_flags') = 'array'
      THEN ARRAY(SELECT jsonb_array_elements_text(p_receipt->'risk_flags'))
      ELSE '{}'::text[]
    END,
    COALESCE(p_receipt->'ocr_data', '{}'::jsonb)
  ) c;

  IF v_claim.id IS NULL THEN
    RAISE EXCEPTION 'receipt_claim_failed';
  END IF;

  -- ── إيصال طلب الفحص الذكي تدقيقاً إدارياً لا يُرقّى إلى passed ──
  -- (مثال: إشعار قديم جداً — الرقم والمبلغ مطابقان لكنه يحتاج نظر الإدارة)
  v_ocr_final := v_claim.ocr_status;
  IF v_ocr_in IN ('needs_admin_check', 'needs_review') AND v_ocr_final = 'passed' THEN
    v_ocr_final := v_ocr_in;
    UPDATE payment_receipts pr SET ocr_status = v_ocr_final WHERE pr.id = v_claim.id;
  END IF;

  SELECT pr.tx_ref_raw, pr.receipt_hash
  INTO   v_tx_ref_raw, v_receipt_hash
  FROM   payment_receipts pr WHERE pr.id = v_claim.id;

  -- ── إدخال الطلبات (صف لكل قطعة) ──
  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id,
        payment_method_id, receipt_id, receipt_url, receipt_hash,
        transaction_reference, ocr_status, amount_verified, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'bank', 'pending_review', v_coupon_id,
        v_method_id, v_claim.id, v_receipt_url, v_receipt_hash,
        v_tx_ref_raw, v_ocr_final, v_claim.amount_verified, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;


-- create_code_orders_bulk(p_items jsonb, p_code text, p_coupon_code text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_code_orders_bulk(p_items jsonb, p_code text, p_coupon_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id      uuid := auth.uid();
  v_rate         numeric;
  v_margin       numeric;
  v_coupon_id    uuid;
  v_discount_pct numeric := 0;
  v_total        numeric := 0;
  v_item         jsonb;
  v_product      RECORD;
  v_option       jsonb;
  v_option_usd   numeric;
  v_unit         numeric;
  v_qty          int;
  v_name         text;
  v_order_id     uuid;
  v_lines        jsonb := '[]'::jsonb;
  v_line         jsonb;
  v_ids          uuid[] := '{}';
  v_codeRow      public.payment_codes;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
  IF EXISTS (SELECT 1 FROM store_settings WHERE store_settings.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN RAISE EXCEPTION 'cart_too_large'; END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;

  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

    SELECT * INTO v_product FROM products
    WHERE products.id = (v_item->>'product_id')::uuid AND products.is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'product_not_found'; END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(trim(v_item->>'option_id'), '') = '' THEN RAISE EXCEPTION 'option_required'; END IF;
      SELECT opt INTO v_option FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id') LIMIT 1;
      IF v_option IS NULL THEN RAISE EXCEPTION 'option_not_found'; END IF;
      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;

    v_lines := v_lines || jsonb_build_object(
      'product_id',   v_product.id,
      'name',         v_name,
      'unit',         v_unit,
      'quantity',     v_qty,
      'option',       v_option,
      'field_values', COALESCE(v_item->'field_values', '{}'::jsonb),
      'field_labels', COALESCE(v_item->'field_labels', '{}'::jsonb)
    );

    v_total := v_total + (v_unit * v_qty);
  END LOOP;

  IF p_coupon_code IS NOT NULL AND trim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent INTO v_coupon_id, v_discount_pct
    FROM public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN v_total := 1; END IF;

  SELECT * INTO v_codeRow FROM public.payment_codes
  WHERE upper(replace(code, ' ', '')) = upper(replace(trim(p_code), ' ', ''))
  FOR UPDATE;

  IF v_codeRow.id IS NULL THEN RAISE EXCEPTION 'code_not_found'; END IF;
  IF v_codeRow.status <> 'active' THEN RAISE EXCEPTION 'code_not_active'; END IF;
  IF v_codeRow.expires_at IS NOT NULL AND v_codeRow.expires_at < now() THEN RAISE EXCEPTION 'code_expired'; END IF;
  IF v_codeRow.user_id IS NOT NULL AND v_codeRow.user_id <> v_user_id THEN RAISE EXCEPTION 'code_not_yours'; END IF;
  IF v_codeRow.amount < v_total THEN RAISE EXCEPTION 'code_amount_too_low'; END IF;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id, review_reason, review_severity
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'code', 'in_progress', v_coupon_id,
        'دفع برمز إداري: ' || v_codeRow.code, 'info'
      )
      RETURNING orders.id INTO v_order_id;
      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  UPDATE public.payment_codes
  SET status = 'used', used_by = v_user_id, used_at = now(), order_id = v_ids[1]
  WHERE id = v_codeRow.id;

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;


-- create_wallet_order(p_product_id uuid, p_field_values jsonb, p_field_labels jsonb, p_coupon_code text, p_selected_option_id text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_wallet_order(p_product_id uuid, p_field_values jsonb DEFAULT '{}'::jsonb, p_field_labels jsonb DEFAULT '{}'::jsonb, p_coupon_code text DEFAULT NULL::text, p_selected_option_id text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id          uuid := auth.uid();
  v_product          RECORD;
  v_wallet_balance   numeric;
  v_rate             numeric;
  v_margin           numeric;
  v_price_sdg        numeric;
  v_option           jsonb := NULL;
  v_option_price_usd numeric;
  v_coupon_id        uuid;
  v_discount_pct     numeric := 0;
  v_order_id         uuid;
  v_name_snapshot    text;
  v_new_balance      numeric;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings ss WHERE ss.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  SELECT p.* INTO v_product FROM products p
  WHERE p.id = p_product_id AND p.is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF p_selected_option_id IS NULL OR btrim(p_selected_option_id) = '' THEN
      RAISE EXCEPTION 'option_required';
    END IF;

    SELECT opt INTO v_option
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = p_selected_option_id
    LIMIT 1;

    IF v_option IS NULL THEN
      RAISE EXCEPTION 'option_not_found';
    END IF;

    v_option_price_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
    IF v_option_price_usd <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;
    v_price_sdg     := v_option_price_usd * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
  ELSE
    v_price_sdg     := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
    v_name_snapshot := v_product.name;
  END IF;

  IF v_price_sdg IS NULL OR v_price_sdg <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_price_sdg) uc;
    v_price_sdg := v_price_sdg * (1.0 - LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95) / 100.0);
  END IF;

  v_price_sdg := ROUND(v_price_sdg);
  IF v_price_sdg <= 0 THEN
    v_price_sdg := 1;
  END IF;

  SELECT w.balance INTO v_wallet_balance
  FROM wallets w WHERE w.user_id = v_user_id FOR UPDATE;

  IF v_wallet_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_wallet_balance < v_price_sdg THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets w SET balance = w.balance - v_price_sdg, updated_at = now()
  WHERE w.user_id = v_user_id
  RETURNING w.balance INTO v_new_balance;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  INSERT INTO orders (
    user_id, product_id, product_name_snapshot,
    price_sdg_snapshot, field_values, field_labels, selected_option,
    payment_type, status, coupon_id, refunded
  ) VALUES (
    v_user_id, p_product_id, v_name_snapshot,
    v_price_sdg, COALESCE(p_field_values, '{}'::jsonb),
    COALESCE(p_field_labels, '{}'::jsonb), v_option,
    'wallet', 'in_progress', v_coupon_id, false
  )
  RETURNING orders.id INTO v_order_id;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id)
  VALUES (v_user_id, v_price_sdg, 'debit', v_new_balance, 'wallet_order', v_order_id);

  RETURN QUERY SELECT v_order_id;
END;
$function$;


-- create_wallet_orders_bulk(p_items jsonb, p_coupon_code text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_wallet_orders_bulk(p_items jsonb, p_coupon_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id      uuid := auth.uid();
  v_rate         numeric;
  v_margin       numeric;
  v_balance      numeric;
  v_coupon_id    uuid;
  v_discount_pct numeric := 0;
  v_total        numeric := 0;
  v_item         jsonb;
  v_product      RECORD;
  v_option       jsonb;
  v_option_usd   numeric;
  v_unit         numeric;
  v_qty          int;
  v_name         text;
  v_order_id     uuid;
  v_lines        jsonb := '[]'::jsonb;
  v_line         jsonb;
  v_ids          uuid[] := '{}';
  i              int;
  v_new_balance  numeric;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings ss WHERE ss.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN
    RAISE EXCEPTION 'cart_too_large';
  END IF;

  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN
      RAISE EXCEPTION 'invalid_quantity';
    END IF;

    SELECT p.* INTO v_product FROM products p
    WHERE p.id = (v_item->>'product_id')::uuid AND p.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(btrim(v_item->>'option_id'), '') = '' THEN
        RAISE EXCEPTION 'option_required';
      END IF;

      SELECT opt INTO v_option
      FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id')
      LIMIT 1;

      IF v_option IS NULL THEN
        RAISE EXCEPTION 'option_not_found';
      END IF;

      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN
        RAISE EXCEPTION 'price_calculation_error';
      END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;

    v_lines := v_lines || jsonb_build_object(
      'product_id',   v_product.id,
      'name',         v_name,
      'unit',         v_unit,
      'quantity',     v_qty,
      'option',       v_option,
      'field_values', COALESCE(v_item->'field_values', '{}'::jsonb),
      'field_labels', COALESCE(v_item->'field_labels', '{}'::jsonb)
    );

    v_total := v_total + (v_unit * v_qty);
  END LOOP;

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

  SELECT w.balance INTO v_balance FROM wallets w WHERE w.user_id = v_user_id FOR UPDATE;
  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'wallet_missing';
  END IF;
  IF v_balance < v_total THEN
    RAISE EXCEPTION 'insufficient_balance';
  END IF;

  UPDATE wallets w SET balance = w.balance - v_total, updated_at = now()
  WHERE w.user_id = v_user_id
  RETURNING w.balance INTO v_new_balance;

  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'wallet', 'in_progress', v_coupon_id, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids := array_append(v_ids, v_order_id);
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, details)
  VALUES (v_user_id, v_total, 'debit', v_new_balance, 'wallet_order_bulk', jsonb_build_object('order_ids', v_ids));

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;


-- create_wallet_topup_from_receipt(p_amount numeric, p_payment_method_id uuid, p_receipt_url text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.create_wallet_topup_from_receipt(p_amount numeric, p_payment_method_id uuid, p_receipt_url text, p_tx_ref text, p_receipt_hash text, p_receipt_path text DEFAULT NULL::text, p_provider text DEFAULT NULL::text, p_amount_detected numeric DEFAULT NULL::numeric, p_tx_ref_ocr text DEFAULT NULL::text, p_ocr_status text DEFAULT 'needs_review'::text, p_ocr_confidence numeric DEFAULT NULL::numeric, p_risk_flags text[] DEFAULT '{}'::text[], p_ocr_data jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id uuid, receipt_id uuid, ocr_status text, amount_verified boolean, ref_verified boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                            DECLARE
                                              v_user_id uuid := auth.uid();
                                                v_claim RECORD;
                                                  v_topup_id uuid;
                                                    v_status text := 'pending';
                                                    BEGIN
                                                      IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
                                                        IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
                                                          IF p_amount IS NULL OR p_amount <= 0 OR p_payment_method_id IS NULL THEN
                                                              RAISE EXCEPTION 'invalid_receipt_input';
                                                                END IF;

                                                                  SELECT c.* INTO v_claim
                                                                    FROM public.claim_payment_receipt(
                                                                        'topup',
                                                                            p_tx_ref,
                                                                                p_receipt_hash,
                                                                                    p_receipt_path,
                                                                                        p_provider,
                                                                                            p_payment_method_id,
                                                                                                p_amount,
                                                                                                    p_amount_detected,
                                                                                                        p_tx_ref_ocr,
                                                                                                            COALESCE(NULLIF(p_ocr_status, ''), 'needs_review'),
                                                                                                                p_ocr_confidence,
                                                                                                                    COALESCE(p_risk_flags, '{}'),
                                                                                                                        COALESCE(p_ocr_data, '{}'::jsonb)
                                                                                                                          ) c;

                                                                                                                            IF v_claim.id IS NULL THEN RAISE EXCEPTION 'receipt_claim_failed'; END IF;

                                                                                                                              INSERT INTO public.wallet_topups (
                                                                                                                                  user_id, amount, payment_method_id, receipt_id, receipt_url,
                                                                                                                                      receipt_hash, transaction_reference, status, ocr_status, amount_verified
                                                                                                                                        ) VALUES (
                                                                                                                                            v_user_id, p_amount, p_payment_method_id, v_claim.id, p_receipt_url,
                                                                                                                                                lower(trim(p_receipt_hash)), trim(p_tx_ref), v_status,
                                                                                                                                                    v_claim.ocr_status, v_claim.amount_verified
                                                                                                                                                      )
                                                                                                                                                        RETURNING wallet_topups.id INTO v_topup_id;

                                                                                                                                                          RETURN QUERY SELECT v_topup_id, v_claim.id, v_claim.ocr_status,
                                                                                                                                                                                v_claim.amount_verified, v_claim.ref_verified;
                                                                                                                                                                                END;
$function$;


-- derive_receipt_url_from_receipt(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.derive_receipt_url_from_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_path text;
BEGIN
  -- بلا إيصال موثّق ⇒ لا رابط إطلاقاً (حتى لو أرسل العميل رابطاً)
  IF NEW.receipt_id IS NULL THEN
    NEW.receipt_url := NULL;
    RETURN NEW;
  END IF;

  SELECT r.receipt_path INTO v_path
  FROM public.payment_receipts r
  WHERE r.id = NEW.receipt_id;

  -- المرجع القانوني: مسار داخلي في bucket receipts، والواجهة تولّد الرابط الموقّع
  NEW.receipt_url := CASE
    WHEN v_path IS NULL OR btrim(v_path) = '' THEN NULL
    ELSE 'receipts/' || v_path
  END;
  RETURN NEW;
END
$function$;


-- enforce_coupon_code_strength(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.enforce_coupon_code_strength()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code THEN
    IF length(regexp_replace(coalesce(NEW.code, ''), '[^A-Za-z0-9]', '', 'g')) < 10 THEN
      RAISE EXCEPTION 'coupon_code_too_short: at least 10 alphanumeric characters required';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;


-- generate_order_code(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.generate_order_code()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_code text;
  v_tries int := 0;
BEGIN
  LOOP
    v_code := lpad((floor(random() * 900000) + 100000)::int::text, 6, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.orders WHERE order_code = v_code);
    v_tries := v_tries + 1;
    IF v_tries > 30 THEN
      v_code := lpad((floor(random() * 9000000) + 1000000)::int::text, 7, '0');
      EXIT;
    END IF;
  END LOOP;
  RETURN v_code;
END;
$function$;


-- generate_referral_short_code(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.generate_referral_short_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_code     text;
  v_attempt  integer := 0;
begin
  loop
    v_attempt := v_attempt + 1;
    v_code := 'MEEM';
    for i in 1..8 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where referral_short_code = v_code);
    if v_attempt > 25 then
      raise exception 'referral_code_generation_failed';
    end if;
  end loop;
  return v_code;
end
$function$;


-- get_admin_notification_counts(); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_admin_notification_counts()
 RETURNS TABLE(pending_orders bigint, needs_admin_check bigint, pending_topups bigint, total_alerts bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pending_orders bigint := 0;
  v_needs_check bigint := 0;
  v_pending_topups bigint := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  IF public.has_admin_permission('manage_orders') THEN
    SELECT COUNT(*) INTO v_pending_orders
    FROM public.orders
    WHERE status = 'pending_review';

    SELECT COUNT(*) INTO v_needs_check
    FROM public.orders
    WHERE status NOT IN ('cancelled', 'completed', 'rejected', 'pending_review')
      AND (
        ocr_status = 'needs_admin_check'
        OR NULLIF(btrim(COALESCE(review_reason, '')), '') IS NOT NULL
      );
  END IF;

  IF public.has_admin_permission('manage_wallets') THEN
    SELECT COUNT(*) INTO v_pending_topups
    FROM public.wallet_topups
    WHERE status = 'pending';
  END IF;

  RETURN QUERY SELECT
    v_pending_orders,
    v_needs_check,
    v_pending_topups,
    v_pending_orders + v_needs_check + v_pending_topups;
END;
$function$;


-- get_banners_public(); ACL={postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.get_banners_public()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by (x->>'sort_order')::integer, x->>'created_at'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', b.id,
      'banner_style', b.banner_style,
      'title', b.title,
      'subtitle', b.subtitle,
      'cta_text', b.cta_text,
      'alt_text', b.alt_text,
      'image_desktop_url', b.image_desktop_url,
      'image_mobile_url', b.image_mobile_url,
      'link_type', b.link_type,
      'link_target', b.link_target,
      'whatsapp_message', b.whatsapp_message,
      'overlay_position_desktop', b.overlay_position_desktop,
      'overlay_position_mobile', b.overlay_position_mobile,
      'sort_order', b.sort_order,
      'created_at', b.created_at
    ) as x
    from public.banners b
    where b.status = 'published'
      and b.is_active
      and (b.starts_at is null or b.starts_at <= now())
      and (b.ends_at   is null or b.ends_at   >= now())
      and (
        not b.hide_if_target_inactive
        or b.link_type = 'none'
        or (b.link_type = 'product'  and exists (select 1 from public.products   p where p.id = b.link_target::uuid and p.is_active))
        or (b.link_type = 'category' and exists (select 1 from public.categories c where c.id = b.link_target::uuid and c.is_active))
        or b.link_type in ('page','offers','whatsapp','url')
      )
  ) s;
$function$;


-- get_my_admin_context(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.get_my_admin_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                SELECT jsonb_build_object(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    'user_id', auth.uid(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'legacy_admin', EXISTS (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                              SELECT 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    FROM public.profiles p
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          WHERE p.id = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  AND p.role = 'admin'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      ),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          'is_admin', public.is_admin(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              'is_super_admin', public.is_super_admin(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  'permissions', COALESCE(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                SELECT to_jsonb(ap) - 'created_by' - 'updated_by' - 'created_at' - 'updated_at'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        FROM public.admin_permissions ap
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHERE ap.profile_id = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        LIMIT 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              ),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    '{}'::jsonb
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          );
$function$;


-- get_top_ordered_products(p_limit integer); ACL={postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.get_top_ordered_products(p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with counts as (
    select o.product_id, count(*)::int as ordered
    from public.orders o
    where o.product_id is not null
      and o.status in ('completed','in_progress')
    group by o.product_id
  )
  select coalesce(jsonb_agg(x order by (x->>'ordered')::int desc, x->>'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'image_url', p.image_url,
      'price_usd', p.price_usd,
      'ordered', c.ordered
    ) as x
    from counts c
    join public.products p on p.id = c.product_id and p.is_active
    order by c.ordered desc, p.name
    limit greatest(1, least(coalesce(p_limit, 8), 24))
  ) s;
$function$;


-- handle_new_user(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code      text;
  v_whatsapp  text;
  v_ref_code  text;
  v_referrer  uuid;
begin
  v_code := upper(substr(md5(random()::text || new.id::text), 1, 7));

  -- رقم الواتساب يأتي من raw_user_meta_data (لا يمكن للعميل تحديثه بعد التسجيل لغياب الـ session)
  v_whatsapp := nullif(regexp_replace(coalesce(new.raw_user_meta_data->>'whatsapp_number',''), '[^0-9+]', '', 'g'), '');

  -- كود الإحالة يُحلّ هنا على السيرفر (RLS يمنع العميل من قراءة بروفايلات الآخرين)
  v_ref_code := nullif(upper(trim(coalesce(new.raw_user_meta_data->>'referral_code_used',''))), '');
  if v_ref_code is not null then
    select p.id into v_referrer from public.profiles p where p.referral_code = v_ref_code limit 1;
    if v_referrer = new.id then v_referrer := null; end if;
  end if;

  insert into public.profiles (id, full_name, whatsapp_number, referral_code, referred_by)
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data->>'full_name', ''), 120),
    v_whatsapp,
    v_code,
    v_referrer
  )
  on conflict (id) do nothing;

  insert into public.wallets (user_id, balance)
  values (new.id, 0)
  on conflict (user_id) do nothing;

  return new;
end;
$function$;


-- has_admin_permission(permission_key text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.has_admin_permission(permission_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                      SELECT COALESCE(
                                                                                                                                                                                                                                                          (
                                                                                                                                                                                                                                                                SELECT
                                                                                                                                                                                                                                                                        ap.is_super_admin OR
                                                                                                                                                                                                                                                                                CASE permission_key
                                                                                                                                                                                                                                                                                          WHEN 'manage_orders' THEN ap.can_manage_orders
                                                                                                                                                                                                                                                                                                    WHEN 'manage_wallets' THEN ap.can_manage_wallets
                                                                                                                                                                                                                                                                                                              WHEN 'manage_products' THEN ap.can_manage_products
                                                                                                                                                                                                                                                                                                                        WHEN 'manage_settings' THEN ap.can_manage_settings
                                                                                                                                                                                                                                                                                                                                  WHEN 'manage_maintenance' THEN ap.can_manage_maintenance
                                                                                                                                                                                                                                                                                                                                            WHEN 'manage_admins' THEN ap.can_manage_admins
                                                                                                                                                                                                                                                                                                                                                      WHEN 'manage_coupons' THEN ap.can_manage_coupons
                                                                                                                                                                                                                                                                                                                                                                WHEN 'manage_gift_cards' THEN ap.can_manage_gift_cards
                                                                                                                                                                                                                                                                                                                                                                          WHEN 'view_audit_logs' THEN ap.can_view_audit_logs
                                                                                                                                                                                                                                                                                                                                                                                    ELSE false
                                                                                                                                                                                                                                                                                                                                                                                            END
                                                                                                                                                                                                                                                                                                                                                                                                  FROM public.admin_permissions ap
                                                                                                                                                                                                                                                                                                                                                                                                        WHERE ap.profile_id = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                              LIMIT 1
                                                                                                                                                                                                                                                                                                                                                                                                                  ),
                                                                                                                                                                                                                                                                                                                                                                                                                      false
                                                                                                                                                                                                                                                                                                                                                                                                                        );
$function$;


-- icon_fields_validate(p_mode text, p_key text, p_image text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.icon_fields_validate(p_mode text, p_key text, p_image text)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  v_mode text := coalesce(nullif(btrim(p_mode),''),'auto');
  v_key  text := nullif(btrim(coalesce(p_key,'')),'');
  v_img  text := nullif(btrim(coalesce(p_image,'')),'');
begin
  if v_mode not in ('auto','preset','custom') then raise exception 'INVALID_ICON_MODE'; end if;
  if v_mode = 'preset' then
    if v_key is null or v_key !~ '^[a-z0-9-]{2,40}$' then raise exception 'INVALID_ICON_KEY'; end if;
  end if;
  if v_mode = 'custom' then
    if v_img is null then raise exception 'ICON_IMAGE_REQUIRED'; end if;
    if not public.icon_image_url_ok(v_img) then raise exception 'INVALID_ICON_IMAGE_URL'; end if;
  end if;
end;
$function$;


-- icon_image_url_ok(p_url text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.icon_image_url_ok(p_url text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_url is null then true
    when p_url = '' then true
    when p_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/category-icons/[A-Za-z0-9._/@%-]+$' then true
    else false
  end;
$function$;


-- is_admin(); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
      AND role = 'admin'
      AND COALESCE(is_banned, false) = false
  );
$function$;


-- is_banned(); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_banned()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT is_banned FROM profiles WHERE id = auth.uid()),
    false
  );
$function$;


-- is_super_admin(); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM admin_permissions ap
    JOIN profiles p ON p.id = ap.profile_id
    WHERE ap.profile_id = auth.uid()
      AND ap.is_super_admin = true
      AND p.role = 'admin'
      AND COALESCE(p.is_banned, false) = false
  );
$function$;


-- link_order_payment_code(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.link_order_payment_code()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_code uuid;
BEGIN
  IF NEW.payment_type <> 'code' OR NEW.payment_code_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  SELECT pc.id INTO v_code
  FROM public.payment_codes pc
  WHERE pc.used_by = NEW.user_id
    AND pc.status = 'used'
    AND pc.used_at >= transaction_timestamp()
  ORDER BY pc.used_at DESC
  LIMIT 1;

  IF v_code IS NOT NULL THEN
    PERFORM set_config('raizey.trusted_order', 'on', true);
    UPDATE public.orders SET payment_code_id = v_code WHERE id = NEW.id;
    PERFORM set_config('raizey.trusted_order', 'off', true);
  END IF;
  RETURN NULL;
END
$function$;


-- log_receipt_fraud_attempt(p_entered_reference text, p_reason text, p_provider text, p_ocr_excerpt text, p_order_amount numeric, p_metadata jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.log_receipt_fraud_attempt(p_entered_reference text, p_reason text, p_provider text DEFAULT NULL::text, p_ocr_excerpt text DEFAULT NULL::text, p_order_amount numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- best-effort telemetry: throttle hard, never fail the caller
  BEGIN
    SELECT * INTO v_rate FROM public.consume_chat_rate_limit('fraudlog:' || v_user_id::text, 60, 3600);
    IF NOT v_rate.allowed THEN
      RETURN;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN;
  END;

  INSERT INTO receipt_fraud_attempts (
    user_id, entered_reference, normalized_reference, reason,
    provider, ocr_excerpt, order_amount, metadata
  ) VALUES (
    v_user_id,
    left(coalesce(p_entered_reference, ''), 100),
    public.normalize_tx_ref(p_entered_reference),
    left(coalesce(p_reason, 'unknown'), 60),
    left(coalesce(p_provider, ''), 40),
    left(coalesce(p_ocr_excerpt, ''), 500),
    p_order_amount,
    coalesce(p_metadata, '{}'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  NULL;
END
$function$;


-- normalize_tx_ref(p_ref text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.normalize_tx_ref(p_ref text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT NULLIF(regexp_replace(upper(coalesce(p_ref, '')), '[^A-Z0-9]', '', 'g'), '');
$function$;


-- process_referral_commission(p_user_id uuid, p_order_id uuid); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.process_referral_commission(p_user_id uuid, p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE
  v_referrer_id uuid;
  v_order       RECORD;
  v_commission  numeric;
  v_updated     uuid;
  v_new_balance numeric;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'access_denied: admin only';
  END IF;

  SELECT * INTO v_order FROM orders
  WHERE id = p_order_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF COALESCE(v_order.referral_commission_paid, false) = true THEN RETURN; END IF;
  IF v_order.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  SELECT referred_by INTO v_referrer_id FROM profiles WHERE id = p_user_id;
  IF v_referrer_id IS NULL OR v_referrer_id = p_user_id THEN RETURN; END IF;

  UPDATE orders SET referral_commission_paid = true
  WHERE id = p_order_id AND COALESCE(referral_commission_paid, false) = false
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN RETURN; END IF;

  v_commission := ROUND(COALESCE(v_order.price_sdg_snapshot, 0) * 0.02, 2);
  IF v_commission <= 0 THEN RETURN; END IF;

  INSERT INTO wallets (user_id, balance) VALUES (v_referrer_id, v_commission)
  ON CONFLICT (user_id) DO UPDATE
  SET balance = wallets.balance + v_commission, updated_at = now()
  RETURNING wallets.balance INTO v_new_balance;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id, performed_by)
  VALUES (v_referrer_id, v_commission, 'credit', v_new_balance, 'referral_commission', p_order_id, auth.uid());
END;
$function$;


-- profile_guard_fields_unchanged(p_id uuid, p_role text, p_is_banned boolean, p_referred_by uuid, p_referral_code text, p_referral_short_code text, p_referral_rewarded boolean, p_referral_discount_used boolean, p_milestone10_paid boolean, p_milestone25_paid boolean, p_loyalty_points integer); ACL={postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
CREATE OR REPLACE FUNCTION public.profile_guard_fields_unchanged(p_id uuid, p_role text, p_is_banned boolean, p_referred_by uuid, p_referral_code text, p_referral_short_code text, p_referral_rewarded boolean, p_referral_discount_used boolean, p_milestone10_paid boolean, p_milestone25_paid boolean, p_loyalty_points integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT (p_id = auth.uid()) AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role                    IS NOT DISTINCT FROM p_role
      AND p.is_banned               IS NOT DISTINCT FROM p_is_banned
      AND p.referred_by             IS NOT DISTINCT FROM p_referred_by
      AND p.referral_code           IS NOT DISTINCT FROM p_referral_code
      AND p.referral_short_code     IS NOT DISTINCT FROM p_referral_short_code
      AND p.referral_rewarded       IS NOT DISTINCT FROM p_referral_rewarded
      AND p.referral_discount_used  IS NOT DISTINCT FROM p_referral_discount_used
      AND p.milestone10_paid        IS NOT DISTINCT FROM p_milestone10_paid
      AND p.milestone25_paid        IS NOT DISTINCT FROM p_milestone25_paid
      AND p.loyalty_points          IS NOT DISTINCT FROM p_loyalty_points
  );
$function$;


-- protect_notification_fields(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.protect_notification_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;
  NEW.id         := OLD.id;
  NEW.user_id    := OLD.user_id;
  NEW.title      := OLD.title;
  NEW.message    := OLD.message;
  NEW.type       := OLD.type;
  NEW.created_at := OLD.created_at;
  RETURN NEW;
END;
$function$;


-- protect_order_fields(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.protect_order_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.is_admin()
     OR COALESCE(current_setting('raizey.trusted_order', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  NEW.id                       := OLD.id;
  NEW.user_id                  := OLD.user_id;
  NEW.product_id               := OLD.product_id;
  NEW.product_name_snapshot    := OLD.product_name_snapshot;
  NEW.price_sdg_snapshot       := OLD.price_sdg_snapshot;
  NEW.field_values             := OLD.field_values;
  NEW.field_labels             := OLD.field_labels;
  NEW.selected_option          := OLD.selected_option;
  NEW.payment_type             := OLD.payment_type;
  NEW.payment_method_id        := OLD.payment_method_id;
  NEW.payment_code_id          := OLD.payment_code_id;
  NEW.receipt_id               := OLD.receipt_id;
  NEW.receipt_url              := OLD.receipt_url;
  NEW.receipt_hash             := OLD.receipt_hash;
  NEW.transaction_reference    := OLD.transaction_reference;
  NEW.rejection_reason         := OLD.rejection_reason;
  NEW.ocr_status               := OLD.ocr_status;
  NEW.amount_verified          := OLD.amount_verified;
  NEW.coupon_id                := OLD.coupon_id;
  NEW.referral_commission_paid := OLD.referral_commission_paid;
  NEW.created_at               := OLD.created_at;
  NEW.updated_at               := now();

  RETURN NEW;
END
$function$;


-- protect_profile_columns(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    NEW.role := OLD.role;
    NEW.is_banned := OLD.is_banned;
    NEW.referral_rewarded := OLD.referral_rewarded;
    NEW.milestone10_paid := OLD.milestone10_paid;
    NEW.milestone25_paid := OLD.milestone25_paid;
    NEW.referral_discount_used := OLD.referral_discount_used;
    NEW.referral_code := OLD.referral_code;

    if OLD.referred_by is not null then
      NEW.referred_by := OLD.referred_by;
    elsif NEW.referred_by = NEW.id then
      NEW.referred_by := NULL;
    elsif NEW.referred_by is not null and not exists (select 1 from public.profiles where id = NEW.referred_by) then
      NEW.referred_by := NULL;
    end if;
  end if;
  return NEW;
end;
$function$;


-- protect_profile_fields(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;


-- protect_profile_insert(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.protect_profile_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;
  NEW.role           := 'customer';
  NEW.is_banned      := false;
  NEW.loyalty_points := 0;
  RETURN NEW;
END;
$function$;


-- protect_topup_insert(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.protect_topup_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.receipt_id IS NULL
     OR NULLIF(btrim(COALESCE(NEW.transaction_reference, '')), '') IS NULL THEN
    RAISE EXCEPTION 'topup_requires_receipt';
  END IF;

  NEW.status          := 'pending';
  NEW.reviewed_at     := NULL;
  NEW.amount_verified := false;
  RETURN NEW;
END
$function$;


-- redeem_gift_card(p_code text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.redeem_gift_card(p_code text)
 RETURNS TABLE(amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_card    RECORD;
  v_user_id uuid := auth.uid();
  v_updated uuid;
  v_new_balance numeric;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;

  -- P3-SEC-001: brute-force protection — 10 attempts/hour per user
  SELECT * INTO v_rate FROM public.consume_chat_rate_limit(
    'giftcard:' || v_user_id::text, 10, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'giftcard_rate_limited';
  END IF;

  IF public.normalize_tx_ref(p_code) IS NULL THEN RAISE EXCEPTION 'giftcard_invalid'; END IF;

  SELECT * INTO v_card FROM gift_cards WHERE upper(gift_cards.code) = upper(trim(p_code)) FOR UPDATE;

  IF NOT FOUND OR COALESCE(v_card.is_redeemed, false) = true THEN
    RAISE EXCEPTION 'giftcard_invalid';
  END IF;

  IF v_card.expires_at IS NOT NULL AND v_card.expires_at <= now() THEN
    RAISE EXCEPTION 'giftcard_expired';
  END IF;

  IF COALESCE(v_card.amount, 0) <= 0 THEN RAISE EXCEPTION 'giftcard_invalid'; END IF;

  UPDATE gift_cards
  SET is_redeemed = true, redeemed_by = v_user_id, redeemed_at = now()
  WHERE gift_cards.id = v_card.id AND COALESCE(gift_cards.is_redeemed, false) = false
  RETURNING gift_cards.id INTO v_updated;

  IF v_updated IS NULL THEN RAISE EXCEPTION 'giftcard_invalid'; END IF;

  INSERT INTO wallets (user_id, balance)
  VALUES (v_user_id, v_card.amount)
  ON CONFLICT (user_id) DO UPDATE SET balance = wallets.balance + v_card.amount, updated_at = now()
  RETURNING wallets.balance INTO v_new_balance;

  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, reference_id)
  VALUES (v_user_id, v_card.amount, 'credit', v_new_balance, 'gift_card', v_card.id);

  RETURN QUERY SELECT v_card.amount;
END;
$function$;


-- redeem_loyalty_points(p_points integer); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.redeem_loyalty_points(p_points integer)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare
  v_user_id uuid := auth.uid();
  v_balance integer;
  v_value_rate numeric;
  v_credit numeric;
  v_new_balance numeric;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'invalid_points';
  end if;

  select loyalty_points into v_balance from public.profiles where id = v_user_id for update;

  if v_balance is null or v_balance < p_points then
    raise exception 'insufficient_points';
  end if;

  select coalesce(value::numeric, 0) into v_value_rate from public.settings where key = 'loyalty_point_value_sdg';
  v_credit := p_points * coalesce(v_value_rate, 0);

  update public.profiles set loyalty_points = loyalty_points - p_points where id = v_user_id;
  update public.wallets set balance = balance + v_credit, updated_at = now() where user_id = v_user_id
  returning balance into v_new_balance;

  insert into public.wallet_transactions (user_id, amount, direction, balance_after, source, details)
  values (v_user_id, v_credit, 'credit', v_new_balance, 'loyalty_points', jsonb_build_object('points', p_points));

  insert into public.notifications (user_id, title, message, type)
  values (v_user_id, 'استبدال نقاط الولاء', 'تم تحويل ' || p_points || ' نقطة إلى ' || v_credit || ' جنيه في محفظتك.', 'loyalty');

  return v_credit;
end;
$function$;


-- redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id      uuid := auth.uid();
  v_norm         text;
  v_code         RECORD;
  v_updated      uuid;
  v_rate         numeric;
  v_margin       numeric;
  v_coupon_id    uuid;
  v_discount_pct numeric := 0;
  v_total        numeric := 0;
  v_item         jsonb;
  v_product      RECORD;
  v_option       jsonb;
  v_option_usd   numeric;
  v_unit         numeric;
  v_qty          int;
  v_name         text;
  v_order_id     uuid;
  v_lines        jsonb := '[]'::jsonb;
  v_line         jsonb;
  v_ids          uuid[] := '{}';
  v_last_id      uuid;
  i              int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;
  IF EXISTS (SELECT 1 FROM store_settings ss WHERE ss.maintenance_mode = true)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'maintenance_mode';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'empty_cart';
  END IF;
  IF jsonb_array_length(p_items) > 30 THEN
    RAISE EXCEPTION 'cart_too_large';
  END IF;

  -- ── قفل الرمز أولاً ──
  v_norm := upper(btrim(coalesce(p_code, '')));
  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  FOR UPDATE;

  IF NOT FOUND                                             THEN RAISE EXCEPTION 'not_found';     END IF;
  IF v_code.status = 'cancelled'                            THEN RAISE EXCEPTION 'cancelled';     END IF;
  IF v_code.status <> 'active' OR v_code.used_by IS NOT NULL THEN RAISE EXCEPTION 'already_used'; END IF;
  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN RAISE EXCEPTION 'expired'; END IF;
  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id   THEN RAISE EXCEPTION 'not_your_code'; END IF;

  -- ── حساب الأسعار من القاعدة فقط ──
  SELECT
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT s.value::numeric FROM settings s WHERE s.key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate, 0);
  v_margin := COALESCE(v_margin, 0);
  IF v_rate <= 0 THEN
    RAISE EXCEPTION 'price_calculation_error';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_item->>'quantity')::int, 1);
    IF v_qty < 1 OR v_qty > 20 THEN
      RAISE EXCEPTION 'invalid_quantity';
    END IF;

    SELECT p.* INTO v_product FROM products p
    WHERE p.id = (v_item->>'product_id')::uuid AND p.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'product_not_found';
    END IF;

    v_option := NULL;
    IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
      IF COALESCE(btrim(v_item->>'option_id'), '') = '' THEN
        RAISE EXCEPTION 'option_required';
      END IF;

      SELECT opt INTO v_option
      FROM jsonb_array_elements(v_product.options) opt
      WHERE opt->>'id' = (v_item->>'option_id')
      LIMIT 1;

      IF v_option IS NULL THEN
        RAISE EXCEPTION 'option_not_found';
      END IF;

      v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
      IF v_option_usd <= 0 THEN
        RAISE EXCEPTION 'price_calculation_error';
      END IF;
      v_unit := v_option_usd * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name || ' - ' || COALESCE(v_option->>'label', '');
    ELSE
      v_unit := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
      v_name := v_product.name;
    END IF;

    IF v_unit IS NULL OR v_unit <= 0 THEN
      RAISE EXCEPTION 'price_calculation_error';
    END IF;

    v_lines := v_lines || jsonb_build_object(
      'product_id',   v_product.id,
      'name',         v_name,
      'unit',         v_unit,
      'quantity',     v_qty,
      'option',       v_option,
      'field_values', COALESCE(v_item->'field_values', '{}'::jsonb),
      'field_labels', COALESCE(v_item->'field_labels', '{}'::jsonb)
    );

    v_total := v_total + (v_unit * v_qty);
  END LOOP;

  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    SELECT uc.coupon_id, uc.discount_percent
    INTO   v_coupon_id, v_discount_pct
    FROM   public.use_coupon_atomic(p_coupon_code, v_total) uc;
    v_discount_pct := LEAST(GREATEST(COALESCE(v_discount_pct, 0), 0), 95);
  END IF;

  v_total := ROUND(v_total * (1.0 - v_discount_pct / 100.0));
  IF v_total <= 0 THEN
    v_total := 1;
  END IF;

  -- ── قيمة الرمز يجب أن تغطي الإجمالي (تحقق في السيرفر لا المتصفح) ──
  IF COALESCE(v_code.amount, 0) < v_total THEN
    RAISE EXCEPTION 'amount_too_low';
  END IF;

  -- ── إدخال الطلبات ──
  PERFORM set_config('raizey.trusted_order', 'on', true);

  FOR v_line IN SELECT jsonb_array_elements(v_lines) LOOP
    FOR i IN 1..(v_line->>'quantity')::int LOOP
      INSERT INTO orders (
        user_id, product_id, product_name_snapshot,
        price_sdg_snapshot, field_values, field_labels, selected_option,
        payment_type, status, coupon_id, refunded
      ) VALUES (
        v_user_id,
        (v_line->>'product_id')::uuid,
        v_line->>'name',
        GREATEST(ROUND((v_line->>'unit')::numeric * (1.0 - v_discount_pct / 100.0)), 1),
        v_line->'field_values',
        v_line->'field_labels',
        CASE WHEN v_line->'option' = 'null'::jsonb THEN NULL ELSE v_line->'option' END,
        'code', 'in_progress', v_coupon_id, false
      )
      RETURNING orders.id INTO v_order_id;

      v_ids     := array_append(v_ids, v_order_id);
      v_last_id := v_order_id;
    END LOOP;
  END LOOP;

  PERFORM set_config('raizey.trusted_order', 'off', true);

  -- ── استهلاك الرمز شرطياً: الحاجز الحقيقي ضد الاستخدام المزدوج ──
  UPDATE public.payment_codes pc
  SET status = 'used', used_by = v_user_id, used_at = now(), order_id = v_last_id
  WHERE pc.id = v_code.id AND pc.status = 'active' AND pc.used_by IS NULL
  RETURNING pc.id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'already_used';
  END IF;

  RETURN QUERY SELECT unnest(v_ids);
END;
$function$;


-- report_fraud_alert(p_details jsonb); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.report_fraud_alert(p_details jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id   uuid;
  v_rate RECORD;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('fraudrep:' || auth.uid()::text, 20, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'rate_limited';
  END IF;

  INSERT INTO public.audit_logs (admin_id, action, details, source)
  VALUES (
    NULL,
    'fraud_alert_duplicate_receipt',
    COALESCE(p_details, '{}'::jsonb) || jsonb_build_object('reporter_id', auth.uid()),
    'customer_report'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;


-- rls_auto_enable(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;


-- set_order_code(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_order_code()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.order_code IS NULL THEN
    NEW.order_code := public.generate_order_code();
  END IF;
  RETURN NEW;
END;
$function$;


-- set_row_updated_at(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_row_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  NEW.updated_at := timezone('utc', now());
    RETURN NEW;
    END;
$function$;


-- set_store_exchange_rate(p_rate numeric); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_store_exchange_rate(p_rate numeric)
 RETURNS store_settings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            v_row public.store_settings;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              IF auth.uid() IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      IF NOT public.has_admin_permission('manage_settings') THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          RAISE EXCEPTION 'MISSING_PERMISSION:manage_settings';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              IF p_rate IS NULL OR p_rate <= 0 THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  RAISE EXCEPTION 'INVALID_EXCHANGE_RATE';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      UPDATE public.store_settings
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        SET usd_to_sdg_rate = p_rate,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              updated_by = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                WHERE singleton_key = true
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  RETURNING * INTO v_row;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    PERFORM public.append_admin_audit_log(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'set_store_exchange_rate',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            'store_settings',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                v_row.id::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    jsonb_build_object('usd_to_sdg_rate', p_rate)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      );

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        RETURN v_row;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        END;
$function$;


-- set_store_maintenance(p_enabled boolean, p_message text); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_store_maintenance(p_enabled boolean, p_message text DEFAULT NULL::text)
 RETURNS store_settings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              v_row public.store_settings;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                v_message text := COALESCE(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    NULLIF(trim(p_message), ''),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'الموقع قيد الصيانة والتحديث حالياً، وسنسعد بخدمتكم مجدداً في أقرب وقت ممكن.'
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          );
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            IF auth.uid() IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    IF NOT public.has_admin_permission('manage_maintenance') THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        RAISE EXCEPTION 'MISSING_PERMISSION:manage_maintenance';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            UPDATE public.store_settings
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              SET maintenance_mode = COALESCE(p_enabled, false),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    maintenance_message = v_message,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          updated_by = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            WHERE singleton_key = true
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              RETURNING * INTO v_row;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                PERFORM public.append_admin_audit_log(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    'set_store_maintenance',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        'store_settings',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            v_row.id::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                jsonb_build_object(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      'maintenance_mode', COALESCE(p_enabled, false),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            'maintenance_message', v_message
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  );

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    RETURN v_row;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    END;
$function$;


-- set_store_sections_updated_at(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.set_store_sections_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;


-- touch_subcategories_updated_at(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.touch_subcategories_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;


-- upsert_admin_permissions(p_profile_id uuid, p_is_super_admin boolean, p_can_manage_orders boolean, p_can_manage_wallets boolean, p_can_manage_products boolean, p_can_manage_settings boolean, p_can_manage_maintenance boolean, p_can_manage_admins boolean, p_can_manage_coupons boolean, p_can_manage_gift_cards boolean, p_can_view_audit_logs boolean); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.upsert_admin_permissions(p_profile_id uuid, p_is_super_admin boolean DEFAULT false, p_can_manage_orders boolean DEFAULT false, p_can_manage_wallets boolean DEFAULT false, p_can_manage_products boolean DEFAULT false, p_can_manage_settings boolean DEFAULT false, p_can_manage_maintenance boolean DEFAULT false, p_can_manage_admins boolean DEFAULT false, p_can_manage_coupons boolean DEFAULT false, p_can_manage_gift_cards boolean DEFAULT false, p_can_view_audit_logs boolean DEFAULT false)
 RETURNS admin_permissions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          DECLARE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            v_row public.admin_permissions;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              v_super_admin_count integer;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              BEGIN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                IF auth.uid() IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    RAISE EXCEPTION 'AUTH_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        IF NOT public.has_admin_permission('manage_admins') THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            RAISE EXCEPTION 'MISSING_PERMISSION:manage_admins';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                IF p_profile_id IS NULL THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    RAISE EXCEPTION 'PROFILE_ID_REQUIRED';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        SELECT count(*)
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          INTO v_super_admin_count
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            FROM public.admin_permissions
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              WHERE is_super_admin = true;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                IF v_super_admin_count = 1
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     AND p_is_super_admin = false
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          AND p_profile_id = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               AND public.is_super_admin() THEN
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   RAISE EXCEPTION 'LAST_SUPER_ADMIN_PROTECTION';
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     END IF;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       INSERT INTO public.admin_permissions (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           profile_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               is_super_admin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_manage_orders,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       can_manage_wallets,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           can_manage_products,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_manage_settings,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_manage_maintenance,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       can_manage_admins,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           can_manage_coupons,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_manage_gift_cards,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_view_audit_logs,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       created_by,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           updated_by
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               VALUES (
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   p_profile_id,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       p_is_super_admin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           p_is_super_admin OR p_can_manage_orders,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               p_is_super_admin OR p_can_manage_wallets,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   p_is_super_admin OR p_can_manage_products,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       p_is_super_admin OR p_can_manage_settings,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           p_is_super_admin OR p_can_manage_maintenance,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               p_is_super_admin OR p_can_manage_admins,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   p_is_super_admin OR p_can_manage_coupons,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       p_is_super_admin OR p_can_manage_gift_cards,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           p_is_super_admin OR p_can_view_audit_logs,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               auth.uid(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       ON CONFLICT (profile_id) DO UPDATE
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         SET is_super_admin = EXCLUDED.is_super_admin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_manage_orders = EXCLUDED.can_manage_orders,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     can_manage_wallets = EXCLUDED.can_manage_wallets,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           can_manage_products = EXCLUDED.can_manage_products,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 can_manage_settings = EXCLUDED.can_manage_settings,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       can_manage_maintenance = EXCLUDED.can_manage_maintenance,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             can_manage_admins = EXCLUDED.can_manage_admins,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   can_manage_coupons = EXCLUDED.can_manage_coupons,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         can_manage_gift_cards = EXCLUDED.can_manage_gift_cards,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               can_view_audit_logs = EXCLUDED.can_view_audit_logs,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     updated_by = auth.uid()
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       RETURNING * INTO v_row;

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         PERFORM public.append_admin_audit_log(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             'upsert_admin_permissions',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 'admin_permissions',
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     p_profile_id::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         jsonb_build_object(
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               'is_super_admin', v_row.is_super_admin,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     'can_manage_orders', v_row.can_manage_orders,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           'can_manage_wallets', v_row.can_manage_wallets,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 'can_manage_products', v_row.can_manage_products,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       'can_manage_settings', v_row.can_manage_settings,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             'can_manage_maintenance', v_row.can_manage_maintenance,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   'can_manage_admins', v_row.can_manage_admins,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         'can_manage_coupons', v_row.can_manage_coupons,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               'can_manage_gift_cards', v_row.can_manage_gift_cards,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     'can_view_audit_logs', v_row.can_view_audit_logs
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         )
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           );

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             RETURN v_row;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             END;
$function$;


-- use_coupon_atomic(p_code text, p_order_total numeric); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.use_coupon_atomic(p_code text, p_order_total numeric DEFAULT NULL::numeric)
 RETURNS TABLE(coupon_id uuid, discount_percent numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
  v_pct     numeric;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT c.* INTO v_coupon FROM coupons c
  WHERE upper(c.code) = upper(btrim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF p_order_total IS NOT NULL AND COALESCE(v_coupon.min_order_sdg, 0) > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  BEGIN
    INSERT INTO coupon_redemptions (coupon_id, user_id) VALUES (v_coupon.id, v_user_id);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'coupon_already_used';
  END;

  UPDATE coupons c SET uses_count = COALESCE(c.uses_count, 0) + 1
  WHERE c.id = v_coupon.id;

  v_pct := LEAST(GREATEST(COALESCE(v_coupon.discount_percent, 0), 0), 95);
  RETURN QUERY SELECT v_coupon.id, v_pct;
END;
$function$;


-- validate_coupon(p_code text, p_order_total numeric); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.validate_coupon(p_code text, p_order_total numeric DEFAULT NULL::numeric)
 RETURNS TABLE(coupon_id uuid, discount_percent numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_coupon  RECORD;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('coupon:' || v_user_id::text, 60, 3600);
  IF NOT v_rate.allowed THEN
    RAISE EXCEPTION 'coupon_rate_limited';
  END IF;

  SELECT c.id, c.discount_percent AS pct, COALESCE(c.min_order_sdg, 0) AS min_order_sdg
  INTO v_coupon
  FROM coupons c
  WHERE upper(c.code) = upper(btrim(p_code))
    AND c.is_active = true
    AND (c.max_uses   IS NULL OR COALESCE(c.uses_count, 0) < c.max_uses)
    AND (c.expires_at IS NULL OR c.expires_at > now())
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_invalid';
  END IF;

  IF EXISTS (
    SELECT 1 FROM coupon_redemptions cr
    WHERE cr.coupon_id = v_coupon.id AND cr.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'coupon_already_used';
  END IF;

  IF p_order_total IS NOT NULL AND v_coupon.min_order_sdg > 0
     AND p_order_total < v_coupon.min_order_sdg THEN
    RAISE EXCEPTION 'coupon_min_order';
  END IF;

  RETURN QUERY SELECT v_coupon.id, LEAST(GREATEST(COALESCE(v_coupon.pct, 0), 0), 95);
END
$function$;


-- validate_payment_code(p_code text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.validate_payment_code(p_code text)
 RETURNS TABLE(valid boolean, reason text, amount numeric, note text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_user_id uuid := auth.uid();
  v_code    RECORD;
  v_norm    text;
  v_rate    RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  SELECT * INTO v_rate FROM public.consume_chat_rate_limit('paycode:' || v_user_id::text, 60, 3600);
  IF NOT v_rate.allowed THEN
    RETURN QUERY SELECT false, 'rate_limited'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  v_norm := upper(btrim(coalesce(p_code, '')));
  -- أكواد الدفع 13 خانة (RZY-XXXX-XXXX)؛ أي مدخل أقصر مرفوض قبل أي بحث
  IF length(v_norm) < 10 THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  SELECT pc.* INTO v_code
  FROM public.payment_codes pc
  WHERE upper(btrim(pc.code)) = v_norm
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'not_found'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'cancelled' THEN
    RETURN QUERY SELECT false, 'cancelled'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.status = 'used' OR v_code.used_by IS NOT NULL THEN
    RETURN QUERY SELECT false, 'already_used'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.expires_at IS NOT NULL AND v_code.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'expired'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  IF v_code.user_id IS NOT NULL AND v_code.user_id <> v_user_id THEN
    RETURN QUERY SELECT false, 'not_your_code'::text, NULL::numeric, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'ok'::text, v_code.amount, v_code.note;
END
$function$;


-- validate_receipt_path(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.validate_receipt_path()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.receipt_path IS NOT NULL AND btrim(NEW.receipt_path) <> '' THEN
    IF NEW.receipt_path !~ ('^' || NEW.user_id::text || '/([A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+$') THEN
      RAISE EXCEPTION 'receipt_path_not_owned: path must live under the owner folder (%)', NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END
$function$;


-- validate_referral_short_code(p_code text); ACL={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}
CREATE OR REPLACE FUNCTION public.validate_referral_short_code(p_code text)
 RETURNS TABLE(valid boolean, reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;


-- verify_order_price_before_insert(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.verify_order_price_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_product      RECORD;
  v_receipt      RECORD;
  v_rate         numeric;
  v_margin       numeric;
  v_expected     numeric;
  v_option_usd   numeric;
  v_discount_pct numeric := 0;
  v_min_allowed  numeric;
  v_option       jsonb;
  v_option_id    text;
BEGIN
  IF COALESCE(current_setting('raizey.trusted_order', true), '') = 'on'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_product
  FROM products
  WHERE products.id = NEW.product_id AND products.is_active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'product_not_found'; END IF;

  -- ── Bank orders must reference the caller's own, server-verified receipt ──
  IF NEW.payment_type = 'bank' THEN
    IF NEW.receipt_id IS NULL THEN
      RAISE EXCEPTION 'receipt_required';
    END IF;
    SELECT * INTO v_receipt
    FROM public.payment_receipts pr
    WHERE pr.id = NEW.receipt_id
      AND pr.user_id = auth.uid()
      AND pr.ocr_status IN ('passed', 'needs_admin_check')
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'receipt_not_verified';
    END IF;
  END IF;

  SELECT
    (SELECT value::numeric FROM settings WHERE key = 'usd_to_sdg_rate'       LIMIT 1),
    (SELECT value::numeric FROM settings WHERE key = 'profit_margin_percent' LIMIT 1)
  INTO v_rate, v_margin;

  v_rate   := COALESCE(v_rate,   0);
  v_margin := COALESCE(v_margin, 0);

  IF jsonb_array_length(COALESCE(v_product.options, '[]'::jsonb)) > 0 THEN
    IF NEW.selected_option IS NULL
       OR COALESCE(btrim(NEW.selected_option->>'id'), '') = '' THEN
      RAISE EXCEPTION 'option_required';
    END IF;

    v_option_id := NEW.selected_option->>'id';
    SELECT opt INTO v_option
    FROM jsonb_array_elements(v_product.options) opt
    WHERE opt->>'id' = v_option_id
    LIMIT 1;
    IF v_option IS NULL THEN RAISE EXCEPTION 'option_not_found'; END IF;

    v_option_usd := COALESCE((v_option->>'price_usd')::numeric, 0);
    IF v_option_usd <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;
    v_expected := v_option_usd * v_rate * (1 + v_margin / 100.0);
  ELSE
    v_expected := COALESCE(v_product.price_usd, 0) * v_rate * (1 + v_margin / 100.0);
  END IF;

  IF v_expected <= 0 THEN RAISE EXCEPTION 'price_calculation_error'; END IF;

  IF NEW.coupon_id IS NOT NULL THEN
    SELECT discount_percent INTO v_discount_pct
    FROM coupons
    WHERE id = NEW.coupon_id AND is_active = true
      AND (valid_from IS NULL OR now() >= valid_from)
      AND (valid_until IS NULL OR now() <= valid_until);
    IF NOT FOUND OR COALESCE(v_discount_pct, 0) <= 0 THEN
      RAISE EXCEPTION 'coupon_invalid';
    END IF;
  END IF;

  v_min_allowed := v_expected * (1 - COALESCE(v_discount_pct, 0) / 100.0) * 0.99;

  IF NEW.price_sdg_snapshot < v_min_allowed THEN
    RAISE EXCEPTION 'price_tampered';
  END IF;

  RETURN NEW;
END
$function$;


-- verify_privilege_model(); ACL={postgres=X/postgres,service_role=X/postgres}
CREATE OR REPLACE FUNCTION public.verify_privilege_model()
 RETURNS TABLE(check_name text, passed boolean, details text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY SELECT 'is_admin_single_banned'::text,
    (SELECT count(*) = 1 AND bool_and(p.prosrc LIKE '%is_banned%')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'is_admin'),
    'is_admin must be exactly one definition and enforce the banned check'::text;

  RETURN QUERY SELECT 'is_super_admin_single_banned'::text,
    (SELECT count(*) = 1 AND bool_and(p.prosrc LIKE '%is_banned%')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'is_super_admin'),
    'is_super_admin must be exactly one definition and enforce the banned check'::text;

  RETURN QUERY SELECT 'no_anon_grants_except_settings_ro'::text,
    (SELECT NOT EXISTS (
       SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND c.relname IN ('profiles','audit_logs','wallet_topups','wallets','wallet_transactions',
                           'payment_receipts','receipt_scan_results','coupons','gift_cards',
                           'admin_permissions','orders','coupon_redemptions')
         AND c.relacl::text LIKE '%anon=%')
     AND (SELECT c.relacl::text ~ 'anon=r/' AND c.relacl::text !~ 'anon=[^,}]*[wWdD]'
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'settings')),
    'anon must have no grants on sensitive tables; settings anon grant must stay read-only'::text;

  RETURN QUERY SELECT 'no_open_policies'::text,
    (SELECT NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename IN ('profiles','audit_logs','wallet_topups','wallets','wallet_transactions',
                           'payment_receipts','receipt_scan_results','coupons','gift_cards',
                           'settings','admin_permissions','orders','coupon_redemptions')
         AND (qual = 'true' OR with_check = 'true'))),
    'no permissive USING(true) policies on sensitive tables'::text;

  -- (جديد) لا EXECUTE لـ anon على validate_referral_short_code
  RETURN QUERY SELECT 'anon_referral_oracle_revoked'::text,
    NOT has_function_privilege('anon', 'public.validate_referral_short_code(text)', 'EXECUTE'),
    'anon must not be able to enumerate referral codes'::text;

  -- (جديد) pg_stat_statements مغلق أمام أدوار العملاء + PUBLIC
  RETURN QUERY SELECT 'pg_stat_statements_locked'::text,
    (NOT has_table_privilege('anon', 'extensions.pg_stat_statements', 'SELECT')
     AND NOT has_table_privilege('authenticated', 'extensions.pg_stat_statements', 'SELECT')),
    'anon/authenticated must not read pg_stat_statements'::text;

  -- (جديد) سياسة profiles_update_own تحرس الحقول الحساسة في WITH CHECK
  RETURN QUERY SELECT 'profiles_update_guarded_with_check'::text,
    (SELECT count(*) = 1
       AND bool_and(with_check LIKE '%profile_guard_fields_unchanged%')
     FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = 'profiles_update_own'
       AND cmd = 'UPDATE'),
    'profiles_update_own must re-guard role/is_banned/referred_by in WITH CHECK'::text;

  -- (جديد) اشتقاق receipt_url خادمياً محميّ بتريجر على orders و wallet_topups
  RETURN QUERY SELECT 'receipt_url_derived_server_side'::text,
    ((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'orders'
         AND t.tgname = 'trg_derive_receipt_url_orders') = 1
     AND (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'wallet_topups'
         AND t.tgname = 'trg_derive_receipt_url_topups') = 1
     AND (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'payment_receipts'
         AND t.tgname = 'trg_validate_receipt_path') = 1),
    'receipt_url must be derived from payment_receipts.receipt_path via triggers'::text;

  -- (جديد) لا EXECUTE لـ anon/authenticated على دالة اختبار داخلية
  RETURN QUERY SELECT 'internal_test_fn_not_exposed'::text,
    (NOT has_function_privilege('anon', 'public.verify_privilege_model()', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.verify_privilege_model()', 'EXECUTE')),
    'verify_privilege_model must not be reachable from client roles'::text;

  -- (جديد) الكوبونات الجديدة 10 خانات على الأقل (تريجر قائم)
  RETURN QUERY SELECT 'coupon_code_strength_enforced'::text,
    ((SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE NOT t.tgisinternal AND c.relname = 'coupons'
         AND t.tgname = 'trg_enforce_coupon_code_strength') = 1),
    'coupons must reject new codes shorter than 10 alphanumeric characters'::text;
END
$function$;


ALTER TABLE "public"."coupons" ADD CONSTRAINT "coupons_code_key" UNIQUE (code);
ALTER TABLE "public"."coupons" ADD CONSTRAINT "coupons_discount_percent_check" CHECK (((discount_percent > (0)::numeric) AND (discount_percent <= (100)::numeric)));
ALTER TABLE "public"."coupons" ADD CONSTRAINT "coupons_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."gift_cards" ADD CONSTRAINT "gift_cards_code_key" UNIQUE (code);
ALTER TABLE "public"."gift_cards" ADD CONSTRAINT "gift_cards_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."receipt_scan_results" ADD CONSTRAINT "receipt_scan_results_decision_check" CHECK ((decision = ANY (ARRAY['accept'::text, 'reject'::text, 'review'::text, 'review_admin'::text])));
ALTER TABLE "public"."receipt_scan_results" ADD CONSTRAINT "receipt_scan_results_image_bytes_check" CHECK (((image_bytes > 0) AND (image_bytes <= 33554432)));
ALTER TABLE "public"."receipt_scan_results" ADD CONSTRAINT "receipt_scan_results_mime_type_check" CHECK ((mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'image/heic'::text, 'image/heif'::text])));
ALTER TABLE "public"."receipt_scan_results" ADD CONSTRAINT "receipt_scan_results_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."receipt_scan_results" ADD CONSTRAINT "receipt_scan_results_receipt_hash_check" CHECK ((receipt_hash ~ '^[0-9a-f]{64}$'::text));
ALTER TABLE "public"."categories" ADD CONSTRAINT "categories_icon_key_chk" CHECK (((icon_key IS NULL) OR (icon_key ~ '^[a-z0-9-]{2,40}$'::text)));
ALTER TABLE "public"."categories" ADD CONSTRAINT "categories_icon_mode_chk" CHECK ((icon_mode = ANY (ARRAY['auto'::text, 'preset'::text, 'custom'::text])));
ALTER TABLE "public"."categories" ADD CONSTRAINT "categories_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."products" ADD CONSTRAINT "products_delivery_badge_text_length" CHECK (((delivery_badge_text IS NULL) OR (char_length(delivery_badge_text) <= 120)));
ALTER TABLE "public"."products" ADD CONSTRAINT "products_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."receipt_fraud_attempts" ADD CONSTRAINT "receipt_fraud_attempts_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."admin_permissions" ADD CONSTRAINT "admin_permissions_pkey" PRIMARY KEY (profile_id);
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_player_ids_object_check" CHECK ((jsonb_typeof(player_ids) = 'object'::text));
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_referral_code_key" UNIQUE (referral_code);
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_referral_short_code_format" CHECK (((referral_short_code IS NULL) OR (referral_short_code ~ '^[A-Z0-9]{5,12}$'::text)));
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_role_check" CHECK ((role = ANY (ARRAY['customer'::text, 'admin'::text])));
ALTER TABLE "public"."payment_methods" ADD CONSTRAINT "payment_methods_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."settings" ADD CONSTRAINT "settings_pkey" PRIMARY KEY (key);
ALTER TABLE "public"."admin_audit_logs" ADD CONSTRAINT "admin_audit_logs_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."audit_logs" ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."wallet_topups" ADD CONSTRAINT "unique_wallet_topups_ref" UNIQUE (receipt_hash);
ALTER TABLE "public"."wallet_topups" ADD CONSTRAINT "wallet_topups_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."wallet_topups" ADD CONSTRAINT "wallet_topups_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'rejected'::text])));
ALTER TABLE "public"."wallets" ADD CONSTRAINT "wallets_pkey" PRIMARY KEY (user_id);
ALTER TABLE "public"."wallet_transactions" ADD CONSTRAINT "wallet_transactions_direction_check" CHECK ((direction = ANY (ARRAY['credit'::text, 'debit'::text])));
ALTER TABLE "public"."wallet_transactions" ADD CONSTRAINT "wallet_transactions_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."store_settings" ADD CONSTRAINT "store_settings_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."store_settings" ADD CONSTRAINT "store_settings_singleton_key_check" CHECK ((singleton_key = true));
ALTER TABLE "public"."store_settings" ADD CONSTRAINT "store_settings_singleton_key_uniq" UNIQUE (singleton_key);
ALTER TABLE "public"."store_settings" ADD CONSTRAINT "store_settings_usd_to_sdg_rate_check" CHECK ((usd_to_sdg_rate >= (0)::numeric));
ALTER TABLE "public"."referral_milestones" ADD CONSTRAINT "referral_milestones_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."referral_milestone_payouts" ADD CONSTRAINT "referral_milestone_payouts_pkey" PRIMARY KEY (referrer_id, milestone_id);
ALTER TABLE "public"."notifications" ADD CONSTRAINT "notifications_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."payment_receipts" ADD CONSTRAINT "payment_receipts_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."payment_receipts" ADD CONSTRAINT "payment_receipts_purpose_check" CHECK ((purpose = ANY (ARRAY['order'::text, 'topup'::text])));
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_amount_check" CHECK ((amount > (0)::numeric));
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_code_key" UNIQUE (code);
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'used'::text, 'cancelled'::text])));
ALTER TABLE "public"."coupon_redemptions" ADD CONSTRAINT "coupon_redemptions_coupon_id_user_id_key" UNIQUE (coupon_id, user_id);
ALTER TABLE "public"."coupon_redemptions" ADD CONSTRAINT "coupon_redemptions_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."subcategories" ADD CONSTRAINT "subcategories_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_payment_type_check" CHECK ((payment_type = ANY (ARRAY['wallet'::text, 'bank'::text, 'code'::text])));
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_status_check" CHECK ((status = ANY (ARRAY['pending_review'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text, 'rejected'::text])));
ALTER TABLE "public"."orders" ADD CONSTRAINT "unique_orders_receipt_hash" UNIQUE (receipt_hash);
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_cta_len" CHECK (((cta_text IS NULL) OR (char_length(cta_text) <= 20)));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_img_d_chk" CHECK ((image_desktop_url ~ '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$'::text));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_img_m_chk" CHECK (((image_mobile_url IS NULL) OR (image_mobile_url ~ '^(/[^/[:space:]][^[:space:]]*|https://[^[:space:]]+)$'::text)));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_link_chk" CHECK ((link_type = ANY (ARRAY['none'::text, 'page'::text, 'product'::text, 'category'::text, 'offers'::text, 'whatsapp'::text, 'url'::text])));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_no_scheme_abuse" CHECK (((image_desktop_url !~~* 'javascript:%'::text) AND (image_desktop_url !~~* 'data:%'::text) AND (COALESCE(image_mobile_url, ''::text) !~~* 'javascript:%'::text) AND (COALESCE(image_mobile_url, ''::text) !~~* 'data:%'::text) AND ((link_target IS NULL) OR ((link_target !~~* 'javascript:%'::text) AND (link_target !~~* 'data:%'::text)))));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_ovd_chk" CHECK ((overlay_position_desktop = ANY (ARRAY['right'::text, 'left'::text])));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_ovm_chk" CHECK ((overlay_position_mobile = ANY (ARRAY['top'::text, 'bottom'::text])));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_status_chk" CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_style_chk" CHECK ((banner_style = ANY (ARRAY['image_only'::text, 'image_text'::text])));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_subtitle_len" CHECK (((subtitle IS NULL) OR (char_length(subtitle) <= 90)));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_target_chk" CHECK (
CASE link_type
    WHEN 'none'::text THEN (link_target IS NULL)
    WHEN 'offers'::text THEN (link_target IS NULL)
    WHEN 'whatsapp'::text THEN (link_target IS NULL)
    WHEN 'url'::text THEN (link_target ~ '^https://'::text)
    ELSE (COALESCE(btrim(link_target), ''::text) <> ''::text)
END);
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_text_chk" CHECK (((banner_style <> 'image_text'::text) OR ((title IS NOT NULL) AND (btrim(title) <> ''::text))));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_title_len" CHECK (((title IS NULL) OR (char_length(title) <= 45)));
ALTER TABLE "public"."banners" ADD CONSTRAINT "banners_window_chk" CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at > starts_at)));
ALTER TABLE "public"."store_sections" ADD CONSTRAINT "store_sections_icon_key_chk" CHECK (((icon_key IS NULL) OR (icon_key ~ '^[a-z0-9-]{2,40}$'::text)));
ALTER TABLE "public"."store_sections" ADD CONSTRAINT "store_sections_icon_mode_chk" CHECK ((icon_mode = ANY (ARRAY['auto'::text, 'preset'::text, 'custom'::text])));
ALTER TABLE "public"."store_sections" ADD CONSTRAINT "store_sections_name_not_blank" CHECK ((length(btrim(name)) > 0));
ALTER TABLE "public"."store_sections" ADD CONSTRAINT "store_sections_name_unique" UNIQUE (name);
ALTER TABLE "public"."store_sections" ADD CONSTRAINT "store_sections_pkey" PRIMARY KEY (id);
ALTER TABLE "public"."gift_cards" ADD CONSTRAINT "gift_cards_redeemed_by_fkey" FOREIGN KEY (redeemed_by) REFERENCES profiles(id);
ALTER TABLE "public"."receipt_scan_results" ADD CONSTRAINT "receipt_scan_results_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE "public"."categories" ADD CONSTRAINT "categories_section_id_fkey" FOREIGN KEY (section_id) REFERENCES store_sections(id) ON DELETE RESTRICT;
ALTER TABLE "public"."products" ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE "public"."receipt_fraud_attempts" ADD CONSTRAINT "receipt_fraud_attempts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE "public"."admin_permissions" ADD CONSTRAINT "admin_permissions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE "public"."admin_permissions" ADD CONSTRAINT "admin_permissions_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE "public"."admin_permissions" ADD CONSTRAINT "admin_permissions_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_referred_by_fkey" FOREIGN KEY (referred_by) REFERENCES profiles(id);
ALTER TABLE "public"."admin_audit_logs" ADD CONSTRAINT "admin_audit_logs_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE "public"."audit_logs" ADD CONSTRAINT "audit_logs_admin_id_fkey" FOREIGN KEY (admin_id) REFERENCES profiles(id);
ALTER TABLE "public"."wallet_topups" ADD CONSTRAINT "wallet_topups_payment_method_id_fkey" FOREIGN KEY (payment_method_id) REFERENCES payment_methods(id);
ALTER TABLE "public"."wallet_topups" ADD CONSTRAINT "wallet_topups_receipt_id_fkey" FOREIGN KEY (receipt_id) REFERENCES payment_receipts(id);
ALTER TABLE "public"."wallet_topups" ADD CONSTRAINT "wallet_topups_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE "public"."wallets" ADD CONSTRAINT "wallets_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE "public"."wallet_transactions" ADD CONSTRAINT "wallet_transactions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE "public"."store_settings" ADD CONSTRAINT "store_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE "public"."referral_milestone_payouts" ADD CONSTRAINT "referral_milestone_payouts_milestone_id_fkey" FOREIGN KEY (milestone_id) REFERENCES referral_milestones(id);
ALTER TABLE "public"."referral_milestone_payouts" ADD CONSTRAINT "referral_milestone_payouts_referrer_id_fkey" FOREIGN KEY (referrer_id) REFERENCES profiles(id);
ALTER TABLE "public"."notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE "public"."payment_receipts" ADD CONSTRAINT "payment_receipts_parent_receipt_id_fkey" FOREIGN KEY (parent_receipt_id) REFERENCES payment_receipts(id) ON DELETE SET NULL;
ALTER TABLE "public"."payment_receipts" ADD CONSTRAINT "payment_receipts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_created_by_fkey" FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL;
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_used_by_fkey" FOREIGN KEY (used_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE "public"."payment_codes" ADD CONSTRAINT "payment_codes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE "public"."coupon_redemptions" ADD CONSTRAINT "coupon_redemptions_coupon_id_fkey" FOREIGN KEY (coupon_id) REFERENCES coupons(id) ON DELETE CASCADE;
ALTER TABLE "public"."coupon_redemptions" ADD CONSTRAINT "coupon_redemptions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE "public"."subcategories" ADD CONSTRAINT "subcategories_category_id_fkey" FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE RESTRICT;
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_coupon_id_fkey" FOREIGN KEY (coupon_id) REFERENCES coupons(id) ON DELETE SET NULL;
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_payment_code_id_fkey" FOREIGN KEY (payment_code_id) REFERENCES payment_codes(id) ON DELETE SET NULL;
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_payment_method_id_fkey" FOREIGN KEY (payment_method_id) REFERENCES payment_methods(id);
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_product_id_fkey" FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_receipt_id_fkey" FOREIGN KEY (receipt_id) REFERENCES payment_receipts(id);
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_user_id_fkey" FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
CREATE INDEX idx_coupons_code ON public.coupons USING btree (upper(code)) WHERE (is_active = true);
CREATE INDEX idx_gift_cards_code ON public.gift_cards USING btree (upper(code)) WHERE (is_redeemed = false);
CREATE INDEX idx_gift_cards_redeemed_by ON public.gift_cards USING btree (redeemed_by);
CREATE INDEX idx_receipt_scan_results_user_created ON public.receipt_scan_results USING btree (user_id, created_at DESC);
CREATE INDEX idx_receipt_scan_results_expires ON public.receipt_scan_results USING btree (expires_at);
CREATE INDEX idx_receipt_scan_results_hash ON public.receipt_scan_results USING btree (receipt_hash);
CREATE UNIQUE INDEX chat_rate_limits_pkey ON private.chat_rate_limits USING btree (rate_key);
CREATE INDEX idx_categories_active_order ON public.categories USING btree (is_active, display_order, name);
CREATE INDEX categories_section_active_order_idx ON public.categories USING btree (section_id, is_active, display_order, name);
CREATE INDEX idx_products_category_active_order ON public.products USING btree (category_id, is_active, display_order);
CREATE INDEX idx_products_active_flash_sale ON public.products USING btree (is_active, flash_sale_ends_at) WHERE (flash_sale_ends_at IS NOT NULL);
CREATE INDEX products_on_offer_idx ON public.products USING btree (is_on_offer) WHERE is_on_offer;
CREATE INDEX idx_fraud_attempts_user ON public.receipt_fraud_attempts USING btree (user_id, created_at DESC);
CREATE INDEX idx_fraud_attempts_ref ON public.receipt_fraud_attempts USING btree (normalized_reference);
CREATE INDEX idx_admin_permissions_super_admin ON public.admin_permissions USING btree (is_super_admin) WHERE (is_super_admin = true);
CREATE INDEX idx_admin_permissions_created_by ON public.admin_permissions USING btree (created_by);
CREATE INDEX idx_admin_permissions_updated_by ON public.admin_permissions USING btree (updated_by);
CREATE INDEX idx_profiles_role ON public.profiles USING btree (role);
CREATE UNIQUE INDEX uq_profiles_referral_short_code ON public.profiles USING btree (referral_short_code) WHERE (referral_short_code IS NOT NULL);
CREATE INDEX idx_profiles_referral_short_code ON public.profiles USING btree (referral_short_code);
CREATE INDEX idx_profiles_referred_by ON public.profiles USING btree (referred_by);
CREATE UNIQUE INDEX profiles_referral_code_uniq ON public.profiles USING btree (upper(referral_code)) WHERE (referral_code IS NOT NULL);
CREATE INDEX idx_admin_audit_logs_admin_id_created_at ON public.admin_audit_logs USING btree (admin_id, created_at DESC);
CREATE INDEX idx_admin_audit_logs_target ON public.admin_audit_logs USING btree (target_table, target_id);
CREATE INDEX idx_audit_logs_admin_id ON public.audit_logs USING btree (admin_id);
CREATE INDEX idx_topups_receipt_hash ON public.wallet_topups USING btree (receipt_hash) WHERE (receipt_hash IS NOT NULL);
CREATE INDEX idx_topups_user_status ON public.wallet_topups USING btree (user_id, status);
CREATE INDEX idx_topups_receipt_id ON public.wallet_topups USING btree (receipt_id);
CREATE INDEX idx_topups_txref_norm ON public.wallet_topups USING btree (normalize_tx_ref(transaction_reference));
CREATE INDEX idx_wallet_topups_payment_method_id ON public.wallet_topups USING btree (payment_method_id);
CREATE INDEX wallet_transactions_user_idx ON public.wallet_transactions USING btree (user_id, created_at DESC);
CREATE INDEX wallet_transactions_ref_idx ON public.wallet_transactions USING btree (reference_id);
CREATE INDEX idx_store_settings_updated_by ON public.store_settings USING btree (updated_by);
CREATE INDEX idx_referral_payouts_milestone_id ON public.referral_milestone_payouts USING btree (milestone_id);
CREATE INDEX idx_notif_user_unread ON public.notifications USING btree (user_id) WHERE (is_read = false);
CREATE UNIQUE INDEX uq_payment_receipts_tx_norm ON public.payment_receipts USING btree (tx_ref_norm);
CREATE UNIQUE INDEX uq_payment_receipts_hash ON public.payment_receipts USING btree (receipt_hash);
CREATE INDEX idx_payment_receipts_user ON public.payment_receipts USING btree (user_id, created_at DESC);
CREATE UNIQUE INDEX payment_receipts_tx_ref_norm_uniq ON public.payment_receipts USING btree (tx_ref_norm) WHERE ((tx_ref_norm IS NOT NULL) AND (tx_ref_norm <> ''::text));
CREATE INDEX idx_payment_receipts_parent ON public.payment_receipts USING btree (parent_receipt_id);
CREATE INDEX payment_codes_status_idx ON public.payment_codes USING btree (status);
CREATE INDEX idx_payment_codes_status ON public.payment_codes USING btree (status, created_at DESC);
CREATE INDEX idx_payment_codes_user ON public.payment_codes USING btree (user_id);
CREATE UNIQUE INDEX uq_payment_codes_code ON public.payment_codes USING btree (upper(btrim(code)));
CREATE INDEX idx_payment_codes_created_by ON public.payment_codes USING btree (created_by);
CREATE INDEX idx_payment_codes_order_id ON public.payment_codes USING btree (order_id);
CREATE INDEX idx_payment_codes_used_by ON public.payment_codes USING btree (used_by);
CREATE INDEX idx_coupon_redemptions_user_id ON public.coupon_redemptions USING btree (user_id);
CREATE UNIQUE INDEX uq_subcategories_category_name_ci ON public.subcategories USING btree (category_id, lower(name));
CREATE INDEX idx_subcategories_category_active_order ON public.subcategories USING btree (category_id, is_active, display_order, name);
CREATE INDEX idx_orders_status ON public.orders USING btree (status);
CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id);
CREATE INDEX idx_orders_created_at ON public.orders USING btree (created_at DESC);
CREATE INDEX idx_orders_receipt_hash ON public.orders USING btree (receipt_hash) WHERE (receipt_hash IS NOT NULL);
CREATE INDEX idx_orders_ocr_status ON public.orders USING btree (ocr_status);
CREATE INDEX idx_orders_coupon_id ON public.orders USING btree (coupon_id) WHERE (coupon_id IS NOT NULL);
CREATE INDEX idx_orders_receipt_id ON public.orders USING btree (receipt_id);
CREATE INDEX idx_orders_txref_norm ON public.orders USING btree (normalize_tx_ref(transaction_reference));
CREATE UNIQUE INDEX orders_order_code_key ON public.orders USING btree (order_code);
CREATE INDEX idx_orders_needs_admin_check ON public.orders USING btree (created_at DESC) WHERE (ocr_status = 'needs_admin_check'::text);
CREATE INDEX idx_orders_completed_product ON public.orders USING btree (product_id, created_at DESC) WHERE (status = 'completed'::text);
CREATE INDEX idx_orders_payment_method_id ON public.orders USING btree (payment_method_id);
CREATE INDEX orders_payment_code_id_idx ON public.orders USING btree (payment_code_id);
CREATE INDEX banners_public_idx ON public.banners USING btree (is_active, sort_order);
CREATE INDEX banners_sort_idx ON public.banners USING btree (sort_order, created_at);
CREATE INDEX store_sections_active_order_idx ON public.store_sections USING btree (is_active, display_order, name);
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();
CREATE TRIGGER trg_protect_profile_columns BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_columns();
CREATE TRIGGER trg_award_loyalty_points AFTER UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION award_loyalty_points();
CREATE TRIGGER trg_store_settings_set_updated_at BEFORE UPDATE ON store_settings FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER trg_admin_permissions_set_updated_at BEFORE UPDATE ON admin_permissions FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER trg_protect_profile_fields BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_fields();
CREATE TRIGGER trg_protect_profile_insert BEFORE INSERT ON profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_insert();
CREATE TRIGGER trg_protect_order_fields BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION protect_order_fields();
CREATE TRIGGER trg_protect_notification_fields BEFORE UPDATE ON notifications FOR EACH ROW EXECUTE FUNCTION protect_notification_fields();
CREATE TRIGGER trg_verify_order_price BEFORE INSERT ON orders FOR EACH ROW EXECUTE FUNCTION verify_order_price_before_insert();
CREATE TRIGGER trg_set_order_code BEFORE INSERT ON orders FOR EACH ROW EXECUTE FUNCTION set_order_code();
CREATE TRIGGER trg_payment_codes_updated_at BEFORE UPDATE ON payment_codes FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER trg_apply_referral_signup_metadata BEFORE INSERT ON profiles FOR EACH ROW EXECUTE FUNCTION apply_referral_signup_metadata();
CREATE TRIGGER trg_subcategories_updated_at BEFORE UPDATE ON subcategories FOR EACH ROW EXECUTE FUNCTION touch_subcategories_updated_at();
CREATE TRIGGER store_sections_updated_at BEFORE UPDATE ON store_sections FOR EACH ROW EXECUTE FUNCTION set_store_sections_updated_at();
CREATE CONSTRAINT TRIGGER trg_assert_wallet_ledger AFTER INSERT OR UPDATE ON wallets DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION assert_wallet_ledger_entry();
CREATE TRIGGER trg_protect_topup_insert BEFORE INSERT ON wallet_topups FOR EACH ROW EXECUTE FUNCTION protect_topup_insert();
CREATE CONSTRAINT TRIGGER trg_link_order_payment_code AFTER INSERT ON orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION link_order_payment_code();
CREATE TRIGGER trg_validate_receipt_path BEFORE INSERT OR UPDATE OF receipt_path, user_id ON payment_receipts FOR EACH ROW EXECUTE FUNCTION validate_receipt_path();
CREATE TRIGGER trg_derive_receipt_url_orders BEFORE INSERT OR UPDATE OF receipt_id, receipt_url ON orders FOR EACH ROW EXECUTE FUNCTION derive_receipt_url_from_receipt();
CREATE TRIGGER trg_derive_receipt_url_topups BEFORE INSERT OR UPDATE OF receipt_id, receipt_url ON wallet_topups FOR EACH ROW EXECUTE FUNCTION derive_receipt_url_from_receipt();
CREATE TRIGGER banners_touch BEFORE UPDATE ON banners FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER trg_enforce_coupon_code_strength BEFORE INSERT OR UPDATE OF code ON coupons FOR EACH ROW EXECUTE FUNCTION enforce_coupon_code_strength();
CREATE POLICY "admin_audit_insert" ON "public"."admin_audit_logs" FOR INSERT TO authenticated WITH CHECK ((is_admin() AND (admin_id = ( SELECT auth.uid() AS uid))));
CREATE POLICY "admin_audit_select" ON "public"."admin_audit_logs" FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "admin_perms_select" ON "public"."admin_permissions" FOR SELECT TO authenticated USING (((profile_id = ( SELECT auth.uid() AS uid)) OR is_super_admin()));
CREATE POLICY "admin_perms_super_admin" ON "public"."admin_permissions" FOR ALL TO authenticated USING ((is_super_admin() AND (profile_id <> ( SELECT auth.uid() AS uid)))) WITH CHECK ((is_super_admin() AND (profile_id <> ( SELECT auth.uid() AS uid))));
CREATE POLICY "audit_logs_admin_insert" ON "public"."audit_logs" FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "audit_logs_select_admin" ON "public"."audit_logs" FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "banners_admin_read" ON "public"."banners" FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "banners_public_read" ON "public"."banners" FOR SELECT TO anon,authenticated USING (((status = 'published'::text) AND is_active AND ((starts_at IS NULL) OR (starts_at <= now())) AND ((ends_at IS NULL) OR (ends_at >= now()))));
CREATE POLICY "categories_admin" ON "public"."categories" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_products'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_products'::text)));
CREATE POLICY "categories_select_active_anon" ON "public"."categories" FOR SELECT TO anon USING ((is_active = true));
CREATE POLICY "categories_select_active_authenticated" ON "public"."categories" FOR SELECT TO authenticated USING (((is_active = true) OR is_admin()));
CREATE POLICY "coupon_redemptions_admin" ON "public"."coupon_redemptions" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "coupon_redemptions_select_own" ON "public"."coupon_redemptions" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "coupons_admin" ON "public"."coupons" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_coupons'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_coupons'::text)));
CREATE POLICY "coupons_select_admin_only" ON "public"."coupons" FOR SELECT TO authenticated USING ((is_admin() AND has_admin_permission('manage_coupons'::text)));
CREATE POLICY "gift_cards_admin" ON "public"."gift_cards" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_gift_cards'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_gift_cards'::text)));
CREATE POLICY "gift_cards_select_own" ON "public"."gift_cards" FOR SELECT TO authenticated USING (((redeemed_by = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "notifications_admin_all" ON "public"."notifications" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "notifications_select_own" ON "public"."notifications" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "notifications_update_own" ON "public"."notifications" FOR UPDATE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "orders_admin_all" ON "public"."orders" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "orders_cancel_own" ON "public"."orders" FOR UPDATE TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending_review'::text))) WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (status = 'cancelled'::text)));
CREATE POLICY "orders_insert_own" ON "public"."orders" FOR INSERT TO authenticated WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (NOT is_banned()) AND (status = ANY (ARRAY['pending_review'::text, 'in_progress'::text])) AND (COALESCE(referral_commission_paid, false) = false)));
CREATE POLICY "orders_select" ON "public"."orders" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "payment_codes_admin_manage" ON "public"."payment_codes" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_settings'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_settings'::text)));
CREATE POLICY "payment_codes_select_own" ON "public"."payment_codes" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR (used_by = ( SELECT auth.uid() AS uid))));
CREATE POLICY "payment_methods_admin" ON "public"."payment_methods" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_settings'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_settings'::text)));
CREATE POLICY "payment_methods_select_active_anon" ON "public"."payment_methods" FOR SELECT TO anon USING ((is_active = true));
CREATE POLICY "payment_methods_select_authenticated" ON "public"."payment_methods" FOR SELECT TO authenticated USING (((is_active = true) OR (is_admin() AND has_admin_permission('manage_settings'::text))));
CREATE POLICY "receipts_admin_all" ON "public"."payment_receipts" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "receipts_select_own" ON "public"."payment_receipts" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "products_admin_all" ON "public"."products" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_products'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_products'::text)));
CREATE POLICY "products_select_active_anon" ON "public"."products" FOR SELECT TO anon USING ((is_active = true));
CREATE POLICY "products_select_active_authenticated" ON "public"."products" FOR SELECT TO authenticated USING (((is_active = true) OR is_admin()));
CREATE POLICY "profiles_admin_all" ON "public"."profiles" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "profiles_insert_own" ON "public"."profiles" FOR INSERT TO authenticated WITH CHECK ((id = ( SELECT auth.uid() AS uid)));
CREATE POLICY "profiles_select_own" ON "public"."profiles" FOR SELECT TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "profiles_update_own" ON "public"."profiles" FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK (profile_guard_fields_unchanged(id, role, is_banned, referred_by, referral_code, referral_short_code, referral_rewarded, referral_discount_used, milestone10_paid, milestone25_paid, loyalty_points));
CREATE POLICY "fraud_attempts_admin_select" ON "public"."receipt_fraud_attempts" FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "referral_payouts_admin" ON "public"."referral_milestone_payouts" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "referral_payouts_select" ON "public"."referral_milestone_payouts" FOR SELECT TO authenticated USING (((referrer_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "referral_milestones_admin" ON "public"."referral_milestones" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_settings'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_settings'::text)));
CREATE POLICY "referral_milestones_select" ON "public"."referral_milestones" FOR SELECT TO authenticated USING (((is_active = true) OR is_admin()));
CREATE POLICY "settings_admin" ON "public"."settings" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_settings'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_settings'::text)));
CREATE POLICY "settings_select" ON "public"."settings" FOR SELECT TO anon,authenticated USING ((key = ANY (ARRAY['usd_to_sdg_rate'::text, 'profit_margin_percent'::text, 'referral_signup_discount_percent'::text, 'whatsapp_number'::text, 'banner_mobile_ratio'::text, 'banner_autoplay'::text, 'banner_interval'::text, 'banner_effect'::text, 'offers_use_flag'::text, 'catalog_icons_flag'::text, 'home_highlights_flag'::text])));
CREATE POLICY "store_sections_admin_delete" ON "public"."store_sections" FOR DELETE TO authenticated USING ((is_admin() AND has_admin_permission('manage_products'::text)));
CREATE POLICY "store_sections_admin_insert" ON "public"."store_sections" FOR INSERT TO authenticated WITH CHECK ((is_admin() AND has_admin_permission('manage_products'::text)));
CREATE POLICY "store_sections_admin_update" ON "public"."store_sections" FOR UPDATE TO authenticated USING ((is_admin() AND has_admin_permission('manage_products'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_products'::text)));
CREATE POLICY "store_sections_select_active_anon" ON "public"."store_sections" FOR SELECT TO anon USING ((is_active = true));
CREATE POLICY "store_sections_select_authenticated" ON "public"."store_sections" FOR SELECT TO authenticated USING (((is_active = true) OR (is_admin() AND has_admin_permission('manage_products'::text))));
CREATE POLICY "store_settings_admin" ON "public"."store_settings" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "store_settings_select" ON "public"."store_settings" FOR SELECT TO anon,authenticated USING (true);
CREATE POLICY "subcategories_admin_manage" ON "public"."subcategories" FOR ALL TO authenticated USING ((is_admin() AND has_admin_permission('manage_products'::text))) WITH CHECK ((is_admin() AND has_admin_permission('manage_products'::text)));
CREATE POLICY "subcategories_select_active_anon" ON "public"."subcategories" FOR SELECT TO anon USING ((is_active = true));
CREATE POLICY "subcategories_select_authenticated" ON "public"."subcategories" FOR SELECT TO authenticated USING (((is_active = true) OR is_admin()));
CREATE POLICY "topups_admin_all" ON "public"."wallet_topups" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "topups_insert_own" ON "public"."wallet_topups" FOR INSERT TO authenticated WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (NOT is_banned()) AND (status = 'pending'::text) AND (amount > (0)::numeric) AND (amount <= (10000000)::numeric) AND (reviewed_at IS NULL) AND (COALESCE(amount_verified, false) = false)));
CREATE POLICY "topups_select_own" ON "public"."wallet_topups" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "wallet_tx_select_own" ON "public"."wallet_transactions" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "wallets_admin_all" ON "public"."wallets" FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "wallets_select_own" ON "public"."wallets" FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR is_admin()));
CREATE POLICY "avatars_owner_delete" ON "storage"."objects" FOR DELETE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY "avatars_owner_insert" ON "storage"."objects" FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY "avatars_owner_update" ON "storage"."objects" FOR UPDATE TO authenticated USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))) WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY "avatars_public_read" ON "storage"."objects" FOR SELECT TO public USING ((bucket_id = 'avatars'::text));
CREATE POLICY "banners_admin_delete" ON "storage"."objects" FOR DELETE TO authenticated USING (((bucket_id = 'banners'::text) AND is_admin()));
CREATE POLICY "banners_admin_update" ON "storage"."objects" FOR UPDATE TO authenticated USING (((bucket_id = 'banners'::text) AND is_admin())) WITH CHECK (((bucket_id = 'banners'::text) AND is_admin()));
CREATE POLICY "banners_admin_write" ON "storage"."objects" FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'banners'::text) AND is_admin()));
CREATE POLICY "banners_public_read_objects" ON "storage"."objects" FOR SELECT TO anon,authenticated USING ((bucket_id = 'banners'::text));
CREATE POLICY "category_icons_admin_delete" ON "storage"."objects" FOR DELETE TO authenticated USING (((bucket_id = 'category-icons'::text) AND is_admin()));
CREATE POLICY "category_icons_admin_update" ON "storage"."objects" FOR UPDATE TO authenticated USING (((bucket_id = 'category-icons'::text) AND is_admin())) WITH CHECK (((bucket_id = 'category-icons'::text) AND is_admin()));
CREATE POLICY "category_icons_admin_write" ON "storage"."objects" FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'category-icons'::text) AND is_admin()));
CREATE POLICY "category_icons_public_read" ON "storage"."objects" FOR SELECT TO anon,authenticated USING ((bucket_id = 'category-icons'::text));
CREATE POLICY "product_images_admin_delete" ON "storage"."objects" FOR DELETE TO authenticated USING (((bucket_id = 'product-images'::text) AND is_admin()));
CREATE POLICY "product_images_admin_update" ON "storage"."objects" FOR UPDATE TO authenticated USING (((bucket_id = 'product-images'::text) AND is_admin())) WITH CHECK (((bucket_id = 'product-images'::text) AND is_admin()));
CREATE POLICY "product_images_admin_write" ON "storage"."objects" FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'product-images'::text) AND is_admin()));
CREATE POLICY "product_images_public_read" ON "storage"."objects" FOR SELECT TO anon,authenticated USING ((bucket_id = 'product-images'::text));
CREATE POLICY "receipts_admin_manage" ON "storage"."objects" FOR DELETE TO authenticated USING (((bucket_id = 'receipts'::text) AND is_admin()));
CREATE POLICY "receipts_admin_read" ON "storage"."objects" FOR SELECT TO authenticated USING (((bucket_id = 'receipts'::text) AND is_admin()));
CREATE POLICY "receipts_read_own" ON "storage"."objects" FOR SELECT TO authenticated USING (((bucket_id = 'receipts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
CREATE POLICY "receipts_upload_own" ON "storage"."objects" FOR INSERT TO authenticated WITH CHECK (((bucket_id = 'receipts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
ALTER TABLE public."coupons" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."coupons" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."coupons" TO authenticated;
ALTER TABLE public."gift_cards" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."gift_cards" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."gift_cards" TO authenticated;
ALTER TABLE public."receipt_scan_results" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."receipt_scan_results" TO service_role;
ALTER TABLE public."categories" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."categories" TO service_role;
GRANT SELECT ON public."categories" TO anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."categories" TO authenticated;
ALTER TABLE public."products" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."products" TO service_role;
GRANT SELECT ON public."products" TO anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."products" TO authenticated;
ALTER TABLE public."receipt_fraud_attempts" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."receipt_fraud_attempts" TO service_role;
GRANT SELECT ON public."receipt_fraud_attempts" TO authenticated;
ALTER TABLE public."admin_permissions" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."admin_permissions" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."admin_permissions" TO authenticated;
ALTER TABLE public."profiles" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."profiles" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."profiles" TO authenticated;
ALTER TABLE public."payment_methods" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."payment_methods" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."payment_methods" TO authenticated;
ALTER TABLE public."settings" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."settings" TO service_role;
GRANT SELECT ON public."settings" TO anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."settings" TO authenticated;
ALTER TABLE public."admin_audit_logs" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."admin_audit_logs" TO service_role;
GRANT SELECT,INSERT ON public."admin_audit_logs" TO authenticated;
ALTER TABLE public."audit_logs" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."audit_logs" TO service_role;
GRANT SELECT,INSERT ON public."audit_logs" TO authenticated;
ALTER TABLE public."wallet_topups" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."wallet_topups" TO service_role;
GRANT SELECT ON public."wallet_topups" TO authenticated;
ALTER TABLE public."wallets" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."wallets" TO service_role;
GRANT SELECT ON public."wallets" TO authenticated;
ALTER TABLE public."wallet_transactions" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."wallet_transactions" TO service_role;
GRANT SELECT ON public."wallet_transactions" TO authenticated;
ALTER TABLE public."store_settings" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."store_settings" TO service_role;
GRANT SELECT ON public."store_settings" TO anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."store_settings" TO authenticated;
ALTER TABLE public."referral_milestones" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."referral_milestones" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."referral_milestones" TO authenticated;
ALTER TABLE public."referral_milestone_payouts" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."referral_milestone_payouts" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."referral_milestone_payouts" TO authenticated;
ALTER TABLE public."notifications" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."notifications" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."notifications" TO authenticated;
ALTER TABLE public."payment_receipts" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."payment_receipts" TO service_role;
GRANT SELECT ON public."payment_receipts" TO authenticated;
ALTER TABLE public."payment_codes" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."payment_codes" TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."payment_codes" TO authenticated;
ALTER TABLE public."coupon_redemptions" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."coupon_redemptions" TO service_role;
GRANT SELECT ON public."coupon_redemptions" TO authenticated;
ALTER TABLE public."subcategories" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."subcategories" TO service_role;
GRANT SELECT ON public."subcategories" TO anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."subcategories" TO authenticated;
ALTER TABLE public."orders" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."orders" TO service_role;
GRANT SELECT ON public."orders" TO authenticated;
ALTER TABLE public."banners" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."banners" TO service_role;
GRANT SELECT ON public."banners" TO anon;
GRANT SELECT ON public."banners" TO authenticated;
ALTER TABLE public."store_sections" ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public."store_sections" TO service_role;
GRANT SELECT ON public."store_sections" TO anon;
GRANT SELECT,INSERT,UPDATE,DELETE ON public."store_sections" TO authenticated;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON FUNCTION public.admin_cancel_payment_code(p_code_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cancel_payment_code(p_code_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.admin_confirm_topup(p_topup_id uuid, p_override_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_topup(p_topup_id uuid, p_override_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_topup(p_topup_id uuid, p_override_reason text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_copy_banner(p_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_copy_banner(p_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_copy_banner(p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.admin_create_payment_code(p_amount numeric, p_user_id uuid, p_note text, p_expires_at timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_payment_code(p_amount numeric, p_user_id uuid, p_note text, p_expires_at timestamp with time zone) TO service_role;
REVOKE ALL ON FUNCTION public.admin_delete_banner(p_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_banner(p_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_banner(p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.admin_refund_wallet(p_order_id uuid, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_refund_wallet(p_order_id uuid, p_reason text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_reject_order(p_order_id uuid, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_order(p_order_id uuid, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_order(p_order_id uuid, p_reason text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_reject_topup(p_topup_id uuid, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reject_topup(p_topup_id uuid, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_topup(p_topup_id uuid, p_reason text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_release_receipt(p_receipt_id uuid, p_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_release_receipt(p_receipt_id uuid, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_release_receipt(p_receipt_id uuid, p_reason text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_reorder_banner(p_id uuid, p_direction text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reorder_banner(p_id uuid, p_direction text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reorder_banner(p_id uuid, p_direction text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_reorder_banners(p_order jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reorder_banners(p_order jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reorder_banners(p_order jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.admin_save_banner(p_id uuid, p_payload jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_save_banner(p_id uuid, p_payload jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_save_banner(p_id uuid, p_payload jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_banner_active(p_id uuid, p_active boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_banner_active(p_id uuid, p_active boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_banner_active(p_id uuid, p_active boolean) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_banner_status(p_id uuid, p_status text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_banner_status(p_id uuid, p_status text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_banner_status(p_id uuid, p_status text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_category_icon(p_id uuid, p_mode text, p_key text, p_image text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_category_icon(p_id uuid, p_mode text, p_key text, p_image text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_category_icon(p_id uuid, p_mode text, p_key text, p_image text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_customer_banned(p_profile_id uuid, p_banned boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_customer_banned(p_profile_id uuid, p_banned boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_customer_banned(p_profile_id uuid, p_banned boolean) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_section_icon(p_id uuid, p_mode text, p_key text, p_image text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_section_icon(p_id uuid, p_mode text, p_key text, p_image text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_section_icon(p_id uuid, p_mode text, p_key text, p_image text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_set_staff_permissions(p_profile_id uuid, p_role text, p_permissions jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_staff_permissions(p_profile_id uuid, p_role text, p_permissions jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_staff_permissions(p_profile_id uuid, p_role text, p_permissions jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.admin_update_order_status(p_order_id uuid, p_status text, p_override_reason text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_order_status(p_order_id uuid, p_status text, p_override_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_order_status(p_order_id uuid, p_status text, p_override_reason text) TO service_role;
REVOKE ALL ON FUNCTION public.append_admin_audit_log(p_action text, p_target_table text, p_target_id text, p_details jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.append_admin_audit_log(p_action text, p_target_table text, p_target_id text, p_details jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.append_admin_audit_log(p_action text, p_target_table text, p_target_id text, p_details jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.apply_referral_signup_metadata() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_referral_signup_metadata() TO service_role;
REVOKE ALL ON FUNCTION public.assert_wallet_ledger_entry() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_wallet_ledger_entry() TO service_role;
REVOKE ALL ON FUNCTION public.attach_secondary_receipt(p_parent_tx_ref text, p_order_id uuid, p_receipt jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.attach_secondary_receipt(p_parent_tx_ref text, p_order_id uuid, p_receipt jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attach_secondary_receipt(p_parent_tx_ref text, p_order_id uuid, p_receipt jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.award_loyalty_points() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.award_loyalty_points() TO service_role;
REVOKE ALL ON FUNCTION public.banners_validate(p_payload jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.banners_validate(p_payload jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.banners_validate_image_url(p_url text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.banners_validate_image_url(p_url text) TO service_role;
REVOKE ALL ON FUNCTION public.bootstrap_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bootstrap_super_admin() TO service_role;
REVOKE ALL ON FUNCTION public.cancel_my_order(p_order_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_my_order(p_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_my_order(p_order_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.check_tx_ref_available(p_tx_ref text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(p_tx_ref text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_tx_ref_available(p_tx_ref text) TO service_role;
REVOKE ALL ON FUNCTION public.claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_payment_method_id uuid, p_amount_expected numeric, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_payment_method_id uuid, p_amount_expected numeric, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_payment_receipt(p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_payment_method_id uuid, p_amount_expected numeric, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.consume_chat_rate_limit(p_rate_key text, p_limit integer, p_window_seconds integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_chat_rate_limit(p_rate_key text, p_limit integer, p_window_seconds integer) TO service_role;
REVOKE ALL ON FUNCTION public.create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_bank_orders_bulk(p_items jsonb, p_receipt jsonb, p_coupon_code text) TO service_role;
REVOKE ALL ON FUNCTION public.create_code_orders_bulk(p_items jsonb, p_code text, p_coupon_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_code_orders_bulk(p_items jsonb, p_code text, p_coupon_code text) TO service_role;
REVOKE ALL ON FUNCTION public.create_wallet_order(p_product_id uuid, p_field_values jsonb, p_field_labels jsonb, p_coupon_code text, p_selected_option_id text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_wallet_order(p_product_id uuid, p_field_values jsonb, p_field_labels jsonb, p_coupon_code text, p_selected_option_id text) TO service_role;
REVOKE ALL ON FUNCTION public.create_wallet_orders_bulk(p_items jsonb, p_coupon_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_wallet_orders_bulk(p_items jsonb, p_coupon_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_orders_bulk(p_items jsonb, p_coupon_code text) TO service_role;
REVOKE ALL ON FUNCTION public.create_wallet_topup_from_receipt(p_amount numeric, p_payment_method_id uuid, p_receipt_url text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_wallet_topup_from_receipt(p_amount numeric, p_payment_method_id uuid, p_receipt_url text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_topup_from_receipt(p_amount numeric, p_payment_method_id uuid, p_receipt_url text, p_tx_ref text, p_receipt_hash text, p_receipt_path text, p_provider text, p_amount_detected numeric, p_tx_ref_ocr text, p_ocr_status text, p_ocr_confidence numeric, p_risk_flags text[], p_ocr_data jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.derive_receipt_url_from_receipt() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.derive_receipt_url_from_receipt() TO service_role;
REVOKE ALL ON FUNCTION public.enforce_coupon_code_strength() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enforce_coupon_code_strength() TO service_role;
REVOKE ALL ON FUNCTION public.generate_order_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_order_code() TO service_role;
REVOKE ALL ON FUNCTION public.generate_referral_short_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.generate_referral_short_code() TO service_role;
REVOKE ALL ON FUNCTION public.get_admin_notification_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_notification_counts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_notification_counts() TO service_role;
REVOKE ALL ON FUNCTION public.get_banners_public() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_banners_public() TO anon;
GRANT EXECUTE ON FUNCTION public.get_banners_public() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_banners_public() TO service_role;
REVOKE ALL ON FUNCTION public.get_my_admin_context() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_admin_context() TO service_role;
REVOKE ALL ON FUNCTION public.get_top_ordered_products(p_limit integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_top_ordered_products(p_limit integer) TO anon;
GRANT EXECUTE ON FUNCTION public.get_top_ordered_products(p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_top_ordered_products(p_limit integer) TO service_role;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
REVOKE ALL ON FUNCTION public.has_admin_permission(permission_key text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_admin_permission(permission_key text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_admin_permission(permission_key text) TO service_role;
REVOKE ALL ON FUNCTION public.icon_fields_validate(p_mode text, p_key text, p_image text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.icon_fields_validate(p_mode text, p_key text, p_image text) TO service_role;
REVOKE ALL ON FUNCTION public.icon_image_url_ok(p_url text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.icon_image_url_ok(p_url text) TO service_role;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO service_role;
REVOKE ALL ON FUNCTION public.is_banned() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_banned() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_banned() TO service_role;
REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO service_role;
REVOKE ALL ON FUNCTION public.link_order_payment_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.link_order_payment_code() TO service_role;
REVOKE ALL ON FUNCTION public.log_receipt_fraud_attempt(p_entered_reference text, p_reason text, p_provider text, p_ocr_excerpt text, p_order_amount numeric, p_metadata jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_receipt_fraud_attempt(p_entered_reference text, p_reason text, p_provider text, p_ocr_excerpt text, p_order_amount numeric, p_metadata jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_receipt_fraud_attempt(p_entered_reference text, p_reason text, p_provider text, p_ocr_excerpt text, p_order_amount numeric, p_metadata jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.normalize_tx_ref(p_ref text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_tx_ref(p_ref text) TO service_role;
REVOKE ALL ON FUNCTION public.process_referral_commission(p_user_id uuid, p_order_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_referral_commission(p_user_id uuid, p_order_id uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_referral_commission(p_user_id uuid, p_order_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.profile_guard_fields_unchanged(p_id uuid, p_role text, p_is_banned boolean, p_referred_by uuid, p_referral_code text, p_referral_short_code text, p_referral_rewarded boolean, p_referral_discount_used boolean, p_milestone10_paid boolean, p_milestone25_paid boolean, p_loyalty_points integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.profile_guard_fields_unchanged(p_id uuid, p_role text, p_is_banned boolean, p_referred_by uuid, p_referral_code text, p_referral_short_code text, p_referral_rewarded boolean, p_referral_discount_used boolean, p_milestone10_paid boolean, p_milestone25_paid boolean, p_loyalty_points integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.profile_guard_fields_unchanged(p_id uuid, p_role text, p_is_banned boolean, p_referred_by uuid, p_referral_code text, p_referral_short_code text, p_referral_rewarded boolean, p_referral_discount_used boolean, p_milestone10_paid boolean, p_milestone25_paid boolean, p_loyalty_points integer) TO service_role;
REVOKE ALL ON FUNCTION public.protect_notification_fields() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.protect_notification_fields() TO service_role;
REVOKE ALL ON FUNCTION public.protect_order_fields() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.protect_order_fields() TO service_role;
REVOKE ALL ON FUNCTION public.protect_profile_columns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.protect_profile_columns() TO service_role;
REVOKE ALL ON FUNCTION public.protect_profile_fields() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.protect_profile_fields() TO service_role;
REVOKE ALL ON FUNCTION public.protect_profile_insert() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.protect_profile_insert() TO service_role;
REVOKE ALL ON FUNCTION public.protect_topup_insert() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.protect_topup_insert() TO service_role;
REVOKE ALL ON FUNCTION public.redeem_gift_card(p_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_gift_card(p_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_gift_card(p_code text) TO service_role;
REVOKE ALL ON FUNCTION public.redeem_loyalty_points(p_points integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_loyalty_points(p_points integer) TO service_role;
REVOKE ALL ON FUNCTION public.redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_payment_code_order(p_code text, p_items jsonb, p_coupon_code text) TO service_role;
REVOKE ALL ON FUNCTION public.report_fraud_alert(p_details jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.report_fraud_alert(p_details jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_fraud_alert(p_details jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO service_role;
REVOKE ALL ON FUNCTION public.set_order_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_order_code() TO service_role;
REVOKE ALL ON FUNCTION public.set_row_updated_at() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_row_updated_at() TO service_role;
REVOKE ALL ON FUNCTION public.set_store_exchange_rate(p_rate numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_store_exchange_rate(p_rate numeric) TO service_role;
REVOKE ALL ON FUNCTION public.set_store_maintenance(p_enabled boolean, p_message text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_store_maintenance(p_enabled boolean, p_message text) TO service_role;
REVOKE ALL ON FUNCTION public.set_store_sections_updated_at() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_store_sections_updated_at() TO service_role;
REVOKE ALL ON FUNCTION public.touch_subcategories_updated_at() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.touch_subcategories_updated_at() TO service_role;
REVOKE ALL ON FUNCTION public.upsert_admin_permissions(p_profile_id uuid, p_is_super_admin boolean, p_can_manage_orders boolean, p_can_manage_wallets boolean, p_can_manage_products boolean, p_can_manage_settings boolean, p_can_manage_maintenance boolean, p_can_manage_admins boolean, p_can_manage_coupons boolean, p_can_manage_gift_cards boolean, p_can_view_audit_logs boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_admin_permissions(p_profile_id uuid, p_is_super_admin boolean, p_can_manage_orders boolean, p_can_manage_wallets boolean, p_can_manage_products boolean, p_can_manage_settings boolean, p_can_manage_maintenance boolean, p_can_manage_admins boolean, p_can_manage_coupons boolean, p_can_manage_gift_cards boolean, p_can_view_audit_logs boolean) TO service_role;
REVOKE ALL ON FUNCTION public.use_coupon_atomic(p_code text, p_order_total numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(p_code text, p_order_total numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.use_coupon_atomic(p_code text, p_order_total numeric) TO service_role;
REVOKE ALL ON FUNCTION public.validate_coupon(p_code text, p_order_total numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_coupon(p_code text, p_order_total numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_coupon(p_code text, p_order_total numeric) TO service_role;
REVOKE ALL ON FUNCTION public.validate_payment_code(p_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_code(p_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_payment_code(p_code text) TO service_role;
REVOKE ALL ON FUNCTION public.validate_receipt_path() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_receipt_path() TO service_role;
REVOKE ALL ON FUNCTION public.validate_referral_short_code(p_code text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_referral_short_code(p_code text) TO anon;
GRANT EXECUTE ON FUNCTION public.validate_referral_short_code(p_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_referral_short_code(p_code text) TO service_role;
REVOKE ALL ON FUNCTION public.verify_order_price_before_insert() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_order_price_before_insert() TO service_role;
REVOKE ALL ON FUNCTION public.verify_privilege_model() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_privilege_model() TO service_role;
