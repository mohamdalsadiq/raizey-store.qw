-- P0-SEC-001: close the customer-controlled stored-XSS path into the admin audit log.
--
-- Background (SEC-ADM-001, confirmed live 2026-10-07):
--   * admin-audit-log.html rendered audit rows with innerHTML (fixed in this change).
--   * Policy audit_logs_insert_customer allowed ANY authenticated user to INSERT
--     rows with admin_id IS NULL, which then rendered in the admin's browser.
-- This migration removes the forge path and keeps the one legitimate
-- customer-originated signal (duplicate-receipt fraud alerts) behind a narrow
-- server-side RPC with server-fixed action and server-bound reporter.
--
-- SAFE TO APPLY: additive column, policy drop, new function. No data deletion.
-- ROLLBACK: re-create audit_logs_insert_customer (re-opens the hole - do not).

-- 1) Tag every audit row with its origin. Server-set only; never client-set.
ALTER TABLE public.audit_logs
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'admin_action';

-- Backfill: rows written with admin_id IS NULL came from customers.
UPDATE public.audit_logs
SET source = 'customer_report'
WHERE admin_id IS NULL AND source = 'admin_action';

-- 2) Drop the over-permissive customer INSERT policy (the forge path).
DROP POLICY IF EXISTS audit_logs_insert_customer ON public.audit_logs;

-- 3) Narrow RPC for duplicate-receipt fraud alerts (replaces wallet.html direct INSERT).
CREATE OR REPLACE FUNCTION public.report_fraud_alert(p_details jsonb DEFAULT '{}')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
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
END;
$$;

REVOKE ALL ON FUNCTION public.report_fraud_alert(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.report_fraud_alert(jsonb) TO authenticated;

COMMENT ON FUNCTION public.report_fraud_alert(jsonb) IS
  'P0-SEC-001: narrow customer-originated fraud signal. Action is server-fixed; reporter is server-bound to auth.uid(). Customer direct INSERTs into audit_logs are no longer possible.';
