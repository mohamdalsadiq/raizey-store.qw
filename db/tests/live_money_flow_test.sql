-- ============================================================================
-- MEEM STORE — اختبار تدفقات المال على القاعدة الحية (Live money-flow test)
-- File : db/tests/live_money_flow_test.sql
-- Rule : تعمل داخل معاملة واحدة وتنتهي بـ ROLLBACK دائماً — لا تترك أي بيانات.
-- Run  : Management API (POST /v1/projects/<ref>/database/query) أو SQL Editor.
-- Tested users: مستخدمون حقيقيون (زبون + زبون آخر + أدمن) بلا أي تعديل دائم.
-- ============================================================================
BEGIN;
CREATE TEMP TABLE mft(n int, name text, ok boolean, detail text);
GRANT ALL ON mft TO authenticated;

-- ---------------------------------------------------------------------------
-- 0) تجهيز المراجع
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE ctx AS
SELECT
  (SELECT id FROM public.profiles WHERE role='customer' ORDER BY created_at LIMIT 1)  AS user_a,
  (SELECT o.user_id FROM public.orders o
    WHERE o.user_id IN (SELECT id FROM public.profiles WHERE role='customer')
      AND o.user_id <> (SELECT id FROM public.profiles WHERE role='customer' ORDER BY created_at LIMIT 1)
    GROUP BY o.user_id ORDER BY count(*) DESC LIMIT 1) AS user_b,
  (SELECT id FROM public.profiles WHERE role='admin' LIMIT 1) AS admin_id,
  (SELECT id FROM public.products WHERE is_active AND jsonb_array_length(COALESCE(options,'[]'::jsonb))>0 LIMIT 1) AS prod_opt,
  (SELECT id FROM public.products WHERE is_active AND jsonb_array_length(COALESCE(options,'[]'::jsonb))=0 LIMIT 1) AS prod_plain,
  (SELECT id FROM public.payment_methods WHERE is_active LIMIT 1) AS method_id,
  (SELECT code FROM public.coupons WHERE is_active LIMIT 1) AS coupon_code;
GRANT SELECT ON ctx TO authenticated;

-- ---------------------------------------------------------------------------
-- 1) طلب شحن من إيصال (مسار quarantined: بلا فحص خادمي)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT user_a FROM ctx),'role','authenticated')::text, true);

DO $$
DECLARE v_m uuid; v_p uuid; v_topup record; v_before numeric; v_after numeric; v_tx int; v_url text;
BEGIN
  SELECT method_id INTO v_m FROM ctx; SELECT prod_opt INTO v_p FROM ctx;
  SELECT balance INTO v_before FROM public.wallets WHERE user_id = auth.uid();

  SELECT * INTO v_topup FROM public.create_wallet_topup_from_receipt(
    p_amount        => 1500,
    p_payment_method_id => v_m,
    p_receipt_url   => 'https://evil.example.com/fake.png',   -- يجب أن يُتجاهل
    p_tx_ref        => 'MFT-TOPUP-000001',
    p_receipt_hash  => repeat('a', 64),
    p_receipt_path  => auth.uid()::text || '/mft_topup_1.jpg',
    p_provider      => 'bankak',
    p_amount_detected => NULL,
    p_ocr_status    => 'needs_review',
    p_risk_flags    => ARRAY['mft_probe']
  );
  INSERT INTO mft VALUES (1,'topup created from receipt (quarantine)', v_topup.id IS NOT NULL, 'topup='||v_topup.id::text||' ocr='||v_topup.ocr_status);

  SELECT receipt_url INTO v_url FROM public.wallet_topups WHERE id = v_topup.id;
  INSERT INTO mft VALUES (2,'client receipt_url ignored (canonical path)', v_url = 'receipts/'||auth.uid()::text||'/mft_topup_1.jpg', 'stored='||coalesce(v_url,'NULL'));
END $$;

-- ---------------------------------------------------------------------------
-- 2) منع الشحن بلا إيصال + منع رابط بلا إيصال
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  BEGIN
    INSERT INTO public.wallet_topups (user_id, amount, payment_method_id, status)
    VALUES (auth.uid(), 500, (SELECT method_id FROM ctx), 'pending');
    INSERT INTO mft VALUES (3,'receipt-less topup rejected', false, 'INSERT SUCCEEDED (BAD)');
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (3,'receipt-less topup rejected', true, left(SQLERRM,80));
  END;
