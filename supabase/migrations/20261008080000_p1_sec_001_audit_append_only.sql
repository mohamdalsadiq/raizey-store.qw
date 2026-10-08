-- P1-SEC-001: trusted audit architecture — append-only audit log.
--
-- Background: audit_logs_admin was an ALL policy — any admin could UPDATE or
-- DELETE audit rows via the API, tampering with the trail. Combined with P0-SEC-001
-- (source column, customer INSERT removed, report_fraud_alert()), the log is now:
--   - customers: can only file reports via report_fraud_alert() (source='customer_report')
--   - admins: INSERT + SELECT only — no UPDATE/DELETE policy exists, so rows are
--     immutable through the API. All server writes are INSERT-only (verified).
--
-- SAFE: no function UPDATEs/DELETEs audit_logs (verified 2026-10-08).
-- ROLLBACK: re-create the ALL policy (not recommended).
-- APPLIED LIVE: 2026-10-08.

DROP POLICY IF EXISTS audit_logs_admin ON public.audit_logs;

CREATE POLICY audit_logs_admin_insert ON public.audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

COMMENT ON POLICY audit_logs_admin_insert ON public.audit_logs IS
  'P1-SEC-001: append-only audit — admins can INSERT/SELECT, never UPDATE/DELETE.';
