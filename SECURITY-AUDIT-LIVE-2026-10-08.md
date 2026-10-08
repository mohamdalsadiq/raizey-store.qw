# 🔒 تقرير التدقيق الأمني المباشر — RAIZEY STORE (raizey-store.qw)

**التاريخ:** 2026-10-08 · **الفرع:** freebuff/e71483281b0d3347fb4c7e37 (من main)
**نوع العمل:** فحص فقط — لم يُعدَّل ولم يُحذف أي ملف في المستودع.
**النطاق الحي:** Supabase project `rglbfizqolrenwfsndyv` (PostgreSQL 17.6، region eu-central-1) — تم الفحص عبر Management API بـPAT (قراءة فقط).
**المستودع:** 145 ملف (43 HTML، 6 JS، Edge Functions، 21 ملف SQL قديم، 10 migrations).

## 0) المنهجية والحدود
- **قراءة فقط**: كل استعلام حي داخل `BEGIN TRANSACTION READ ONLY … ROLLBACK`؛ لم يُنفَّذ أي INSERT/UPDATE/DELETE/DDL.
- تحقق حي من: `pg_proc/pg_get_functiondef` (58 دالة)، `pg_policies` (71 سياسة)، `pg_trigger` (15)، `pg_class.relacl/relrowsecurity`، `information_schema.columns/constraints`، الفهارس الفريدة، صلاحيات `anon/authenticated`، `pg_default_acl`، `pg_roles`، `pg_namespace`، `pg_publication_tables`، buckets.
- اختبار عزل RLS حي عبر `SET LOCAL role authenticated/anon` + `request.jwt.claims` (قراءة فقط) — نجح، ولم تُسجَّل أي كتابة.
- **لم تُنفَّذ أي عملية كتابة** (حتى داخل معاملة تُلغى) — لذلك كل ما يتعلق بـWITH CHECK للكتابة مُستدل عليه من نص السياسات + الصلاحيات + بيانات الإنتاج، وهو مُثبت بالدليل المذكور في كل ثغرة.
- لا يوجد فحص متصفح/UI (لا browser automation) — سلوك واجهات الأدمن مُستدل عليه من الكود + البيانات.
- المشروع نشط فعلياً: 8 مستخدمين، 29 طلباً، 9 إيصالات، 66 فحصاً ذكياً (21 مرفوضاً)، 4 بطاقات هدايا.

---

## 1) الملخص التنفيذي

| الخطورة | العدد |
|---|---|
| 🔴 حرجة | 2 |
| 🟠 عالية | 4 |
| 🟡 متوسطة | 8 |
| 🔵 منخفضة/معلوماتية | 7 |

**الحكم: ❌ غير آمن للإطلاق قبل إصلاح C1 وC2 على الأقل.**
النظام في **جوهر الدوال** محصّن بشكل جيد جداً (تسعير من القاعدة، ربط قرار الفحص بالسيرفر، قيود فريدة للإيصالات، أقفال `FOR UPDATE`، حراسة `is_admin/has_admin_permission` مثبتة حياً). الخطر الأكبر ليس في الحسابات بل في **سلامة السجل المالي** و**قابلية إنشاء رصيد محفظة بدون دفع** عبر ثغرة في RLS + دالة التأكيد + سلوك لوحة الأدمن.

---

## 2) الثغرات

### 🔴 C1 — لا يوجد سجل مالي إطلاقاً: `wallet_transactions` فارغ مع أرصدة قائمة
- **الموقع:** جدول `public.wallet_transactions` (0 صف) + `public.wallets` (8 صفوف، مجموع 82,107.80 ج.س) + `wallet.html:567`.
- **الوصف:** كل الأرصدة الحالية غير مبرَّرة بأي قيد مالي. 11 من 11 طلب محفظة "مكتمل" بلا قيد خصم، و6 طلبات شحن مؤكدة (منها 540,000 ج.س لمالك المتجر) بلا قيد إضافة.
- **الدليل:** `SELECT count(*) FROM wallet_transactions → 0`؛ `SUM(wallets.balance) = 82107.80`؛ استعلام D2: `completed_without_any_debit = 11/11`؛ D11: 6 شحنات مؤكدة.
- **الأثر:** استحالة إثبات أو تدقيق أي حركة مالية، استحالة كشف اختلاس/تلاعب داخلي، وعدم القدرة على ردّ الأموال بدقة. وأي مراجعة قانونية/محاسبية ستفشل.
- **الإصلاح:** (1) إلزام قيود مالية لكل تغيير رصيد عبر تريجر على `wallets` يرفض أي تغيير لا يقابله قيد (أو يجبر الدوال على الكتابة في `wallet_transactions`)، (2) إعادة بناء دفتر افتتاحي (opening-balance entries) موثّق من الإدارة لكل رصيد حالي، (3) منع أي تعديل مباشر على `wallets.balance` من SQL/لوحة التحكم.