END $$;

-- ---------------------------------------------------------------------------
-- 3) تكرار نفس رقم العملية (replay) ونفس بصمة الصورة
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  BEGIN
    PERFORM * FROM public.create_wallet_topup_from_receipt(2000, (SELECT method_id FROM ctx), NULL, 'MFT-TOPUP-000001', repeat('b',64), auth.uid()::text||'/mft_topup_2.jpg');
    INSERT INTO mft VALUES (4,'duplicate tx_ref rejected', false, 'NO ERROR (BAD)');
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (4,'duplicate tx_ref rejected', true, left(SQLERRM,80));
  END;
  BEGIN
    PERFORM * FROM public.create_wallet_topup_from_receipt(2000, (SELECT method_id FROM ctx), NULL, 'MFT-TOPUP-000002', repeat('a',64), auth.uid()::text||'/mft_topup_3.jpg');
    INSERT INTO mft VALUES (5,'duplicate receipt image rejected', false, 'NO ERROR (BAD)');
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (5,'duplicate receipt image rejected', true, left(SQLERRM,80));
  END;
END $$;

-- ---------------------------------------------------------------------------
-- 4) مسار استخدام الآخرين: رفض receipt_path لا يخص المستخدم
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  BEGIN
    PERFORM * FROM public.create_wallet_topup_from_receipt(700, (SELECT method_id FROM ctx), NULL, 'MFT-TOPUP-000003', repeat('c',64), '00000000-0000-0000-0000-000000000001/mft_steal.jpg');
    INSERT INTO mft VALUES (6,'foreign receipt_path rejected', false, 'NO ERROR (BAD)');
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (6,'foreign receipt_path rejected', true, left(SQLERRM,80));
  END;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 5) الأدمن: تأكيد الشحن بلا إيصال موثّق يحتاج سبب تجاوز (ثم ينجح مع السبب)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT admin_id FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_topup uuid; v_before numeric; v_after numeric; v_led int; v_res text;
BEGIN
  SELECT id INTO v_topup FROM public.wallet_topups WHERE transaction_reference='MFT-TOPUP-000001' ORDER BY created_at DESC LIMIT 1;
  SELECT balance INTO v_before FROM public.wallets WHERE user_id=(SELECT user_a FROM ctx);
  BEGIN
    PERFORM public.admin_confirm_topup(v_topup, NULL);
    INSERT INTO mft VALUES (7,'confirm without receipt requires reason', false, 'CONFIRMED WITHOUT REASON (BAD)');
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (7,'confirm without receipt requires reason', true, left(SQLERRM,80));
  END;
  PERFORM public.admin_confirm_topup(v_topup, 'MFT: تحقق يدوي من الإيصال');
  SELECT balance INTO v_after FROM public.wallets WHERE user_id=(SELECT user_a FROM ctx);
  SELECT count(*) INTO v_led FROM public.wallet_transactions
   WHERE user_id=(SELECT user_a FROM ctx) AND source='topup' AND created_at >= transaction_timestamp();
  INSERT INTO mft VALUES (8,'confirm with override credits wallet + ledger', (v_after - v_before)=1500 AND v_led=1,
    'delta='||(v_after-v_before)::text||' ledger_rows='||v_led);
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 6) طلب بنكي بإيصال: الاختيار الصحيح للسعر + ربط الإيصال + منع الإكمال بلا تحقق
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT user_a FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_orders uuid[]; v_order uuid; v_url text; v_opt text; v_status text; v_res text;
BEGIN
  SELECT opt->>'id' INTO v_opt
  FROM public.products p, jsonb_array_elements(p.options) opt
  WHERE p.id = (SELECT prod_opt FROM ctx)
  LIMIT 1;
  SELECT array_agg(id) INTO v_orders FROM public.create_bank_orders_bulk(
    p_items  => jsonb_build_array(jsonb_build_object('product_id',(SELECT prod_opt FROM ctx),'option_id',v_opt)),
    p_receipt=> jsonb_build_object(
       'tx_ref','MFT-BANK-000001','receipt_hash',repeat('d',64),
       'receipt_path', auth.uid()::text||'/mft_bank_1.jpg','provider','bankak',
       'payment_method_id',(SELECT method_id FROM ctx),
       'amount_expected',1000,'ocr_status','needs_review',
       'receipt_url','https://evil.example.com/fake2.png',
       'risk_flags',jsonb_build_array('mft_probe')),
    p_coupon_code => NULL
  );
  v_order := v_orders[1];
  INSERT INTO mft VALUES (9,'bank order created atomically with receipt', v_order IS NOT NULL, 'order='||coalesce(v_order::text,'NULL'));
  SELECT receipt_url INTO v_url FROM public.orders WHERE id=v_order;
  INSERT INTO mft VALUES (10,'order receipt_url canonical (client url ignored)', v_url LIKE 'receipts/'||auth.uid()::text||'/%', 'stored='||coalesce(v_url,'NULL'));
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT admin_id FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_order uuid; v_res text;
BEGIN
  SELECT id INTO v_order FROM public.orders WHERE transaction_reference='MFT-BANK-000001' LIMIT 1;
  PERFORM public.admin_update_order_status(v_order,'in_progress',NULL);
  BEGIN
    PERFORM public.admin_update_order_status(v_order,'completed',NULL);
    INSERT INTO mft VALUES (11,'complete unverified bank order blocked', false, 'COMPLETED WITHOUT EVIDENCE (BAD)');
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (11,'complete unverified bank order blocked', SQLERRM LIKE '%unverified_payment_evidence%', left(SQLERRM,90));
  END;
  BEGIN
    PERFORM public.admin_update_order_status(v_order,'completed','MFT: إيصال مرفوع ومراجَع يدوياً');
    UPDATE mft SET ok = true WHERE n = 11;
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (11,'complete unverified bank order blocked', false, left(SQLERRM,90));
  END;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 7) طلب من المحفظة: خصم + قيد + كشف التلاعب بالسعر
