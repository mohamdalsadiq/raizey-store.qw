-- =====================================================================
-- RAIZEY STORE — المهمة 6: تحقق ما بعد تطبيق الإصلاح
-- =====================================================================
-- شغّل هذا الملف *بعد* تطبيق supabase-SQL-المهمة-6-ربط-الفحص-الخادمي.sql
-- آمن تماماً: الجزء (أ) قراءة فقط، والجزء (ب) معاملة تنتهي بـ ROLLBACK
-- ولا تُثبَّت أي بيانات على القاعدة إطلاقاً.
-- =====================================================================

-- ─────────────────────────────────────────────────────────────────────
-- الجزء (أ): فحوص بنيوية — قراءة فقط
-- ─────────────────────────────────────────────────────────────────────

-- 1) الدالة موجودة بالتوقيع الصحيح (13 وسيطاً)؟  المتوقّع: صف واحد
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'claim_payment_receipt';

-- 2) جدول الفحص الخادمي موجود؟  المتوقّع: صف واحد (public.receipt_scan_results)
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'receipt_scan_results';

-- 3) المحرّك القديم (hard-reject) يجب أن يكون *غير* مُطبَّق.
--    المتوقّع: 0 صفوف. لو ظهر صف، احذفه لأنه يكسر مسار needs_review المتدهور:
--    DROP TRIGGER IF EXISTS trg_payment_receipts_edge_scan_claim ON public.payment_receipts;
SELECT tgname
FROM pg_trigger
WHERE tgname = 'trg_payment_receipts_edge_scan_claim'
  AND NOT tgisinternal;


-- ─────────────────────────────────────────────────────────────────────
-- الجزء (ب): اختبار وظيفي كامل داخل معاملة تُلغى بالكامل (ROLLBACK)
-- يثبت: (T-شرعي) المسار الصحيح يمر بلا ambiguous id،
--        (T-أحادي) لا يُعاد استخدام نفس الفحص،
--        (T-متدهور) بلا فحص خادمي => needs_review فقط ولا passed تلقائي.
-- لا يُنشئ مستخدماً جديداً؛ يستعير أول مستخدم حقيقي موجود ثم يتراجع عن كل شيء.
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

DO $$
DECLARE
  v_uid       uuid;
  v_scan_id   uuid := gen_random_uuid();
  -- بصمة 64 خانة hex (تطابق CHECK) عبر md5 الأساسية — بلا اعتماد على pgcrypto
  v_hash      text := md5('raizey-task6-selftest-a-' || clock_timestamp()::text || random())
                    || md5('raizey-task6-selftest-b-' || clock_timestamp()::text || random());
  v_hash2     text := md5('raizey-task6-degraded-a-' || clock_timestamp()::text || random())
                    || md5('raizey-task6-degraded-b-' || clock_timestamp()::text || random());
  v_ref       text := 'SELFTEST' || floor(random()*1e6)::int::text;
  v_ref2      text := 'SELFTEST' || floor(random()*1e6)::int::text;
  r           record;
  v_err       text;
BEGIN
  -- استعِر مستخدماً حقيقياً موجوداً (بدون إنشاء)، وفعّل هويته للجلسة
  SELECT id INTO v_uid FROM auth.users ORDER BY created_at LIMIT 1;
  IF v_uid IS NULL THEN
    RAISE NOTICE 'تخطّي الاختبار الوظيفي: لا يوجد مستخدمون في auth.users';
    RETURN;
  END IF;
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  -- أنشئ سجل فحص خادمي "ناجح" مربوطاً بهذه الصورة (بصمة v_hash)
  INSERT INTO public.receipt_scan_results (
    id, user_id, receipt_hash, image_bytes, mime_type,
    expected_amount, manual_ref, decision, ocr_status,
    amount_detected, tx_ref_ocr, provider, ocr_confidence,
    submission_allowed, expires_at
  ) VALUES (
    v_scan_id, v_uid, v_hash, 12345, 'image/jpeg',
    100, v_ref, 'accept', 'passed',
    100, v_ref, 'bankak', 0.98,
    true, now() + interval '10 minutes'
  );

  -- ── T-شرعي: يجب أن يمر بلا ambiguous id ويعيد passed/verified ──
  SELECT * INTO r
  FROM public.claim_payment_receipt(
    p_purpose        => 'order',
    p_tx_ref         => v_ref,
    p_receipt_hash   => v_hash,
    p_amount_expected=> 100,
    p_ocr_status     => 'passed',
    p_ocr_data       => jsonb_build_object('edge_scan_id', v_scan_id::text)
  );
  IF r.ocr_status = 'passed' AND r.amount_verified AND r.ref_verified THEN
    RAISE NOTICE '✅ T-شرعي: نجح (status=%, amount_verified=%, ref_verified=%) — باگ ambiguous id اختفى',
                 r.ocr_status, r.amount_verified, r.ref_verified;
  ELSE
    RAISE WARNING '❌ T-شرعي: نتيجة غير متوقعة (status=%, amount_verified=%, ref_verified=%)',
                 r.ocr_status, r.amount_verified, r.ref_verified;
  END IF;

  -- ── T-أحادي: إعادة استخدام نفس الفحص يجب أن تُرفض ──
  BEGIN
    PERFORM public.claim_payment_receipt(
      p_purpose        => 'order',
      p_tx_ref         => v_ref,
      p_receipt_hash   => v_hash,
      p_amount_expected=> 100,
      p_ocr_status     => 'passed',
      p_ocr_data       => jsonb_build_object('edge_scan_id', v_scan_id::text)
    );
    RAISE WARNING '❌ T-أحادي: كان يجب أن يُرفض لكنه نجح!';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err IN ('receipt_scan_already_used','duplicate_receipt_image','duplicate_transaction_ref') THEN
      RAISE NOTICE '✅ T-أحادي: رُفض كما هو متوقع (%%)', v_err;
    ELSE
      RAISE WARNING '⚠️ T-أحادي: رُفض بخطأ غير متوقع (%%)', v_err;
    END IF;
  END;

  -- ── T-متدهور: بلا edge_scan_id => needs_review فقط، لا passed تلقائي ──
  SELECT * INTO r
  FROM public.claim_payment_receipt(
    p_purpose        => 'order',
    p_tx_ref         => v_ref2,
    p_receipt_hash   => v_hash2,
    p_amount_expected=> 100,
    p_ocr_status     => 'passed',                 -- محاولة تمرير passed من "المتصفح"
    p_ocr_data       => '{}'::jsonb               -- لا يوجد فحص خادمي
  );
  IF r.ocr_status = 'needs_review' AND NOT r.amount_verified AND NOT r.ref_verified THEN
    RAISE NOTICE '✅ T-متدهور: تحوّل إلى needs_review رغم محاولة تمرير passed — الثغرة مغلقة';
  ELSE
    RAISE WARNING '❌ T-متدهور: نتيجة غير متوقعة (status=%, amount_verified=%)',
                 r.ocr_status, r.amount_verified;
  END IF;

  RAISE NOTICE '——— انتهى الاختبار الوظيفي؛ كل التغييرات ستُلغى بـ ROLLBACK ———';
END;
$$;

ROLLBACK;