### 🔴 C2 — إنشاء رصيد محفظة بدون أي دفع (شحن بلا إيصال + تأكيد بلا تحقق)
- **الموقع:** سياسة `topups_insert_own` على `public.wallet_topups` (WITH CHECK) + `public.admin_confirm_topup` (فرع `v_detected IS NULL`) + `admin-topups.html:369` + بيانات الإنتاج.
- **الوصف:** أي مستخدم مسجَّل يمكنه `POST /rest/v1/wallet_topups` وإنشاء صف شحن بمبلغ يصل **10,000,000 ج.س** بدون أي إيصال (`receipt_id = NULL`) وبلا حد لعدد الصفوف. وعندما يؤكّد المشرف الصف، تشحن `admin_confirm_topup` الرصيد **دون أي تحقق** لأنها تقارن المبلغ بـ`amount_detected` فقط إذا وُجد إيصال مرتبط. ولوحة الأدمن لا تُظهر أي تحذير عندما لا يوجد إيصال (`isMismatch=false` عند غياب `payment_receipts.amount_detected`).
- **الدليل:** نص السياسة: `CHECK (user_id = auth.uid() AND NOT is_banned() AND status='pending' AND amount > 0 AND amount <= 10000000 AND reviewed_at IS NULL AND COALESCE(amount_verified,false)=false)` — **لا شرط على `receipt_id`**؛ كود الدالة: `IF v_topup.receipt_id IS NOT NULL THEN SELECT pr.amount_detected …` (وبدون ذلك لا فحص)؛ بيانات الإنتاج: **6/6** من شحنات الإنتاج بلا إيصال وكلها `confirmed` (D11).
- **الأثر:** خلق أموال من الهواء ثم شراء منتجات فعلية من المحفظة، والأدمن سيضغط "تأكيد" لأنه لا يوجد ما يقارن به (وهو السلوك التاريخي المسجّل في نفس الجدول).
- **الإصلاح:** إلزام `receipt_id` في السياسة + إلزام `transaction_reference`، وفي الدالة: رفض التأكيد إذا `receipt_id IS NULL` أو `amount_detected IS NULL` إلا بتجاوز صريح مع سبب مُسجَّل، وإظهار تحذير أحمر في لوحة الأدمن للشحنات بلا إيصال.

### 🟠 H1 — إحراق/حجز أرقام عمليات الدفع بشكل جماعي (DoS على المدفوعات)
- **الموقع:** `public.claim_payment_receipt` (فرع `v_scan_id IS NULL`) + الفهارس الفريدة `uq_payment_receipts_tx_norm` / `payment_receipts_tx_ref_norm_uniq` + `public.check_tx_ref_available` (ممنوحة لـauthenticated).
- **الوصف:** أي مستخدم مسجَّل يستطيع استدعاء `claim_payment_receipt` برقم عملية **مختلق** (6 خانات+) وبصمة SHA-256 وهمية (64 hex) بدون أي `edge_scan_id` → تُخزَّن صف في `payment_receipts` يحتل الرقم بشكل دائم (قيد فريد) → العميل الحقيقي لن يستطيع استخدام رقم عمليته أبداً (`duplicate_transaction_ref`). أرقام العمليات البنكية قصيرة/تسلسلية ويمكن تعدادها عبر `check_tx_ref_available`. لا يوجد أي حد معدّل على الدالة.
- **الدليل:** كود الدالة (الفرع بدون فحص: تُستبدل قيم المتصفح بـNULL ويُقبل الصف بـ`needs_review`)، الفهارس الفريدة في `14_indexes.json`، ودليل واقعي: **2 من 9** إيصالات في الإنتاج "معلّقة" بلا أي طلب/شحن مرتبط (D4).
- **الأثر:** تعطيل قدرة العملاء على الدفع (حجب نطاق من أرقام العمليات)، تشويش سجلات الإيصالات، وتحويل مسار الدعم إلى فوضى — قابل للأتمتة بسكربت بسيط.
- **الإصلاح:** اشتراط `edge_scan_id` صالح (من `receipt_scan_results` الخاص بنفس المستخدم مع تطابق البصمة وغير مستهلك) لكل إدراج إيصال إضافي `needs_review`، أو تقييد الإدراج غير الموثّق بحد معدّل (5/ساعة/مستخدم) + إضافة `receipt_scan_results` كشرط إلزامي. الأفضل: لا يُنشأ صف إيصال إلا بعد فحص خادمي ناجح.

