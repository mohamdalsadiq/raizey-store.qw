-- ============================================================================
-- RAIZEY STORE — Security / Integrity invariant suite
-- File: db/tests/security_invariants.sql
-- Run : Supabase SQL editor (or Management API) — READ ONLY, no side effects.
-- Every row returns passed = true|false; any false row is a regression.
-- ============================================================================
WITH f AS (
  SELECT p.oid, p.oid::regprocedure::text AS sig, pg_get_functiondef(p.oid) AS src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f'
),
checks AS (
  -- 1) ledger integrity
  SELECT 'wallet_ledger_balanced' AS check_name,
         NOT EXISTS (
           SELECT 1 FROM public.wallets w
           WHERE w.balance <> COALESCE((SELECT SUM(CASE WHEN t.direction='credit' THEN t.amount ELSE -t.amount END)
                                        FROM public.wallet_transactions t WHERE t.user_id = w.user_id), 0)
         ) AS passed,
         'every wallet balance equals the sum of its ledger entries' AS details
  UNION ALL
  -- 2) deferred ledger guard trigger
  SELECT 'wallet_ledger_guard_trigger', EXISTS (
           SELECT 1 FROM pg_trigger WHERE tgname='trg_assert_wallet_ledger' AND tgdeferrable AND tgenabled <> 'D'
         ), 'trg_assert_wallet_ledger exists, deferrable and enabled'
  UNION ALL
  -- 3) no direct writes by authenticated on money tables
  SELECT 'no_direct_writes_authenticated',
         NOT (has_table_privilege('authenticated','public.orders','INSERT')
           OR has_table_privilege('authenticated','public.orders','UPDATE')
           OR has_table_privilege('authenticated','public.orders','DELETE')
           OR has_table_privilege('authenticated','public.wallets','INSERT')
           OR has_table_privilege('authenticated','public.wallets','UPDATE')
           OR has_table_privilege('authenticated','public.wallets','DELETE')
           OR has_table_privilege('authenticated','public.wallet_topups','INSERT')
           OR has_table_privilege('authenticated','public.wallet_topups','UPDATE')
           OR has_table_privilege('authenticated','public.wallet_topups','DELETE')
           OR has_table_privilege('authenticated','public.wallet_transactions','INSERT')
           OR has_table_privilege('authenticated','public.wallet_transactions','UPDATE')
           OR has_table_privilege('authenticated','public.payment_receipts','INSERT')
           OR has_table_privilege('authenticated','public.payment_receipts','UPDATE')),
         'authenticated can only read orders/wallets/topups/ledger/receipts'
  UNION ALL
  -- 4) wallet history readable but isolated
  SELECT 'wallet_history_readable',
         has_table_privilege('authenticated','public.wallet_transactions','SELECT')
         AND EXISTS (SELECT 1 FROM pg_policies WHERE tablename='wallet_transactions' AND cmd='SELECT'),
         'authenticated may select wallet_transactions (RLS scopes to owner)'
  UNION ALL
  -- 5) anon has no grants on sensitive tables
  SELECT 'anon_no_sensitive_grants',
         NOT EXISTS (
           SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='public'
             AND c.relname IN ('profiles','orders','wallets','wallet_topups','wallet_transactions',
                               'payment_receipts','receipt_scan_results','audit_logs','admin_permissions',
                               'admin_audit_logs','coupons','coupon_redemptions','gift_cards','payment_codes')
             AND c.relacl::text LIKE '%anon=%'
         ), 'anon holds no privileges on sensitive public tables'
  UNION ALL
  -- 6) no PUBLIC/anon execute on administrative functions
  SELECT 'no_public_exec_admin_functions',
         NOT (has_function_privilege('anon','public.admin_confirm_topup(uuid,text)','EXECUTE')
           OR has_function_privilege('anon','public.admin_refund_wallet(uuid,text)','EXECUTE')
           OR has_function_privilege('anon','public.admin_release_receipt(uuid,text)','EXECUTE')
           OR has_function_privilege('anon','public.admin_update_order_status(uuid,text,text)','EXECUTE')
           OR has_function_privilege('anon','public.upsert_admin_permissions(uuid,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)','EXECUTE')
           OR has_function_privilege('anon','public.verify_privilege_model()','EXECUTE')),
         'anonymous visitors cannot execute admin/utility routines'
  UNION ALL
  -- 7) every admin routine keeps its internal guard
  SELECT 'admin_routines_guarded', NOT EXISTS (
           SELECT 1 FROM f
           WHERE f.sig ~ '^(admin_|upsert_admin_permissions|set_store_maintenance|set_store_exchange_rate|bootstrap_super_admin|process_referral_commission|append_admin_audit_log|get_admin_notification_counts|get_my_admin_context|has_admin_permission|is_admin|is_super_admin)'
             AND f.src NOT ILIKE '%is_admin%'
             AND f.src NOT ILIKE '%is_super_admin%'
             AND f.src NOT ILIKE '%has_admin_permission%'
             AND f.src NOT ILIKE '%ADMIN_REQUIRED%'
         ), 'every admin-level routine checks admin/super-admin internally'
  UNION ALL
  -- 8) order price/receipt trigger references real columns only
  SELECT 'order_trigger_valid_columns', (
           SELECT pg_get_functiondef(p.oid) NOT ILIKE '%NEW.payment_method%'
                  AND pg_get_functiondef(p.oid) NOT ILIKE '%NEW.tx_ref%'
                  AND pg_get_functiondef(p.oid) ILIKE '%NEW.payment_type%'
           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname='verify_order_price_before_insert'
         ), 'verify_order_price_before_insert uses payment_type/transaction_reference'
  UNION ALL
  -- 9) topup insert protection
  SELECT 'topup_insert_protected', (
           EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_protect_topup_insert' AND tgenabled <> 'D')
           AND (SELECT pg_get_functiondef(p.oid) ILIKE '%topup_requires_receipt%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public' AND p.proname='protect_topup_insert')
         ), 'receipt-less topup rows are rejected server-side'
  UNION ALL
  -- 10) pg_stat_statements closed to clients
  SELECT 'pg_stat_statements_locked',
         NOT has_function_privilege('anon','extensions.pg_stat_statements(boolean)','EXECUTE')
         AND NOT has_function_privilege('authenticated','extensions.pg_stat_statements(boolean)','EXECUTE'),
         'no client role can read the statement history'
  UNION ALL
  -- 11) referral code entropy + constraint
  SELECT 'referral_code_entropy', (
           (SELECT pg_get_functiondef(p.oid) ILIKE '%FOR i IN 1..8%'
            FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.proname='generate_referral_short_code')
           AND EXISTS (SELECT 1 FROM pg_constraint WHERE conname='profiles_referral_short_code_format'
                       AND pg_get_constraintdef(oid) LIKE '%{5,12}%')
         ), 'short codes use 8 random chars (alphabet without ambiguous glyphs)'
  UNION ALL
  -- 12) no permissive policy on sensitive tables
  SELECT 'no_open_policies', NOT EXISTS (
           SELECT 1 FROM pg_policies
           WHERE schemaname='public'
             AND tablename IN ('profiles','orders','wallets','wallet_topups','wallet_transactions',
                               'payment_receipts','receipt_scan_results','audit_logs','admin_permissions',
                               'coupons','coupon_redemptions','settings')
             AND (qual = 'true' OR with_check = 'true')
         ), 'no USING(true) / WITH CHECK(true) policy on sensitive tables'
  UNION ALL
  -- 13) completion guard present
  SELECT 'completion_guard', (
           SELECT pg_get_functiondef(p.oid) ILIKE '%unverified_payment_evidence%'
                  AND pg_get_functiondef(p.oid) ILIKE '%payment_code_id%'
           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname='admin_update_order_status'
           LIMIT 1
         ), 'orders cannot be completed without verifiable payment evidence'
  UNION ALL
  -- 14) receipt claim quarantine + rate limit
  SELECT 'claim_quarantine_and_throttle', (
           SELECT pg_get_functiondef(p.oid) ILIKE '%v_status_in       := ''needs_review''%'
                  AND pg_get_functiondef(p.oid) ILIKE '%claim:%'
           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname='claim_payment_receipt'
         ), 'unscanned claims are quarantined and throttled per user'
  UNION ALL
  -- 15) RLS enabled on every public table
  SELECT 'rls_enabled_everywhere', NOT EXISTS (
           SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity
         ), 'row level security is enabled on all public tables'
  UNION ALL
  -- 16) receipt uniqueness (replay protection)
  SELECT 'receipt_uniqueness', (
           EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_payment_receipts_tx_norm')
           AND EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_payment_receipts_hash')
           AND EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='unique_orders_receipt_hash')
         ), 'tx_ref and receipt image hashes are unique (no replay)'
  UNION ALL
  -- 17) payment evidence schema + linker
  SELECT 'payment_code_linking', (
           EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='payment_code_id')
           AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_link_order_payment_code' AND tgdeferrable)
         ), 'code orders are linked to the consumed payment code'
  UNION ALL
  -- 18) scan results fully locked to service role
  SELECT 'receipt_scan_results_locked',
         NOT has_table_privilege('anon','public.receipt_scan_results','SELECT')
         AND NOT has_table_privilege('authenticated','public.receipt_scan_results','SELECT'),
         'client roles cannot read the server-side scan records'
  UNION ALL
  -- 19) storage: receipts bucket private
  SELECT 'receipts_bucket_private',
         (SELECT NOT public FROM storage.buckets WHERE id='receipts'),
         'receipt images are not publicly readable'
  UNION ALL
  -- 20) admin audit trail cannot be forged by customers
  SELECT 'audit_trail_trust', (
           (SELECT with_check ILIKE '%is_admin()%' FROM pg_policies
            WHERE tablename='audit_logs' AND cmd='INSERT')
           AND (SELECT qual ILIKE '%is_admin()%' FROM pg_policies
                WHERE tablename='audit_logs' AND cmd='SELECT')
         ), 'audit_logs writes/reads require an admin session'
)
SELECT check_name, passed, details FROM checks ORDER BY passed, check_name;
