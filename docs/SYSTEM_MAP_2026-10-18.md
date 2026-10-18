# خريطة النظام قبل اختبارات الأمن — 2026-10-18

المستودع: mohamdalsadiq/raizey-store.qw. المرجع المفحوص: 0bc7427b4f33f985ed061abcfebb604c42e4b4bb (main).
فرع العمل: security/comprehensive-audit-2026-10-18. خريطة مبنية على الملفات وmetadata الحية؛ التقارير القديمة ليست أدلة على حالة اليوم.

## التقنية والنشر
- واجهة static multipage: HTML، CSS، JavaScript؛ لا React أو Next.js في الكود الحالي.
- package.json بلا dependencies مثبتة؛ npm test يشغّل receipt pipeline / judge / category icons، وtest:edge يتطلب Bun.
- مكتبة Supabase في المتصفح من CDN @2؛ Google Fonts وFont Awesome وLucide وأصول محلية بحسب الصفحة. سيجري جرد نسخ CDN بصورة مستقلة.
- Vercel: project raizey-store-qw، Node 24.x، static hosting، headers/redirects في vercel.json. .vercelignore يحدد الملفات المرفوعة.
- نشر production dpl_ACiby5oXMckJ3fedicWtQdDu3gMJ يطابق commit أعلاه؛ عنوانه raizey-store-qw.vercel.app. النشر من Git main.
- Supabase project rglbfizqolrenwfsndyv في eu-central-1، PostgreSQL 17.6.1.155. Vercel metadata تعرض region iad1.
- مصدر migration موزع بين db/migrations وsupabase/migrations. يلزم مقارنة SQL الحي بالمصدر، لأن وجود ملف migration لا يثبت تطبيقه.

## مكونات التشغيل وحدود الثقة
1. متصفح العميل → Supabase Auth (password / email OTP / Google OAuth).
2. متصفح العميل → PostgREST/RPC باستخدام anon key أو JWT للمستخدم. anon key مفتاح عام مقصود، وليست service_role.
3. PostgREST → PostgreSQL/RLS/SECURITY DEFINER functions/triggers؛ هذه هي حدود التفويض المالي الفعلية.
4. رفع صور → Storage buckets وسياسات storage.objects.
5. process-receipt Edge Function → تحقق JWT عبر Auth → قراءة payment method من DB → Gemini OCR → receipt_scan_results بواسطة service_role → نتيجة scan للمتصفح.
6. chat-assistant Edge Function → JWT اختياري للزائر → rate limiter → سياق المنتجات وطلبات المستخدم → Gemini → نص جواب. ستُقارن النسخة المنشورة بالمصدر قبل اعتماد سلوكها.
7. Supabase Realtime يُستخدم لتحديث الواجهة بحسب الاشتراكات. cache محلي sessionStorage للقراءات، وذاكرة Edge مؤقتة لاكتشاف Gemini models.
8. الوظائف المجدولة والنسخ الاحتياطية وAuth server settings لم تثبت بعد؛ لا نفترض وجودها أو أمنها.

## نموذج البيانات
- الهوية: profiles (role, is_banned, referral fields, loyalty_points, player_ids, avatar_url)، admin_permissions.
- الكتالوج: store_sections → categories → products؛ subcategories legacy مستقلة. خيارات المنتج JSON في products.options.
- المالية: wallets، wallet_transactions، orders، wallet_topups، payment_methods، payment_codes.
- أدلة الدفع: payment_receipts، receipt_scan_results، receipt_fraud_attempts.
- العروض: coupons، coupon_redemptions، gift_cards.
- الإحالات: referral_milestones، referral_milestone_payouts، profiles.referred_by.
- الإدارة: settings، store_settings، notifications، audit_logs، admin_audit_logs.
- private.chat_rate_limits لتحديد المعدل. 26 جدولا في public وكلها تعلن RLS؛ هذا وحده لا يثبت صحة policies.
- Storage: receipts private (5 MiB)، product-images public (5 MiB)، avatars public (5 MiB)، banners public (2 MiB)، category-icons public (200 KiB). الأنواع المعلنة JPEG/PNG/WebP.
- تم حفظ inventory للأعمدة والقيود والسياسات و81 function وtriggers من الكتالوج الحي، بلا تصدير بيانات العملاء.