### 🟠 H2 — طلبات بنكية "مكتملة" دون أي تحقق من الدفع (9 من 10)
- **الموقع:** `public.orders` (بيانات إنتاج) + مسار `admin_update_order_status('completed')`.
- **الوصف:** لا يوجد أي قيد تقني يمنع إكمال طلب بنكي غير مُتحقق (`amount_verified=false` / `ocr_status<>'passed'` / بلا `receipt_id`). الضابط الوحيد هو انتباه المشرف.
- **الدليل:** D3: `bank_completed=10, no_receipt_id=6, not_verified=9, not_passed=9`. ومسار التأكيد في `admin-orders.html` لا يفرض فحصاً.
- **الأثر:** تسليم منتجات مقابل إيصالات مزيفة/ناقصة إذا أخطأ المشرف أو تم استغلال انشغاله.
- **الإصلاح:** في `admin_update_order_status` (وعند "completed"): ارفض الطلبات البنكية التي `receipt_id IS NULL` أو `amount_verified IS NOT TRUE` إلا بتجاوز مُسجَّل مع سبب، واعرض إنذاراً في الواجهة.

### 🟠 H3 — تريجر السعر الحيّ يشير إلى أعمدة غير موجودة (حماية ميتة + تعطّل مسار legacy)
- **الموقع:** `public.verify_order_price_before_insert()` (السطر `IF NEW.payment_method = 'bank_transfer' AND NEW.tx_ref IS NOT NULL`) — لا يوجد عمود `payment_method` ولا `tx_ref` في `public.orders` (الأعمدة الفعلية `payment_type` و`transaction_reference`).
- **الوصف:** أي إدراج مباشر في `orders` من غير مسار "trusted"/أدمن يفشل بخطأ `42703`، وهذا يعني: (أ) سياسة `orders_insert_own` ومنح INSERT/UPDATE للمستخدمين بلا فائدة (حماية بالعمق مفقودة)، (ب) فحص الإيصال داخل التريجر لا يعمل أبداً، (ج) مسار الدفع الاحتياطي القديم في `checkout-v2.html:1728‑1790` (claim ثم إدراج مباشر) **يفشل حالياً** — أي أن أي خلل في RPC الأساسي يُسقط الدفع البنكي بالكامل.
- **الدليل:** `pg_get_functiondef` الكامل + قائمة الأعمدة الحية + إثبات PL/pgSQL غير مُتلِف: `DO $$ DECLARE r public.orders; BEGIN PERFORM r.payment_method; END $$;` → `ERROR 42703: record "r" has no field "payment_method"` (وكذلك `tx_ref`).
- **الأثر:** تعطّل مرونة الدفع (single point of failure)، وحماية مزدوجة مفقودة.
- **الإصلاح:** تصحيح الأسماء أو حذف الفرع القديم، ثم **سحب** صلاحيات INSERT/UPDATE على `orders` من `authenticated` والاعتماد كلياً على الـRPCs (وهو الوضع الفعلي اليوم).

