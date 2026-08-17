# Rollback — فحص الإيصالات قبل النقل إلى الخادم

هذه النسخة تحفظ محرك الفحص القديم الذي كان يعمل في المتصفح قبل نقل المعالجة إلى Supabase Edge Function.

## الملفات المحفوظة

- `receipt-intel.js`: محرك OCR والتحليل القديم في المتصفح.
- `receipt-judge-core.js`: نواة الحكم النصي المشتركة.
- `verify-receipt.js`: endpoint الخادمي السابق في `api/`.
- `SHA256SUMS.txt`: بصمات SHA-256 للتحقق من سلامة النسخة.

## التراجع

نفّذ الخطوات التالية بالترتيب:

1. أوقف نشر الواجهة الجديدة أو أعد آخر commit قبل النقل.
2. شغّل `supabase-SQL-rollback-نقل-فحص-الإيصالات.sql` في Supabase SQL Editor لإزالة triggers وحواجز Edge الجديدة. الملف لا يحذف جدول `receipt_scan_results` أو نتائجه.
3. أعد الملفات القديمة إلى أماكنها:

```bash
mkdir -p api
cp backups/receipt-browser-legacy-20260817/receipt-intel.js assets/js/receipt-intel.js
cp backups/receipt-browser-legacy-20260817/receipt-judge-core.js assets/js/receipt-judge-core.js
cp backups/receipt-browser-legacy-20260817/verify-receipt.js api/verify-receipt.js
```

4. أعد وسوم Tesseract والاستدعاءات القديمة في `checkout.html` و`wallet.html` إذا كان ذلك هو المطلوب، ثم شغّل verifier وادفع rollback كـ commit منفصل.

لا تحذف هذه النسخة أو جدول `receipt_scan_results` حتى اعتماد النقل الخادمي نهائيًا.
