# process-receipt

هذه الدالة هي المسار الوحيد لفحص وتقييم صور الإيصالات. تستقبل صورة الإيصال من عميل مصادق عليه، وتحسب بصمتها داخل Edge Runtime، وتستدعي Gemini Vision من الخادم، ثم تمرر النص إلى `receipt-judge-core.ts` لاتخاذ قرار حتمي. تحفظ النتيجة في `public.receipt_scan_results` وتعيد `scanId` و`receiptHash` للواجهة.

## الأمان

تم نشر الدالة مع `verify_jwt = true`. يجب أن يرسل العميل جلسة Supabase Auth في ترويسة `Authorization: Bearer <user-jwt>`. لا تستخدم الواجهة مفتاح الخدمة ولا مفتاح Gemini.

`SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` متاحان تلقائيًا داخل بيئة Edge Function. يجب ضبط السر التالي في Supabase Dashboard ضمن Function Secrets:

```text
GEMINI_API_KEY=<قيمة مفتاح Gemini في بيئة Supabase فقط>
```

اختياريًا يمكن ضبط `RAIZEY_PUBLIC_ORIGIN` على أصل المتجر الفعلي بدل `*` لتقييد CORS.

## عقد الصورة

يقبل المسار `JPG` و`PNG` و`WEBP` فقط، بحد أقصى `5MB` للصورة الأساسية ولكل صورة إضافية. تُرفض MIME types غير المدعومة وBase64 غير الصالح برسالة آمنة دون إنشاء طلب. يجب أن تعرض واجهات checkout وwallet العقد نفسه للمستخدم.

## قاعدة البيانات

بعد نشر الدالة، شُغّل migration:

```text
supabase-SQL-نقل-فحص-الإيصالات-إلى-الخادم.sql
```

تربط migration كل `payment_receipts` بنتيجة scan مملوكة للمستخدم وغير منتهية، وتتحقق من البصمة والرقم والمبلغ والمزوّد والحالة قبل الحجز، ثم تعلّم scan كمستهلك بعد إدخال الطلب أو شحن المحفظة.

## Rollback

النسخة السابقة موجودة في:

```text
backups/receipt-browser-legacy-20260817/
```

وتحتوي على محرك Tesseract القديم، نواة الحكم، endpoint Vercel السابق، وبصمات SHA-256 وتعليمات التراجع. لا تُستعاد ملفات rollback إلا بعد إيقاف مسار Edge Function أو إزالة trigger migration بما يتوافق مع خطة تراجع كاملة.

## ملاحظة النشر

إذا تعذر اتصال Supabase MCP أو Dashboard، لا تُعتبر تغييرات `index.ts` منشورة تلقائياً عبر GitHub؛ يجب نشر Edge Function والتحقق من الإصدار النشط يدوياً قبل اعتماد عقد 5MB في الإنتاج.
