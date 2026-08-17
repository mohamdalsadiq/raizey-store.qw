# Rollback — فحص الإيصالات قبل النقل إلى الخادم

هذه النسخة تحفظ محرك الفحص القديم الذي كان يعمل في المتصفح قبل نقل المعالجة إلى Supabase Edge Function.

## الملفات المحفوظة

- `receipt-intel.js`: محرك OCR والتحليل القديم في المتصفح.
- `receipt-judge-core.js`: نواة الحكم النصي المشتركة.
- `verify-receipt.js`: endpoint الخادمي السابق في `api/`.
- `SHA256SUMS.txt`: بصمات SHA-256 للتحقق من سلامة النسخة.

## التراجع

لإرجاع الملفات الأصلية إلى أماكنها:

```bash
cp backups/receipt-browser-legacy-20260817/receipt-intel.js assets/js/receipt-intel.js
cp backups/receipt-browser-legacy-20260817/receipt-judge-core.js assets/js/receipt-judge-core.js
cp backups/receipt-browser-legacy-20260817/verify-receipt.js api/verify-receipt.js
```

بعد ذلك يُعاد تفعيل وسوم Tesseract واستدعاء `RaizeyReceiptPipeline.analyze` القديم في `checkout.html` و`wallet.html` إذا كان ذلك هو المطلوب، ثم يُجرى الفحص الآلي قبل الرفع. لا تُحذف هذه النسخة حتى اعتماد النقل الخادمي نهائيًا.
