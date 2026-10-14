#!/usr/bin/env bash
# Runs the money-flow probes: real calls to the order/wallet/payment RPCs on the
# live project, each one inside its own transaction that ends in ROLLBACK, so no
# row is ever changed. This is the functional counterpart of the static checks in
# db/tests/security_invariants.sql (which only inspect definitions and grants).
#
#   live   SUPABASE_ACCESS_TOKEN=<token> bash db/tests/run_money_flow.sh
#          (or the token file: ~/.raizey-audit/live_rw)
#   local  MEEM_LOCAL_DSN="postgresql://..." bash db/tests/run_money_flow.sh
#          (started by db/tests/local_sql_suite.sh)
#
# Probe index and what each one proves: db/tests/money_flow_live.sql
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=probe_lib.sh
. "$HERE/probe_lib.sh"

if [ -z "${MEEM_LOCAL_DSN:-}" ] && [ -z "$(probe_token)" ]; then
  echo "no access token available"; exit 2
fi

# These probes are only meaningful where the money RPCs exist (the live project
# and any database that already has the 2026-10-08 hardening round). Refusing to
# run is deliberate: a missing function would otherwise make the "must be
# rejected" probes pass for the wrong reason.
MONEY_RPCS="admin_update_order_status cancel_my_order admin_refund_wallet
admin_reject_order admin_create_payment_code redeem_payment_code_order
create_wallet_order create_bank_orders_bulk create_wallet_topup_from_receipt
claim_payment_receipt"
missing=""
for fn in $MONEY_RPCS; do
  found="$(_probe_run "select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname = '$fn'")"
  [ "$found" = "0" ] && missing="$missing $fn"
done
if [ -n "$missing" ]; then
  echo "this database does not have the money RPCs:$missing"
  echo "the money-flow suite replays the 2026-10-08 hardening schema — run it against the live project"
  exit 3
fi

# ── identities and fixtures (read-only, as the owner role) ───────────────────
ADMIN_UUID="$(_probe_run "select id::text from public.profiles where role='admin' and coalesce(is_banned,false)=false order by created_at, id limit 1")"
CUSTOMER_UUID="$(_probe_run "select id::text from public.profiles where role='customer' and coalesce(is_banned,false)=false order by created_at, id limit 1")"
OTHER_UUID="$(_probe_run "select id::text from public.profiles where role='customer' and coalesce(is_banned,false)=false order by created_at desc, id limit 1")"
PRODUCT_ID="$(_probe_run "select id::text from public.products where is_active order by created_at, id limit 1")"
USED_CODE="$(_probe_run "select code::text from public.payment_codes where status='used' order by created_at limit 1")"
WALLET_USER="$(_probe_run "select user_id::text from public.wallets order by user_id limit 1")"

is_uuid() {
  case "$1" in
    [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*-[0-9a-fA-F]*) return 0 ;;
    *) return 1 ;;
  esac
}
CUST_CLAIMS="{\"role\":\"authenticated\",\"sub\":\"$CUSTOMER_UUID\"}"
OTHER_CLAIMS="{\"role\":\"authenticated\",\"sub\":\"$OTHER_UUID\"}"
ADMIN_CLAIMS="{\"role\":\"authenticated\",\"sub\":\"$ADMIN_UUID\"}"
# the message a probe caught (set_config survives to the next statement in the txn)
MSG_TAIL="perform set_config('probe.msg', coalesce(m,''), true);
  end \$\$;
  select current_setting('probe.msg', true) as v;
  rollback;"