### 🟠 H4 — أكواد الإحالة قابلة للتعداد من الزوار (4096 احتمالاً) + تصادم
- **الموقع:** `public.generate_referral_short_code()` ('RZY' + 3 خانات hex = 16³ = 4096) + `public.validate_referral_short_code` (ممنوحة لـanon) + `handle_new_user`/`apply_referral_signup_metadata`.
- **الوصف:** يستطيع أي زائر (بدون تسجيل) تعداد كل أكواد الإحالة تقريباً (4096 طلباً فقط)، واستخدام كود صالح للتسجيل لتحصيل خصم الإحالة، كما أن فضاء الأكواد صغير جداً → تصادم حتمي مع نمو المستخدمين (50% عند ~75 مستخدماً) → إسناد إحالات لأشخاص خاطئين.
- **الدليل:** كود التوليد (3 خانات فقط) + منح anon للدالة + اختبار حي: استدعاء anon نجح وأعاد `not_found` لكود غير موجود (أي أنها تعمل كـoracle).
- **الأثر:** إساءة مالية (خصومات متكررة عبر حسابات وهمية)، إسناد عمولات خاطئ.
- **الإصلاح:** أكواد 8–10 خانات Base32، وربط الدالة بـrate limit، وسحب صلاحية anon (تُستخدم فقط قبل التسجيل — إن لزم، حصرها بـ`anon` مع حد صارم + CAPTCHA في التسجيل).

### 🟡 M1 — `pg_stat_statements` مقروء من anon/authenticated (تسريب استطلاعي داخلي)
- **الموقع:** `extensions.pg_stat_statements` (+ دوالها) — منح PUBLIC EXECUTE.
- **الدليل:** كـanon: 582 صفاً ظاهراً، **555 منها لأدوار أخرى**؛ كـauthenticated: 583 صفاً، 258 من `service_role/postgres`. (لم أحصِ أي نص سري: 0 أرقام طويلة/0 UUID/0 بريد/0 أكواد — أي أن القيم مُعَيّرة، لكن البنية كاملة مكشوفة).
- **الأثر:** خريطة كاملة للـschema/الدوال/الجداول ومعدلات الاستخدام — تسهيل قوي لأي مهاجم.
- **الإصلاح:** `REVOKE SELECT ON extensions.pg_stat_statements FROM anon, authenticated;` + `REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements(boolean) FROM PUBLIC;`

### 🟡 M2 — سجل المحفظة مكسور للمستخدمين (`wallet_transactions` بلا منح SELECT)
- **الدليل:** `has_table_privilege('authenticated','public.wallet_transactions','SELECT') = false` بينما `wallet.html:567` يقرأ الجدول، وسياسة `wallet_tx_select_own` موجودة أصلاً.
- **الإصلاح:** `GRANT SELECT ON public.wallet_transactions TO authenticated;` (السياسة تتكفل بالعزل) + ربطه بإصلاح C1.

### 🟡 M3 — `validate_payment_code` / `validate_coupon`: oracles بلا حد معدل
- **الأثر:** تعداد أكواد الدفع (13 خانة بصيغة RZY-XXXX-XXXX) والكوبونات (5 خانات) — احتمال نظري منخفض للنجاح لكنه بلا أي كلفة على المهاجم.
- **الإصلاح:** استخدام `consume_chat_rate_limit('validate:'||uid, 10, 3600)` داخل الدالتين.

### 🟡 M4 — ضجيج السجلات: `report_fraud_alert` و`log_receipt_fraud_attempt` بلا حد
- **الدليل:** 49 صفاً في `receipt_fraud_attempts` و84 في `audit_logs` (12 منها `customer_report`).
- **الإصلاح:** حد معدل لكل مستخدم + حد أقصى للصفوف اليومية.

### 🟡 M5 — `chat-assistant` بلا تحقق JWT (verify_jwt=false)
- **الدليل:** إعداد المشروع: `chat-assistant verify_jwt=false` (والجيد: `process-receipt verify_jwt=true`).
- **الأثر:** إساءة تكلفة LLM؛ الحد الحالي للزوار مبني على IP (`clientAddress`)، وهو قابل للتزوير عبر ترويسات الوكيل.
- **الإصلاح:** حد أدنى أكثر صرامة للزوار + Turnstile/Cloudflare، أو اشتراط تسجيل الدخول.

### 🟡 M6 — مفتاح/كود الكوبون قصير (5 خانات) مع oracle
- **الدليل:** `min(length(code)) = 5` لجدول `coupons`.
- **الإصلاح:** توليد أكواد عشوائية 8+ خانات وتسجيل من أنشأها.

### 🟡 M7 — إيصالات معلّقة (2) وتكرار مشتبه به
- **الدليل:** D4: 2 من 9 إيصالات بلا ارتباط بأي طلب/شحن — تؤكد مسار H1.
- **الإصلاح:** تقرير دوري عن الإيصالات غير المرتبطة + حذف أتمتة قديمة بعد الإصلاح.