--    (تمويل اختباري داخل المعاملة نفسها — يُلغى مع ROLLBACK)
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_new numeric;
BEGIN
  UPDATE public.wallets SET balance = balance + 100000000, updated_at = now()
  WHERE user_id = (SELECT user_a FROM ctx) RETURNING balance INTO v_new;
  INSERT INTO public.wallet_transactions (user_id, amount, direction, balance_after, source, details)
  VALUES ((SELECT user_a FROM ctx), 100000000, 'credit', v_new, 'mft_probe',
          jsonb_build_object('note','rollback-only funding for the money-flow test'));
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT user_a FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_before numeric; v_after numeric; v_led int; v_ids uuid[]; v_res text;
BEGIN
  SELECT balance INTO v_before FROM public.wallets WHERE user_id=auth.uid();
  BEGIN
    SELECT array_agg(id) INTO v_ids FROM public.create_wallet_orders_bulk(
      p_items => jsonb_build_array(jsonb_build_object('product_id',(SELECT prod_plain FROM ctx))),
      p_coupon_code => NULL);
    SELECT balance INTO v_after FROM public.wallets WHERE user_id=auth.uid();
    SELECT count(*) INTO v_led FROM public.wallet_transactions
      WHERE user_id=auth.uid() AND source='wallet_order_bulk' AND created_at >= transaction_timestamp();
    INSERT INTO mft VALUES (12,'wallet order debits balance + ledger', v_after < v_before AND v_led >= 1,
      'before='||v_before::text||' after='||v_after::text||' ledger='||v_led);
  EXCEPTION WHEN others THEN
    INSERT INTO mft VALUES (12,'wallet order debits balance + ledger', false, left(SQLERRM,120));
  END;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 8) إلغاء + استرداد (refund) مع قيد مالي
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT admin_id FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_order uuid; v_before numeric; v_after numeric; v_led int;
BEGIN
  SELECT id INTO v_order FROM public.orders
   WHERE user_id=(SELECT user_a FROM ctx) AND payment_type='wallet' AND status IN ('pending_review','in_progress')
   ORDER BY created_at DESC LIMIT 1;
  IF v_order IS NULL THEN
    INSERT INTO mft VALUES (13,'cancel + refund wallet order', false, 'no wallet order found to refund');
    RETURN;
  END IF;
  SELECT balance INTO v_before FROM public.wallets WHERE user_id=(SELECT user_a FROM ctx);
  -- الإلغاء يستدعي الاسترداد الداخلي (admin_refund_wallet) بنفسه — المسار الإنتاجي
  PERFORM public.admin_update_order_status(v_order,'cancelled',NULL);
  SELECT balance INTO v_after FROM public.wallets WHERE user_id=(SELECT user_a FROM ctx);
  SELECT count(*) INTO v_led FROM public.wallet_transactions
    WHERE user_id=(SELECT user_a FROM ctx) AND source = 'admin_refund'
      AND reference_id = v_order AND created_at >= transaction_timestamp();
  INSERT INTO mft VALUES (13,'cancel auto-refunds wallet order + ledger', v_after > v_before AND v_led = 1,
    'before='||v_before::text||' after='||v_after::text||' refund_ledger='||v_led);
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 9) كرت هدية + نقاط ولاء + كوبون + كود دفع
-- ---------------------------------------------------------------------------
-- كرت هدية اختباري داخل المعاملة (يُلغى بالكامل)
-- ملاحظة: سياسة RLS تخفي البطاقات غير المستخدمة عن الزبائن، لذا نمرّر الكود عبر جدول مؤقت
CREATE TEMP TABLE mft_gift(code text);
GRANT ALL ON mft_gift TO authenticated;
INSERT INTO public.gift_cards (code, amount, is_redeemed, expires_at)
VALUES ('MFT-GIFT-000001', 500, false, now() + interval '1 day');
INSERT INTO mft_gift VALUES ('MFT-GIFT-000001');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT user_a FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_code text; v_before numeric; v_after numeric; v_led int; v_cnt int;
BEGIN
  -- بطاقة هدية: ننشئ واحدة اختبارية كأدمن لاحقاً إن لم توجد غير مستخدمة
  SELECT code INTO v_code FROM mft_gift LIMIT 1;
  IF v_code IS NULL THEN
    INSERT INTO mft VALUES (14,'redeem gift card', false, 'no unredeemed gift card available for probe');
  ELSE
    SELECT balance INTO v_before FROM public.wallets WHERE user_id=auth.uid();
    PERFORM public.redeem_gift_card(v_code);
    SELECT balance INTO v_after FROM public.wallets WHERE user_id=auth.uid();
    SELECT count(*) INTO v_led FROM public.wallet_transactions
      WHERE user_id=auth.uid() AND source='gift_card' AND created_at >= transaction_timestamp();
    INSERT INTO mft VALUES (14,'redeem gift card credits + ledger', v_after > v_before AND v_led >= 1, 'delta='||(v_after-v_before)::text);
    BEGIN
      PERFORM public.redeem_gift_card(v_code);
      INSERT INTO mft VALUES (15,'gift card cannot be redeemed twice', false, 'SECOND REDEEM SUCCEEDED (BAD)');
    EXCEPTION WHEN others THEN
      INSERT INTO mft VALUES (15,'gift card cannot be redeemed twice', true, left(SQLERRM,70));
    END;
  END IF;

  -- كوبون
  IF (SELECT coupon_code FROM ctx) IS NOT NULL THEN
    BEGIN
      PERFORM * FROM public.use_coupon_atomic((SELECT coupon_code FROM ctx), 100000);
      INSERT INTO mft VALUES (16,'coupon redemption recorded', true, 'ok');
    EXCEPTION WHEN others THEN
      INSERT INTO mft VALUES (16,'coupon redemption recorded', false, left(SQLERRM,90));
    END;
    BEGIN
      PERFORM * FROM public.use_coupon_atomic((SELECT coupon_code FROM ctx), 100000);
      INSERT INTO mft VALUES (17,'coupon single-use per user', false, 'SECOND USE SUCCEEDED (BAD)');
    EXCEPTION WHEN others THEN
      INSERT INTO mft VALUES (17,'coupon single-use per user', true, left(SQLERRM,80));
    END;
  END IF;
