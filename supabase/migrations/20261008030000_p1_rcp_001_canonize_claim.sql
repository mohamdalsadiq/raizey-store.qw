-- P1-RCP-001: canonize the secure claim_payment_receipt as the single definition.
--
-- Background (DBSEC2-002): three competing definitions existed in loose SQL files
-- (supabase-critical-fixes-5.sql, supabase-critical-fixes-7.sql = DANGEROUS variants
-- that trusted client OCR; supabase-SQL-...-6 = secure variant). The LIVE database
-- already runs the secure variant (verified 2026-10-07/08, md5 946ea1b4842366923887454e67144cba).
-- This migration pins that exact body as canonical so no future loose-file apply
-- can silently regress it.
--
-- SECURITY INVARIANT (non-negotiable): CLIENT OCR MUST NEVER BE TRUSTED.
-- The function binds edge_scan_id server-side, requires receipt_scan_results.user_id
-- = auth.uid(), locks the scan, rejects expired/rejected/hash-mismatch/used scans,
-- replaces browser OCR values with server-stored values, forces needs_review
-- without a scan, and marks claimed_at/claimed_receipt_id atomically.
--
-- SAFE: re-applies the identical live body (no-op). ROLLBACK: n/a (no change).

CREATE OR REPLACE FUNCTION public.claim_payment_receipt(
  p_purpose text, p_tx_ref text, p_receipt_hash text, p_receipt_path text DEFAULT NULL::text, p_provider text DEFAULT NULL::text, p_payment_method_id uuid DEFAULT NULL::uuid, p_amount_expected numeric DEFAULT NULL::numeric, p_amount_detected numeric DEFAULT NULL::numeric, p_tx_ref_ocr text DEFAULT NULL::text, p_ocr_status text DEFAULT 'needs_review'::text, p_ocr_confidence numeric DEFAULT NULL::numeric, p_risk_flags text[] DEFAULT '{}'::text[], p_ocr_data jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE(id uuid, ocr_status text, amount_verified boolean, ref_verified boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_norm     text;
  v_hash     text;
  v_amount_v boolean := false;
  v_ref_v    boolean := false;
  v_status   text;
  v_id       uuid;
  v_scan_id  uuid;
  v_scan     public.receipt_scan_results%ROWTYPE;
  v_status_in text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;
  IF public.is_banned() THEN
    RAISE EXCEPTION 'access_denied';
  END IF;

  IF p_purpose NOT IN ('order', 'topup') THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  v_norm := public.normalize_tx_ref(p_tx_ref);
  v_hash := lower(trim(coalesce(p_receipt_hash, '')));

  -- رقم العملية: 6 خانات على الأقل (كل بنوك السودان أطول من ذلك)
  IF v_norm IS NULL OR length(v_norm) < 6 THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;
  -- بصمة SHA-256 = 64 خانة hex
  IF v_hash = '' OR v_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid_receipt_input';
  END IF;

  -- الفحص الذكي رفض الإيصال → لا نحجزه ولا نُدخل طلباً
  IF coalesce(p_ocr_status, '') = 'rejected' THEN
    RAISE EXCEPTION 'receipt_rejected';
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- التحقق الخادمي: ربط القرار بنتيجة الفحص المخزّنة (لا يُوثَق بالمتصفح)
  -- ═══════════════════════════════════════════════════════════════════
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
    -- الفحص مرتبط بصورة هذا الإيصال بالذات (بصمة SHA-256)
    IF lower(trim(coalesce(v_scan.receipt_hash, ''))) <> v_hash THEN
      RAISE EXCEPTION 'receipt_scan_hash_mismatch';
    END IF;
    -- لا يُعاد استهلاك نفس الفحص لإيصالين
    IF v_scan.claimed_at IS NOT NULL THEN
      RAISE EXCEPTION 'receipt_scan_already_used';
    END IF;

    -- القيم الحاسمة تُؤخذ من السيرفر حصراً — تجاهل ما أرسله المتصفح
    p_amount_detected := v_scan.amount_detected;
    p_tx_ref_ocr      := v_scan.tx_ref_ocr;
    p_ocr_confidence  := v_scan.ocr_confidence;
    p_provider        := COALESCE(NULLIF(trim(coalesce(p_provider, '')), ''), v_scan.provider);
  ELSE
    -- بلا فحص خادمي مرتبط: لا يُسمح بأي وسم تحقق تلقائي إطلاقاً
    p_amount_detected := NULL;
    p_tx_ref_ocr      := NULL;
    p_ocr_confidence  := NULL;
    IF v_status_in NOT IN ('needs_admin_check') THEN
      v_status_in := 'needs_review';
    END IF;
  END IF;

  -- ── فحص السجلات التاريخية (طلبات/شحنات أُدخلت قبل هذا النظام) ──
  IF EXISTS (
    SELECT 1 FROM orders
    WHERE public.normalize_tx_ref(transaction_reference) = v_norm
  ) OR EXISTS (
    SELECT 1 FROM wallet_topups
    WHERE public.normalize_tx_ref(transaction_reference) = v_norm
  ) THEN
    RAISE EXCEPTION 'duplicate_transaction_ref';
  END IF;

  IF EXISTS (SELECT 1 FROM orders        WHERE lower(receipt_hash) = v_hash)
  OR EXISTS (SELECT 1 FROM wallet_topups WHERE lower(receipt_hash) = v_hash) THEN
    RAISE EXCEPTION 'duplicate_receipt_image';
  END IF;

  -- ── حالة التحقق تُحسب في السيرفر من قيم الفحص الموثوقة ──
  IF p_amount_expected IS NOT NULL AND p_amount_detected IS NOT NULL
     AND p_amount_expected > 0 THEN
    -- هامش 1% أو 2 جنيه (أيهما أكبر) لتفادي فروق التقريب
    v_amount_v := abs(p_amount_detected - p_amount_expected)
                  <= GREATEST(p_amount_expected * 0.01, 2);
  END IF;

  v_ref_v := public.normalize_tx_ref(p_tx_ref_ocr) IS NOT NULL
             AND public.normalize_tx_ref(p_tx_ref_ocr) = v_norm;

  IF v_amount_v AND v_ref_v THEN
    -- تدقيق إداري مطلوب (إشعار قديم / دفع مجزّأ): يُقبل الطلب لكن يبقى موسوماً
    IF v_status_in = 'needs_admin_check' THEN
      v_status := 'needs_admin_check';
    ELSE
      v_status := 'passed';
    END IF;
  ELSIF v_status_in = 'needs_admin_check' THEN
    v_status := 'needs_admin_check';
  ELSE
    v_status := 'needs_review';
  END IF;

  -- ── الحجز الذرّي: القيود الفريدة هي الحاجز الحقيقي ──
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

  -- ── وسم سجل الفحص كمُستهلَك داخل نفس المعاملة (يمنع إعادة الاستخدام) ──
  IF v_scan_id IS NOT NULL THEN
    UPDATE public.receipt_scan_results rs
    SET claimed_at         = COALESCE(rs.claimed_at, now()),
        claimed_receipt_id = COALESCE(rs.claimed_receipt_id, v_id)
    WHERE rs.id = v_scan_id;
  END IF;

  RETURN QUERY SELECT v_id, v_status, v_amount_v, v_ref_v;
END;
$$;

COMMENT ON FUNCTION public.claim_payment_receipt(text, text, text, text, text, uuid, numeric, numeric, text, text, numeric, text[], jsonb) IS
  'P1-RCP-001 canonical secure variant. INVARIANT: CLIENT OCR MUST NEVER BE TRUSTED. Verified live md5 946ea1b4842366923887454e67144cba.';