### 🟡 M8 — التسجيل مفتوح بلا CAPTCHA
- **الدليل:** `disable_signup=false, security_captcha=false, rate_limit_email_sent=30/h` (والجيد: `mailer_autoconfirm=false` — تأكيد البريد مطلوب ✓).
- **الأثر:** إنشاء حسابات وهمية لصيد الخصومات/الإحالات.
- **الإصلاح:** تشغيل CAPTCHA (Turnstile) أو تقييد التسجيل بدعوة/تأكيد يدوي.

### 🔵 L1 — منح PUBLIC EXECUTE على دوال أدمن
`admin_confirm_topup`, `admin_refund_wallet`, `verify_privilege_model`, `generate_order_code`, `set_order_code`, `touch_subcategories_updated_at`, `normalize_tx_ref`. الحراسة الداخلية مثبتة حياً (كل محاولات الاستدعاء من مستخدم عادي/زائر رجعت `access_denied` أو `ADMIN_REQUIRED`) لكن المنح نفسه يجب سحبه:
`REVOKE EXECUTE ON FUNCTION public.admin_confirm_topup(uuid,text) FROM PUBLIC;` … إلخ.

### 🔵 L2 — منح جداول زائدة (دفاع بالعمق مفقود)
`authenticated` يملك INSERT/UPDATE/DELETE على 20+ جدولاً حتى مع غياب سياسة كتابة (مثل `wallets` و`orders`). الحماية اليوم تعتمد كلياً على RLS؛ سحب المنح غير المستخدمة يقلل مساحة الخطأ المستقبلية.

### 🔵 L3 — `verify_privilege_model()` مكشوفة للعامة (دالة اختبار داخلية)
### 🔵 L4 — ملفات `deprecated/*.sql` (21 ملفاً) بها نسخ متضاربة من نفس الدوال — خطر تطبيق خاطئ لاحقاً؛ يُنصح بأرشفتها وتوثيق «DO NOT APPLY».
### 🔵 L5 — `next-storefront/` لا تستدعي أي RPC للطلبات (نسخة/إعادة كتابة غير مستخدمة) — كود ميت يضاعف مساحة المراجعة.
### 🔵 L6 — أعمدة `orders` القابلة للتعيين عند الإدراج المباشر (`ocr_status`, `amount_verified`, `review_reason`) غير محميّة بسياسة ولا تريجر — غير مستغلة حالياً لأن الإدراج المباشر معطّل (H3)، لكنها فجوة يجب سدها عند أي إصلاح.
### 🔵 L7 — معلوماتية: `supabase_realtime` تضم `orders/wallet_topups/notifications/store_settings` — مقبول لأن RLS مفعّل على كلها وسياساتها مقيّدة بالمالك/الأدمن.

---

## 3) ما تم فحصه وثبتت سلامته (بكيف تأكدت)