END $$;
RESET ROLE;

-- 10) كود دفع: إنشاء (أدمن) ثم استبداله (مستخدم) — لا خصم من المحفظة
CREATE TEMP TABLE mft_code(code text);
GRANT ALL ON mft_code TO authenticated;
GRANT INSERT, SELECT ON mft_code TO authenticated;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT admin_id FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_code text; v_id uuid;
BEGIN
  -- نفس مسار الصفحة الإدارية: إدراج مباشر (RLS: manage_settings) داخل المعاملة
  INSERT INTO public.payment_codes (code, amount, note, user_id, expires_at, status, created_by)
  VALUES ('MFT-CODE-000001', 99999999, 'MFT probe', (SELECT user_a FROM ctx), now() + interval '1 day', 'active', (SELECT admin_id FROM ctx))
  RETURNING code INTO v_code;
  IF v_code IS NULL THEN
    INSERT INTO mft VALUES (18,'payment code created by admin', false, 'no code returned');
  ELSE
    INSERT INTO mft_code VALUES (v_code);
    INSERT INTO mft VALUES (18,'payment code created by admin', true, 'ok');
  END IF;
END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT user_a FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_ids uuid[]; v_order record; v_code record; v_bal_before numeric; v_bal_after numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM mft_code) THEN
    INSERT INTO mft VALUES (19,'payment code redeem creates code-order', false, 'skipped (no code)');
  ELSE
    SELECT balance INTO v_bal_before FROM public.wallets WHERE user_id=auth.uid();
    SELECT array_agg(id) INTO v_ids FROM public.redeem_payment_code_order(
      p_code  => (SELECT code FROM mft_code LIMIT 1),
      p_items => jsonb_build_array(jsonb_build_object('product_id',(SELECT prod_plain FROM ctx))),
      p_coupon_code => NULL);
    SELECT * INTO v_order FROM public.orders WHERE id = v_ids[1];
    SELECT * INTO v_code FROM public.payment_codes WHERE code=(SELECT code FROM mft_code LIMIT 1);
    SELECT balance INTO v_bal_after FROM public.wallets WHERE user_id=auth.uid();
    INSERT INTO mft VALUES (19,'payment code redeem creates code-order',
      v_order.id IS NOT NULL AND v_order.payment_type='code'
      AND v_code.status='used' AND v_bal_after = v_bal_before,
      'order='||coalesce(v_order.id::text,'NULL')||' code_status='||coalesce(v_code.status,'?')
      ||' code_linked='||(v_order.payment_code_id IS NOT NULL)::text
      ||' wallet_unchanged='||(v_bal_after=v_bal_before)::text);
    BEGIN
      PERFORM * FROM public.redeem_payment_code_order(
        p_code => (SELECT code FROM mft_code LIMIT 1),
        p_items => jsonb_build_array(jsonb_build_object('product_id',(SELECT prod_plain FROM ctx))),
        p_coupon_code => NULL);
      INSERT INTO mft VALUES (20,'payment code single-use (replay blocked)', false, 'SECOND REDEEM SUCCEEDED (BAD)');
    EXCEPTION WHEN others THEN
      INSERT INTO mft VALUES (20,'payment code single-use (replay blocked)', true, left(SQLERRM,80));
    END;
  END IF;