# ---------------------------------------------------------------- 1. anon is out
probe "1 anon cannot create a wallet order" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select public.create_wallet_order('$PRODUCT_ID'::uuid) as v; rollback;"
probe "2 anon cannot claim a receipt" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select public.claim_payment_receipt('order','probe-ref',repeat('a',64)) as v; rollback;"
probe "3 anon cannot cancel an order" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select public.cancel_my_order((select id from public.orders limit 1)) as v; rollback;"
probe "4 anon cannot redeem a payment code" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select public.redeem_payment_code_order('PROBE-CODE','[{\"product_id\":\"$PRODUCT_ID\",\"quantity\":1}]'::jsonb) as v; rollback;"
probe "5 anon cannot create a bank order" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select public.create_bank_orders_bulk('[{\"product_id\":\"$PRODUCT_ID\",\"quantity\":1}]'::jsonb, '{}'::jsonb) as v; rollback;"
probe "6 anon cannot create a wallet top-up" ERROR \
 "begin; set local role anon; set local request.jwt.claims='{\"role\":\"anon\"}';
  select public.create_wallet_topup_from_receipt(1000, null, 'probe.webp', 'probe-tx', repeat('b',64)) as v; rollback;"

# ------------------------------------------------- 2. admin-only money routines
if is_uuid "$CUSTOMER_UUID"; then
  probe_msg "7 a customer cannot complete an order" "manage_orders" \
   "begin; set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin perform public.admin_update_order_status((select id from public.orders limit 1), 'completed');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe_msg "8 a customer cannot refund a wallet" "denied" \
   "begin; set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin perform public.admin_refund_wallet((select id from public.orders limit 1), 'probe');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe_msg "9 a customer cannot reject an order" "denied" \
   "begin; set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin perform public.admin_reject_order((select id from public.orders limit 1), 'probe');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe_msg "10 a customer cannot mint a payment code" "denied" \
   "begin; set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin perform public.admin_create_payment_code(1000);
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe "11 a customer cannot write an order directly" ERROR \
   "begin; set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    insert into public.orders (user_id, product_id, product_name_snapshot, price_sdg_snapshot, payment_type)
      values ('$CUSTOMER_UUID', '$PRODUCT_ID', 'probe', 1, 'wallet');
    select 'inserted' as v; rollback;"
  probe "12 a customer cannot move a wallet balance" ERROR \
   "begin; set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    update public.wallets set balance = balance + 1 where user_id = '$CUSTOMER_UUID';
    select 'updated' as v; rollback;"
else
  skip "7-12 customer blocked from admin money routines" "no customer profile"
fi

# ------------------------------------- 3. completion is impossible without evidence
if is_uuid "$ADMIN_UUID" && is_uuid "$CUSTOMER_UUID" && is_uuid "$PRODUCT_ID"; then
  probe_msg "13 a bank order cannot be completed with no receipt" "unverified_payment_evidence" \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000101','$CUSTOMER_UUID','$PRODUCT_ID','probe-bank',100,'bank','in_progress');
    do \$\$ declare m text; begin
      begin perform public.admin_update_order_status('00000000-0000-0000-0000-000000000101'::uuid, 'completed');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe_msg "14 a wallet order cannot be completed with no wallet debit" "unverified_payment_evidence" \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000102','$CUSTOMER_UUID','$PRODUCT_ID','probe-wallet',100,'wallet','in_progress');
    do \$\$ declare m text; begin
      begin perform public.admin_update_order_status('00000000-0000-0000-0000-000000000102'::uuid, 'completed');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe_msg "15 a code order cannot be completed with no used code" "unverified_payment_evidence" \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000103','$CUSTOMER_UUID','$PRODUCT_ID','probe-code',100,'code','in_progress');
    do \$\$ declare m text; begin
      begin perform public.admin_update_order_status('00000000-0000-0000-0000-000000000103'::uuid, 'completed');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe "16 a written override reason is the documented escape hatch" "" \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000104','$CUSTOMER_UUID','$PRODUCT_ID','probe-override',100,'bank','in_progress');
    do \$\$ declare m text; begin
      begin perform public.admin_update_order_status('00000000-0000-0000-0000-000000000104'::uuid, 'completed', 'probe: verified by hand');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe "17 a completed order cannot go straight to in_progress" ERROR \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000105','$CUSTOMER_UUID','$PRODUCT_ID','probe-jump',100,'bank','completed');
    select public.admin_update_order_status('00000000-0000-0000-0000-000000000105'::uuid, 'in_progress') as v;
    rollback;"
else
  skip "13-17 completion requires payment evidence" "no admin/customer/product fixture"
fi