1. **تسعير الطلبات من الخادم**: كل مسارات الإنشاء (`create_bank_orders_bulk`, `create_wallet_orders_bulk`, `create_wallet_order`, `redeem_payment_code_order`, `create_code_orders_bulk`) تحسب السعر من `products.options` في القاعدة، وتفرض `option_required` للمنتجات ذات الخيارات، وترفض `price_usd <= 0`، وتستخدم `v_rate/v_margin` من `settings`. → **ثغرة "تزوير المبلغ" في التقرير المبدئي غير موجودة حياً**.
2. **عدم إعادة استخدام الإيصال**: قيود فريدة `uq_payment_receipts_tx_norm` و`uq_payment_receipts_hash` + `unique_orders_receipt_hash` + `unique_wallet_topups_ref` + ربط قرار الفحص بـ`receipt_scan_results` (تطابق `user_id` و`receipt_hash`، انتهاء 30 دقيقة، `claimed_at` مرة واحدة) + `unique_violation` مُعالج داخل الدالة. → التجربة المزدوجة غير ممكنة عبر المسار الشرعي.
3. **عزل RLS**: كعميل حقيقي: `orders 0`, `profiles 1`, `wallets 1`, `payment_receipts 0`, `wallet_topups 1`, `settings 3 مفاتيح فقط`, `coupons 0`, `audit_logs 0`, `admin_permissions 0`, `gift_cards 0`, `receipt_fraud_attempts 0` → **لا تسريب بين المستخدمين**. وكأدمن يرى الكل (29 طلباً/8 ملفات/84 سجلاً).
4. **لا كتابة مباشرة للمستخدمين**: لا سياسة INSERT/UPDATE على `wallets` و`wallet_transactions` و`payment_receipts`؛ كل الحركة عبر دوال SECURITY DEFINER مع أقفال `FOR UPDATE` وفحص رصيد.
5. **حراسة دوال الأدمن**: اختبار حي لكل من `admin_refund_wallet`, `admin_confirm_topup`, `append_admin_audit_log`, `set_store_maintenance`, `upsert_admin_permissions` من حساب عميل ومن زائر → رجعت `access_denied`/`ADMIN_REQUIRED`/`42501` (لا تنفيذ).
6. **الكوبونات**: `use_coupon_atomic` بقفل صف + قيد فريد `(coupon_id,user_id)` + عدّاد استخدامات + تاريخ صلاحية + حد أدنى للطلب.
7. **بطاقات الهدايا**: حد 10 محاولات/ساعة لكل مستخدم + قفل صف + تحديث شرطي `is_redeemed=false` + قيد فريد على الكود (12 خانة) + قيد FRAUD.
8. **أكواد الدفع**: قفل الصف + تحديث شرطي `status='active' AND used_by IS NULL` (يستحيل الاستخدام المزدوج) + إلزام أن قيمة الرمز تغطي الإجمالي.
9. **حماية حقول المستخدم**: تريجرات `protect_profile_fields/columns/insert` الحيّة تحمي `role/is_banned/loyalty_points/referral_*` — **النقاط المعلّقة في التقرير المبدئي مُغلَقة فعلاً**.
10. **التخزين**: bucket `receipts` **خاص** (public=false) وسياسات الملفات تُلزم `foldername = auth.uid()`؛ `avatars` عام (مقصود) و`product-images` للكتابة أدمن فقط. تحقق حي: 0 حالة عدم تطابق ملكية في مجلدات المستخدمين.
11. **الأسرار**: جدول `settings` يعرض 3 مفاتيح فقط عبر RLS، ولا أسرار فيه (10 مفاتيح أعمال)؛ `store_settings` بلا أسرار؛ لا مفاتيح في الواجهة؛ `process-receipt` بـ`verify_jwt=true`؛ محتوى `pg_stat_statements` لا يحوي قيماً حرفية.
12. **الإيصالات المرفوضة/الاحتيال**: 66 فحصاً، 21 مرفوضاً، 49 محاولة مسجّلة (`ref_mismatch_blocked`, `reject_amount_mismatch`, …) → منظومة الكشف تعمل.
13. **الدوال المفقودة**: `admin_reject_topup` و`append_admin_audit_log` **موجودتان حياً** (نقيض ما ورد في التقرير المبدئي المبني على المستودع).
14. **الإعدادات العامة**: تأكيد البريد مطلوب، JWT ساعة واحدة، لا `USING(true)` على الجداول الحساسة (تحقق آلي عبر `verify_privilege_model` + قراءة 71 سياسة).

---

## 4) توصيات عامة مرتبة بالأولوية

1. سدّ C2 فوراً (سياسة + دالة + واجهة) — يوم واحد.
2. إنشاء دفتر مالي افتتاحي وإلزام القيود لكل حركة (C1) — قبل أي إطلاق.
3. إلزام التحقق الخادمي للطلبات البنكية عند الإكمال (H2).
4. تقييد `claim_payment_receipt` بفحص خادمي إلزامي + حد معدل (H1).
5. تصحيح تريجر السعر وسحب INSERT/UPDATE من `orders` (H3).
6. أكواد إحالة أطول + إزالة الوصول المجهول + CAPTCHA (H4/M8).
7. تشغيل مراقبة يومية: إيصالات معلّقة، شحنات بلا إيصال، طلبات مكتملة بلا تحقق.
8. تنظيف المنح الزائدة و`pg_stat_statements` وPUBLIC EXECUTE (M1/L1/L2).
9. فصل بيئة الاختبار عن الإنتاج (بيانات الإنتاج تحتوي آثار اختبار).
10. أرشفة `deprecated/` و`next-storefront/` وتوثيق النسخة الحيّة الوحيدة.
11. تفعيل نسخ احتياطي/نقطة استعادة + مراجعة صلاحيات المفتاح الإداري بشكل دوري.

---

## 5) ملحق: SQL إصلاح جاهز (تحتاج مراجعة قبل التطبيق)