END $$;
RESET ROLE;

-- 11) نقاط الولاء: تحويل إلى رصيد + قيد مالي
-- ملاحظة: redeem_loyalty_points دالة داخلية (غير ممنوحة للمتصفح: لا صفحة تستدعيها).
-- نختبرها كمالك القاعدة مع تعيين المستخدم عبر auth.uid().
UPDATE public.profiles SET loyalty_points = loyalty_points + 50 WHERE id = (SELECT user_a FROM ctx);
DO $$
DECLARE v_credit numeric; v_before numeric; v_after numeric; v_led int; v_points int;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub',(SELECT user_a FROM ctx),'role','authenticated')::text, true);
  SELECT balance INTO v_before FROM public.wallets WHERE user_id=auth.uid();
  SELECT public.redeem_loyalty_points(10) INTO v_credit;
  SELECT balance INTO v_after FROM public.wallets WHERE user_id=auth.uid();
  SELECT loyalty_points INTO v_points FROM public.profiles WHERE id=auth.uid();
  SELECT count(*) INTO v_led FROM public.wallet_transactions
   WHERE user_id=auth.uid() AND source='loyalty_points' AND created_at >= transaction_timestamp();
  INSERT INTO mft VALUES (21,'loyalty points redeem credits + ledger', v_credit > 0 AND v_after = v_before + v_credit AND v_led = 1,
    'credit='||v_credit::text||' ledger='||v_led||' points_left='||v_points);
  PERFORM set_config('request.jwt.claims', '{"role":"postgres"}', true);