## المصادقة والجلسات
- register.html → signUp مع full_name/WhatsApp/referral_code_used داخل user_metadata → trigger handle_new_user → profiles/wallets.
- verify.html → verifyOtp signup + resend. login.html → signInWithPassword أو signInWithOtp/verifyOtp أو Google OAuth.
- forgot-password.html → resetPasswordForEmail → verifyOtp recovery → reset-password.html → updateUser(password).
- account.html → profile update، email update، password update/reauthentication، avatar upload، signOut محلي أو global.
- Supabase SDK يستخدم PKCE وpersistSession/autoRefreshToken مع storageKey raizey-auth؛ تخزين browser session يحتاج فحص مخاطر XSS.
- role/banned/permissions يجب أن تشتق من DB، وليس user_metadata أو عناصر HTML. حراسة صفحات الإدارة لا تعوض RLS وRPC authorization.
- account.html يحتوي enroll/challenge/verify/unenroll لعامل TOTP؛ لم يكن تسجيل الدخول يلزم جلسة AAL2 للحساب ذي العامل المُفعّل، ولذلك اختُبر هذا الحدّ على قاعدة البيانات.

## مسارات المال من النقر إلى الكتابة
- Wallet checkout: cart من browser → checkout-v2.html → create_wallet_orders_bulk → قراءة الأسعار/options/rate/margin من DB → use_coupon_atomic → wallet FOR UPDATE → debit → orders → wallet_transactions داخل نفس transaction.
- Bank checkout: اختيار payment method/reference/upload → process-receipt (server scan) → Storage receipts → create_bank_orders_bulk → تسعير DB → coupon → claim_payment_receipt → orders pending_review. اعتماد/تنفيذ الطلب بيد admin_update_order_status.
- Wallet topup: wallet.html → scan/upload → create_wallet_topup_from_receipt → claim_payment_receipt → wallet_topups pending → admin_confirm_topup → wallet credit + ledger.
- Payment code: validate_payment_code ثم redeem_payment_code_order → تحقق ملكية/حالة/صلاحية ومبلغ الكود → أسعار DB → استهلاك الكود + orders. توجد create_code_orders_bulk legacy ستفحص مستقلة.
- Gift card: wallet.html → redeem_gift_card → lock gift + mark redeemed + wallet credit + ledger.
- Loyalty: account.html → redeem_loyalty_points → خصم النقاط وإضافة رصيد وقيد.
- Refund/cancel: cancel_my_order أو admin_reject_order/admin_update_order_status → admin_refund_wallet بحسب المسار؛ يلزم تتبع مقدار رد الرصيد ومطابقته لما خُصم.
- Coupon: validate_coupon للعرض؛ use_coupon_atomic للاستهلاك مع coupon_redemptions.
- Referral: metadata عند التسجيل → referred_by؛ admin-orders.html يستدعي process_referral_commission بعد تعديل الحالة؛ award_loyalty_points trigger مرتبط بالحالة.
- Admin CRUD: صفحات admin-* → direct tables تحت RLS أو admin_* RPC → audit logs. إعداد الأسعار حالياً عبر عدة تحديثات في admin-settings.html.

## مدخلات غير موثوقة يجب فحصها
- كل product_id/option_id/quantity/field_values/field_labels/coupon/payment code/reference/file path/URL من المتصفح.
- السعر والإجمالي والخصم والرصيد والحالة وrole وamount_verified وOCR data المرسلة من المتصفح لا تُعامل كحقائق.
- scanId لا يكفي وحده: يلزم ownership/expiry/hash/claim/replay/payment method/amount binding من صف الخادم.
- Authorization JWT وOrigin وForwarded IP وContent-Length وMIME والامتداد وGemini output كلها مدخلات تحتاج تحقق يناسب مصدرها.
- الحقول المعروضة داخل innerHTML/attributes/inline handlers تحتاج معالجة حسب السياق.

## حدود الفحص المخطط
- metadata/read-only HTTP أولاً؛ SQL اختبارات داخل BEGIN/ROLLBACK باستخدام fixture accounts.
- لا حذف/تعديل لسجلات حقيقية؛ لا ضغط load test، ولا رسائل OTP إلى عملاء حقيقيين، ولا اتصالات إلى metadata/internal عبر SSRF.
- أي قرار منتج أو تغيير يكسر business rule يبقى بنداً معلّقاً؛ نشر production منفصل عن إعداد فرع الإصلاح.