```sql
-- (1) C2: منع شحن بلا إيصال
ALTER TABLE public.wallet_topups ALTER COLUMN receipt_id SET NOT NULL;  -- بعد تنظيف
DROP POLICY IF EXISTS topups_insert_own ON public.wallet_topups;
CREATE POLICY topups_insert_own ON public.wallet_topups FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid() AND NOT public.is_banned()
  AND status = 'pending' AND amount > 0 AND amount <= 500000
  AND reviewed_at IS NULL AND COALESCE(amount_verified, false) = false
  AND receipt_id IS NOT NULL AND transaction_reference IS NOT NULL
);
-- داخل admin_confirm_topup: ارفض بلا إيصال
-- IF v_topup.receipt_id IS NULL OR v_detected IS NULL THEN
--   IF p_override_reason IS NULL OR btrim(p_override_reason) = '' THEN
--     RAISE EXCEPTION 'topup_requires_verified_receipt'; END IF;
--   v_overrode := true; END IF;

-- (2) H3: تصحيح التريجر
-- IF NEW.payment_type = 'bank' AND NEW.transaction_reference IS NOT NULL THEN
--   SELECT * INTO v_receipt FROM payment_receipts
--    WHERE tx_ref_norm = public.normalize_tx_ref(NEW.transaction_reference)
--      AND user_id = auth.uid() AND ocr_status NOT IN ('reject','review')
--    FOR UPDATE;
--   IF NOT FOUND THEN RAISE EXCEPTION 'receipt_not_verified_for_order'; END IF; END IF;
REVOKE INSERT, UPDATE ON public.orders FROM authenticated;  -- الاعتماد على RPCs

-- (3) H1: إلزام الفحص الخادمي + حد معدل داخل claim_payment_receipt
-- IF v_scan_id IS NULL THEN RAISE EXCEPTION 'receipt_scan_required'; END IF;
-- PERFORM public.consume_chat_rate_limit('claim:'||auth.uid()::text, 15, 3600);

-- (4) M1: إغلاق pg_stat_statements
REVOKE SELECT ON extensions.pg_stat_statements FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements(boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION extensions.pg_stat_statements_info() FROM PUBLIC;

-- (5) M2: إصلاح سجل المحفظة
GRANT SELECT ON public.wallet_transactions TO authenticated;  -- السياسة wallet_tx_select_own تكفي

-- (6) L1: سحب PUBLIC من دوال الأدمن
REVOKE EXECUTE ON FUNCTION public.admin_confirm_topup(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_refund_wallet(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_privilege_model() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.generate_order_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_order_code() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.touch_subcategories_updated_at() FROM PUBLIC;

-- (7) H4: أكواد إحالة أقوى (استبدال منطق التوليد بـ8 خانات Base32) + إزالة anon
REVOKE EXECUTE ON FUNCTION public.validate_referral_short_code(text) FROM anon;

-- (8) H2: منع إكمال طلب بنكي غير مُتحقق داخل admin_update_order_status
-- IF v_status='completed' AND v_order.payment_type='bank'
--    AND (v_order.receipt_id IS NULL OR v_order.amount_verified IS NOT TRUE) THEN
--   RAISE EXCEPTION 'unverified_bank_order'; END IF;

-- (9) C1: قيد سلامة الدفتر (اختياري لكن فعّال)
CREATE OR REPLACE FUNCTION public.guard_wallet_balance() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.balance IS DISTINCT FROM OLD.balance
     AND COALESCE(current_setting('raizey.wallet_ledger_ok', true), '') <> 'on' THEN
    RAISE EXCEPTION 'wallet_balance_change_requires_ledger_entry';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_guard_wallet_balance BEFORE UPDATE ON public.wallets
FOR EACH ROW EXECUTE FUNCTION public.guard_wallet_balance();
```

---

## 6) ما تبقّى خارج نطاق هذا الفحص
- اختبار كتابة فعلي (مرفوض بحسب قاعدة «فحص فقط») — سلوك WITH CHECK مُثبت من نص السياسات + الصلاحيات + بيانات الإنتاج.
- فحص متصفح/UI حقيقي لواجهات الأدمن (لا يوجد browser automation في البيئة).
- مراجعة إعدادات Vercel/Cloudflare والنسخ الاحتياطي وقواعد WAF (خارج القاعدة والمستودع).