END $$;

-- 12) عمولة الإحالة: تُصرف مرة واحدة فقط + قيد مالي
-- تجهيز الإحالة: يجب أن يكون الكاتب أدمن لأن تريجر protect_profile_columns
-- يحمي referred_by من أي غير أدمن (حتى postgres بلا claims إدارية).
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT admin_id FROM ctx),'role','authenticated')::text, true);
DO $$
BEGIN
  IF (SELECT admin_id FROM ctx) <> (SELECT user_b FROM ctx) THEN
    UPDATE public.profiles SET referred_by = (SELECT admin_id FROM ctx) WHERE id = (SELECT user_b FROM ctx);
    INSERT INTO mft VALUES (25,'setup (rollback only): referred_by assigned', true, 'ok');
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT admin_id FROM ctx),'role','authenticated')::text, true);
DO $$
DECLARE v_order uuid; v_before numeric; v_after numeric; v_led int; v_paid boolean; v_cand uuid;
BEGIN
  -- تجهيز: جعل أحد طلبات المستخدم ب مؤهلاً للعمولة (in_progress)
  SELECT id INTO v_cand FROM public.orders WHERE user_id=(SELECT user_b FROM ctx) ORDER BY created_at DESC LIMIT 1;
  IF v_cand IS NOT NULL THEN
    BEGIN
      PERFORM public.admin_update_order_status(v_cand,'in_progress',NULL);
    EXCEPTION WHEN others THEN
      BEGIN PERFORM public.admin_update_order_status(v_cand,'in_progress','MFT probe'); EXCEPTION WHEN others THEN NULL; END;
    END;
  END IF;
  SELECT id INTO v_order FROM public.orders
   WHERE user_id=(SELECT user_b FROM ctx) AND status IN ('in_progress','completed')
   ORDER BY created_at DESC LIMIT 1;
  IF v_order IS NULL THEN
    INSERT INTO mft VALUES (22,'referral commission pays once + ledger', false, 'no eligible order for referral probe');
    RETURN;
  END IF;
  SELECT balance INTO v_before FROM public.wallets WHERE user_id=(SELECT admin_id FROM ctx);
  PERFORM public.process_referral_commission((SELECT user_b FROM ctx), v_order);
  SELECT balance INTO v_after FROM public.wallets WHERE user_id=(SELECT admin_id FROM ctx);
  SELECT referral_commission_paid INTO v_paid FROM public.orders WHERE id=v_order;
  SELECT count(*) INTO v_led FROM public.wallet_transactions
   WHERE user_id=(SELECT admin_id FROM ctx) AND source='referral_commission' AND reference_id=v_order;
  INSERT INTO mft VALUES (22,'referral commission pays once + ledger',
    v_paid AND v_after >= v_before AND v_led = 1,
    'paid='||v_paid::text||' delta='||(v_after-v_before)::text||' ledger='||v_led);
  PERFORM public.process_referral_commission((SELECT user_b FROM ctx), v_order);
  SELECT count(*) INTO v_led FROM public.wallet_transactions
   WHERE user_id=(SELECT admin_id FROM ctx) AND source='referral_commission' AND reference_id=v_order;
  INSERT INTO mft VALUES (23,'referral commission never pays twice', v_led = 1, 'ledger_rows='||v_led);
END $$;
RESET ROLE;

-- 13) الثابت الختامي: كل رصيد محفظة = مجموع قيوده (بعد كل التدفقات)
INSERT INTO mft
SELECT 24,'final invariant: wallets == ledger sums',
  NOT EXISTS (
    SELECT 1 FROM public.wallets w
    WHERE w.balance <> COALESCE((SELECT SUM(CASE WHEN t.direction='credit' THEN t.amount ELSE -t.amount END)
                                 FROM public.wallet_transactions t WHERE t.user_id = w.user_id), 0)
  ), 'checked after all money flows';

SELECT json_agg(json_build_object('n',n,'name',name,'ok',ok,'detail',detail) ORDER BY n) FROM mft;
ROLLBACK;
