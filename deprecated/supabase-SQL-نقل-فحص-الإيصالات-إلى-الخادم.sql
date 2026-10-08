-- RAIZEY STORE — نقل فحص الإيصالات إلى Supabase Edge Function
-- شغّل هذا الملف بعد نشر process-receipt وتحديث واجهات العميل.
-- لا يحتوي على مفاتيح أو بيانات سرية.
-- يمكن التراجع عن كائنات هذا الملف عبر DROP للمحركات/الجدول بعد إيقاف الواجهة الجديدة.

BEGIN;

CREATE TABLE IF NOT EXISTS public.receipt_scan_results (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receipt_hash        text NOT NULL CHECK (receipt_hash ~ '^[0-9a-f]{64}$'),
  image_bytes         integer NOT NULL CHECK (image_bytes > 0 AND image_bytes <= 33554432),
  mime_type           text NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','image/webp','image/heic','image/heif')),
  expected_amount     numeric,
  manual_ref         text,
  expected_account    text,
  decision            text NOT NULL DEFAULT 'review' CHECK (decision IN ('accept','reject','review','review_admin')),
  ocr_status          text NOT NULL DEFAULT 'needs_review',
  amount_detected     numeric,
  tx_ref_ocr          text,
  provider            text,
  provider_name       text,
  ocr_confidence      numeric,
  risk_flags          text[] NOT NULL DEFAULT '{}',
  ocr_data            jsonb NOT NULL DEFAULT '{}'::jsonb,
  submission_allowed  boolean NOT NULL DEFAULT false,
  created_at          timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz NOT NULL,
  claimed_at          timestamptz,
  claimed_receipt_id  uuid,
  consumed_at         timestamptz,
  consumed_by_table   text,
  consumed_record_id  uuid
);

