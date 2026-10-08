-- RAIZEY STORE — rollback لحواجز Edge Receipt Scan
-- هذا الملف لا يحذف receipt_scan_results أو بيانات التدقيق.
-- استخدمه فقط بعد إيقاف الواجهة الجديدة واستعادة ملفات backup.

BEGIN;

DROP TRIGGER IF EXISTS trg_payment_receipts_edge_scan_claim ON public.payment_receipts;
DROP TRIGGER IF EXISTS trg_orders_edge_scan_consumed ON public.orders;
DROP TRIGGER IF EXISTS trg_wallet_topups_edge_scan_consumed ON public.wallet_topups;

DROP FUNCTION IF EXISTS public.enforce_edge_receipt_scan_claim();
DROP FUNCTION IF EXISTS public.mark_edge_receipt_scan_consumed();

-- نحتفظ بجدول receipt_scan_results ونتائجه للتدقيق والتراجع الآمن.
COMMIT;

-- بعد ذلك استعد ملفات العميل القديمة من:
-- backups/receipt-browser-legacy-20260817/
-- وأعد endpoint Vercel القديم إلى api/verify-receipt.js إذا لزم.