# ------------------------------------------------- 4. tampering and the ledger
if is_uuid "$CUSTOMER_UUID" && is_uuid "$PRODUCT_ID"; then
  probe_msg "18 a forged order price is rejected" "price_tampered" \
   "begin; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin
        insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
          values ('00000000-0000-0000-0000-000000000201','$CUSTOMER_UUID','$PRODUCT_ID','probe-tamper',1,'wallet','pending_review');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  probe_msg "19 a bank order without its own receipt is rejected" "receipt_required" \
   "begin; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin
        insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
          values ('00000000-0000-0000-0000-000000000202','$CUSTOMER_UUID','$PRODUCT_ID','probe-noreceipt',100000,'bank','pending_review');
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
else
  skip "18-19 order tampering guards" "no customer/product fixture"
fi

if is_uuid "$WALLET_USER"; then
  probe "20 a wallet balance cannot move without a ledger entry" ERROR \
   "begin;
    update public.wallets set balance = balance + 1 where user_id = '$WALLET_USER';
    set constraints all immediate;
    select 'no_error' as v;
    rollback;"
else
  skip "20 wallet ledger guard" "no wallet row"
fi

# ---------------------------------------------------------- 5. cancel ownership
if is_uuid "$CUSTOMER_UUID" && is_uuid "$OTHER_UUID" && is_uuid "$PRODUCT_ID"; then
  # the fixture is inserted with the admin claims so the price guard (probe 18)
  # does not reject the synthetic row before the cancel path is exercised
  probe "21 an owner can cancel their own pending_review order" "" \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000301','$CUSTOMER_UUID','$PRODUCT_ID','probe-own',100,'bank','pending_review');
    set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin perform public.cancel_my_order('00000000-0000-0000-0000-000000000301'::uuid);
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
  if [ "$OTHER_UUID" != "$CUSTOMER_UUID" ]; then
    probe_msg "22 another customer cannot cancel that order" "order_not_found" \
     "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
      insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
        values ('00000000-0000-0000-0000-000000000302','$CUSTOMER_UUID','$PRODUCT_ID','probe-foreign',100,'bank','pending_review');
      set local role authenticated; set local request.jwt.claims='$OTHER_CLAIMS';
      do \$\$ declare m text; begin
        begin perform public.cancel_my_order('00000000-0000-0000-0000-000000000302'::uuid);
        exception when others then m := sqlerrm; end;
        $MSG_TAIL"
  else
    skip "22 another customer cannot cancel that order" "only one customer profile exists"
  fi
  probe "23 a completed order cannot be cancelled by its owner" ERROR \
   "begin; set local request.jwt.claims='$ADMIN_CLAIMS';
    insert into public.orders (id,user_id,product_id,product_name_snapshot,price_sdg_snapshot,payment_type,status)
      values ('00000000-0000-0000-0000-000000000303','$CUSTOMER_UUID','$PRODUCT_ID','probe-done',100,'bank','completed');
    set local role authenticated; set local request.jwt.claims='$CUST_CLAIMS';
    select public.cancel_my_order('00000000-0000-0000-0000-000000000303'::uuid) as v;
    rollback;"
else
  skip "21-23 cancel ownership" "no customer/product fixture"
fi

# -------------------------------------------------------- 6. payment code replay
if [ -n "$USED_CODE" ] && [ "$USED_CODE" != "ERROR" ] && is_uuid "$PRODUCT_ID"; then
  probe_msg "24 a used payment code cannot be redeemed again" "already_used" \
   "begin; set local request.jwt.claims='$CUST_CLAIMS';
    do \$\$ declare m text; begin
      begin perform public.redeem_payment_code_order('$USED_CODE', '[{\"product_id\":\"$PRODUCT_ID\",\"quantity\":1}]'::jsonb);
      exception when others then m := sqlerrm; end;
      $MSG_TAIL"
else
  skip "24 payment code replay" "no used payment code in the project"
fi

printf '\n%s passed, %s failed, %s skipped\n' "$probe_pass" "$probe_fail" "$probe_skip"
[ "$probe_fail" -eq 0 ]
