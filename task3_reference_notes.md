# مراجع المهمة الثالثة

## مصدر المتطلبات

- صفحة المهام: https://app.notion.com/p/712da759704d43b28c9a3f5d400f686a?v=63230696521d49e9bcc397ace3577882&source=copy_link
- صفحة المهمة 3 العامة: https://www.notion.so/3be180c6b36c819b93f9e5f06adba7fa

## المتطلبات المحفوظة

تربط `wallet.html` بنفس مسار فحص `checkout.html`: استدعاء `/api/verify-receipt` أولًا، ثم fallback إلى Tesseract عبر `ReceiptIntel.analyze` عند فشل السيرفر، ثم مراجعة يدوية fail-closed. يجب أن تستخدم شحنات المحفظة نفس منطق `claim_payment_receipt` لمنع تكرار رقم العملية بين شحن المحفظة ودفع المنتجات، مع حفظ `ocr_status` وبقية بيانات الفحص. إعادة التصميم مطلوبة باستخدام Font Awesome وهوية الألوان الحالية دون إيموجي.

## المراجع البرمجية

- `checkout.html`: `serverVerify`، `runScan`، `ReceiptIntel.analyze`، وبناء `receiptPayload` ومسار `claim_payment_receipt` الاحتياطي.
- `wallet.html`: تدفق الرفع الحالي الذي يضيف `wallet_topups` مباشرة ولا يمر بفحص ذكي أو claim موحّد.
- `api/verify-receipt.js`: عقد POST يستهلك `imageBase64` و`mimeType` و`expectedAmount` و`manualRef` و`expectedAccount`، ويدعم صورة إضافية.
- `assets/js/receipt-intel.js`: `window.ReceiptIntel.analyze(file, options)` هو fallback المتصفح.
- `assets/js/receipt-judge-core.js`: محرك القرار المشترك.
- `supabase-critical-fixes-7.sql`: تعريف `claim_payment_receipt` والتحقق من التكرار عبر `orders` و`wallet_topups`.
- `supabase-critical-fixes-8.sql`: مستهلكو `claim_payment_receipt` ومسارات الطلبات الحالية.


## نتيجة المعاينة البصرية

تمت معاينة نموذج شحن المحفظة على نسخة مؤقتة بعرض المتصفح الضيق. ظهر المبلغ ووسيلة التحويل ورقم العملية ومربع رفع الإيصال وزر الإرسال داخل البطاقة دون تجاوز العرض. عناصر تقرير الفحص الجديدة مخفية حتى اختيار صورة، وسيظهر مكانها بعد الفحص دون تغيير بنية النموذج.


تم التحقق داخل Chromium من أن `RaizeyReceiptPipeline.analyze` و`RaizeyReceiptPipeline.serverVerify` و`ReceiptIntel` و`submitTopup` محمّلة، ولم يظهر خطأ JavaScript في سجل console للمعاينة.


المعاينة النهائية بعرض 393×1200 أظهرت نموذج الشحن مرتبًا: المبلغ، وسيلة التحويل، رقم العملية، رفع الإيصال، وزر الإرسال داخل بطاقة واحدة دون تجاوز الشاشة. حالة الفحص والتقرير ستظهران أسفل مربع الرفع عند اختيار صورة.
