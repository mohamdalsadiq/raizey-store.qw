# process-receipt

هذه الدالة هي المسار الوحيد لفحص وتقييم صور الإيصالات. تستقبل صورة الإيصال من عميل مصادق عليه، وتحسب بصمتها داخل Edge Runtime، وتستدعي Gemini Vision من الخادم، ثم تمرر النص إلى `receipt-judge-core.ts` لاتخاذ قرار حتمي. تحفظ النتيجة في `public.receipt_scan_results` وتعيد `scanId` و`receiptHash` للواجهة.

## الأمان

يجب نشر الدالة مع **`verify_jwt = false`** (مضبوط في `supabase/config.toml`). هذا ليس تخفيفاً للأمان:

- المتصفح يرسل قبل أي POST عابر للنطاقات طلب **CORS preflight (`OPTIONS`) بلا ترويسة `Authorization`**.
- مع `verify_jwt = true` ترفض بوابة Supabase طلب preflight بـ `401 UNAUTHORIZED_NO_AUTH_HEADER` **قبل** الوصول إلى معالج `OPTIONS` داخل الدالة، فيفشل preflight ولا يُرسَل POST إطلاقاً، ولا يظهر أي شيء في `edge_logs`.
- لذلك نعطّل تحقق البوابة، والدالة نفسها تتحقق من JWT داخلياً: تقرأ `Authorization: Bearer <user-jwt>` ثم تستدعي `admin.auth.getUser(token)` وترفض بـ 401 أي طلب بلا جلسة صالحة. فالأمان محفوظ كاملاً.

إعادة النشر بعد أي تعديل (من جذر المشروع، بعد `supabase link`):

```bash
supabase functions deploy process-receipt --no-verify-jwt
```

`SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` متاحان تلقائيًا داخل بيئة Edge Function. يجب ضبط السر التالي في Supabase Dashboard ضمن Function Secrets:

```text
GEMINI_API_KEY=<قيمة مفتاح Gemini في بيئة Supabase فقط>
```

اختياريًا يمكن ضبط `RAIZEY_PUBLIC_ORIGIN` على أصل المتجر الفعلي (مثل `https://raizey-store-qw.vercel.app`، أو قائمة مفصولة بفواصل) لتقييد CORS؛ وإن تُرك فارغاً تُعيد الدالة أصل الطلب نفسه. لا تضع بعده شرطة مائلة `/`.

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
