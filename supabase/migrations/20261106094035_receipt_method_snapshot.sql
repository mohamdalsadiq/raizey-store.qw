-- Bind a scan to the exact recipient configuration used by the server.
BEGIN;
CREATE OR REPLACE FUNCTION private.receipt_method_snapshot(p_method uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
 SELECT jsonb_build_object('id',m.id,'name',m.name,'account_name',m.account_name,
  'account_number',m.account_number,'bin_prefixes',m.bin_prefixes,'bank_key',m.bank_key)
 FROM public.payment_methods m WHERE m.id=p_method AND m.is_active
$$;
CREATE OR REPLACE FUNCTION private.require_receipt_method_snapshot() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE expected jsonb; scanned jsonb;
BEGIN
 expected:=private.receipt_method_snapshot(NEW.payment_method_id);
 SELECT r.ocr_data->'expected_method_snapshot' INTO scanned FROM public.receipt_scan_results r
 WHERE r.id=(NEW.ocr_data->>'edge_scan_id')::uuid AND r.user_id=NEW.user_id;
 IF expected IS NULL OR scanned IS DISTINCT FROM expected THEN RAISE EXCEPTION 'receipt_method_changed'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.receipt_method_snapshot(uuid),private.require_receipt_method_snapshot() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.receipt_method_snapshot(uuid),private.require_receipt_method_snapshot() TO service_role;
DROP TRIGGER IF EXISTS require_receipt_method_snapshot ON public.payment_receipts;
CREATE TRIGGER require_receipt_method_snapshot BEFORE INSERT ON public.payment_receipts
 FOR EACH ROW EXECUTE FUNCTION private.require_receipt_method_snapshot();
COMMIT;