CREATE INDEX IF NOT EXISTS idx_receipt_scan_results_user_created
  ON public.receipt_scan_results (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_receipt_scan_results_expires
  ON public.receipt_scan_results (expires_at);
CREATE INDEX IF NOT EXISTS idx_receipt_scan_results_hash
  ON public.receipt_scan_results (receipt_hash);

ALTER TABLE public.receipt_scan_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.receipt_scan_results FROM anon, authenticated;

-- Edge Function تستخدم service role للحفظ، ولا تكشف نتائج OCR الخام للعميل عبر PostgREST.
DROP POLICY IF EXISTS receipt_scan_results_no_client_access ON public.receipt_scan_results;

CREATE OR REPLACE FUNCTION public.enforce_edge_receipt_scan_claim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scan_id       uuid;
  v_scan          public.receipt_scan_results%ROWTYPE;
  v_expected_ref  text;
  v_claim_ref     text;
BEGIN
  v_scan_id := NULLIF(NEW.ocr_data->>'edge_scan_id', '')::uuid;
  IF v_scan_id IS NULL THEN
    RAISE EXCEPTION 'receipt_scan_required';
  END IF;

  SELECT * INTO v_scan
  FROM public.receipt_scan_results rs
  WHERE rs.id = v_scan_id
    AND rs.user_id = NEW.user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'receipt_scan_not_found';
  END IF;
  IF v_scan.expires_at <= now() THEN
    RAISE EXCEPTION 'receipt_scan_expired';
  END IF;
  IF NOT v_scan.submission_allowed OR v_scan.decision = 'reject' OR v_scan.ocr_status = 'rejected' THEN
    RAISE EXCEPTION 'receipt_scan_rejected';
  END IF;
  IF lower(trim(v_scan.receipt_hash)) <> lower(trim(NEW.receipt_hash)) THEN
    RAISE EXCEPTION 'receipt_scan_hash_mismatch';
  END IF;
  IF v_scan.expected_amount IS NOT NULL AND NEW.amount_expected IS NOT NULL
     AND abs(v_scan.expected_amount - NEW.amount_expected) > GREATEST(v_scan.expected_amount * 0.01, 2) THEN
    RAISE EXCEPTION 'receipt_scan_amount_context_mismatch';
  END IF;
  IF NEW.amount_detected IS DISTINCT FROM v_scan.amount_detected THEN
    RAISE EXCEPTION 'receipt_scan_amount_tampered';
  END IF;
  IF public.normalize_tx_ref(NEW.tx_ref_ocr) IS DISTINCT FROM public.normalize_tx_ref(v_scan.tx_ref_ocr) THEN
    RAISE EXCEPTION 'receipt_scan_reference_tampered';
  END IF;
  IF lower(trim(coalesce(NEW.provider, ''))) IS DISTINCT FROM lower(trim(coalesce(v_scan.provider, ''))) THEN
    RAISE EXCEPTION 'receipt_scan_provider_tampered';
  END IF;
  IF NEW.ocr_confidence IS DISTINCT FROM v_scan.ocr_confidence THEN
    RAISE EXCEPTION 'receipt_scan_confidence_tampered';
  END IF;
  IF v_scan.ocr_status = 'passed' AND NEW.ocr_status NOT IN ('passed', 'needs_admin_check') THEN
    RAISE EXCEPTION 'receipt_scan_status_tampered';
  ELSIF v_scan.ocr_status = 'needs_admin_check' AND NEW.ocr_status <> 'needs_admin_check' THEN
    RAISE EXCEPTION 'receipt_scan_status_tampered';
  ELSIF v_scan.ocr_status NOT IN ('passed', 'needs_admin_check')
        AND NEW.ocr_status IS DISTINCT FROM v_scan.ocr_status THEN
    RAISE EXCEPTION 'receipt_scan_status_tampered';
  END IF;

  v_expected_ref := public.normalize_tx_ref(v_scan.manual_ref);
  v_claim_ref := public.normalize_tx_ref(NEW.tx_ref_raw);
  IF v_expected_ref IS NULL OR v_claim_ref IS NULL OR v_expected_ref <> v_claim_ref THEN
    RAISE EXCEPTION 'receipt_scan_reference_mismatch';
  END IF;

  IF v_scan.expected_amount IS NOT NULL AND NEW.amount_expected IS NOT NULL
     AND abs(v_scan.expected_amount - NEW.amount_expected) > GREATEST(v_scan.expected_amount * 0.01, 2) THEN
    RAISE EXCEPTION 'receipt_scan_amount_context_mismatch';
  END IF;

  -- الحجز المالي والنتيجة الخادمية مرتبطان داخل نفس المعاملة.
  UPDATE public.receipt_scan_results
  SET claimed_at = COALESCE(claimed_at, now()),
      claimed_receipt_id = COALESCE(claimed_receipt_id, NEW.id)
  WHERE id = v_scan.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_receipts_edge_scan_claim ON public.payment_receipts;
CREATE TRIGGER trg_payment_receipts_edge_scan_claim
AFTER INSERT ON public.payment_receipts
FOR EACH ROW
EXECUTE FUNCTION public.enforce_edge_receipt_scan_claim();

CREATE OR REPLACE FUNCTION public.mark_edge_receipt_scan_consumed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scan_id uuid;
BEGIN
  IF NEW.receipt_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT NULLIF(pr.ocr_data->>'edge_scan_id', '')::uuid
  INTO v_scan_id
  FROM public.payment_receipts pr
  WHERE pr.id = NEW.receipt_id;

  IF v_scan_id IS NULL THEN
    RAISE EXCEPTION 'receipt_scan_required';
  END IF;

  -- السلة قد تُدخل عدة صفوف orders لنفس الإيصال؛ أول صف يعلّم النتيجة
  -- والمزيد من الصفوف يمرّ لأن الحجز الأصلي تم التحقق منه داخل نفس المعاملة.
  UPDATE public.receipt_scan_results
  SET consumed_at = COALESCE(consumed_at, now()),
      consumed_by_table = COALESCE(consumed_by_table, TG_TABLE_NAME),
      consumed_record_id = COALESCE(consumed_record_id, NEW.id)
  WHERE id = v_scan_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_edge_scan_consumed ON public.orders;
CREATE TRIGGER trg_orders_edge_scan_consumed
AFTER INSERT ON public.orders
FOR EACH ROW
WHEN (NEW.receipt_id IS NOT NULL)
EXECUTE FUNCTION public.mark_edge_receipt_scan_consumed();

DROP TRIGGER IF EXISTS trg_wallet_topups_edge_scan_consumed ON public.wallet_topups;
CREATE TRIGGER trg_wallet_topups_edge_scan_consumed
AFTER INSERT ON public.wallet_topups
FOR EACH ROW
WHEN (NEW.receipt_id IS NOT NULL)
EXECUTE FUNCTION public.mark_edge_receipt_scan_consumed();

REVOKE ALL ON FUNCTION public.enforce_edge_receipt_scan_claim() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_edge_receipt_scan_consumed() FROM anon, authenticated;

COMMIT;

-- تحقق محدود بعد التشغيل:
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'receipt_scan_results'
ORDER BY ordinal_position
LIMIT 40;
