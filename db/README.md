# `db/` — قاعدة بيانات MEEM STORE (المصدر الوحيد للحقيقة)

## ⚠️ القاعدة الذهبية
كل تغيير على قاعدة البيانات يمرّ من **`db/migrations/`** فقط.
**لا تُطبَّق أي ملفات SQL قديمة** (النسخ السابقة أُزيلت من الشجرة وما زالت في تاريخ Git تحت `deprecated/`).
تطبيق ملف قديم = كسر الحماية المالية (تعارض نسخ الدوال، إعادة منح صلاحيات مكتوبة مباشرة...).

## التطبيق
1. افتح Supabase → SQL Editor (أو Management API `POST /v1/projects/<ref>/database/query`).
2. طبّق الملفات في `db/migrations/` **بالترتيب الزمني**، وكل ملف في **معاملة واحدة**.
3. شغّل `db/tests/security_invariants.sql` — يجب أن تكون كل النتائج `passed = true`.

## Migrations الحالية
| الملف | الوصف |
|---|---|
| `migrations/2026-10-08_security_hardening.sql` | إغلاق ثغرات حرجة/عالية + سلامة مالية + تقوية RLS/الصلاحيات |
| `migrations/2026-10-08_dead_code_cleanup.sql` | إزالة الدوال القديمة المتعارضة (`create_bank_transfer_order` ...) |
| `migrations/2026-10-08_user_cancel_order.sql` | RPC خادمي `cancel_my_order` بدل التحديث المباشر على `orders` |
| `migrations/2026-10-09_admin_reject_order.sql` | توحيد `admin_reject_order` مع القاعدة الحية (يستدعي `admin_refund_wallet(p_order_id, …)`) |
| `migrations/2026-10-09_payment_method_icons.sql` | عمود `payment_methods.icon_url` لأيقونة/شعار كل وسيلة دفع (صفحة الدفع) |
| `migrations/2026-10-13_p1_oracle_scope_and_coupon_strength.sql` | نطاق `check_tx_ref_available` لصفوف المستخدم نفسه + حد معدل موحّد، وطول كود الدفع 10، وتريجر قوة كود الكوبون (10 خانات أبجدية-رقمية) — مع `rollback/` مرافق |
| `migrations/2026-10-12_referral_prefix_meem.sql` | بادئة رمز الإحالة MEEM بدل RZY |
| `migrations/2026-10-12_banners.sql` | أساس البنر: الجدول + RLS + RPCs + bucket `banners` |
| `migrations/2026-10-12_banners_seed_slides.sql` | الشرائح الثلاث المبدئية |
| `migrations/2026-10-12_banners_repoint_assets.sql` | مسارات WebP + `alt` |
| `migrations/2026-10-12_banner_mobile_aspect.sql` | إعداد نسبة الموبايل (النسخة القديمة) |
| `migrations/2026-10-12_settings_whatsapp_number.sql` | مفتاح `whatsapp_number` في `settings` |
| `migrations/2026-10-13_banners_v2.sql` | `status` (draft/published) + نسخ + ترتيب ذرّي + تحقق صارم + مفاتيح السلايدر + `products.is_on_offer` + `offers_use_flag`، ويقيّد سياسة القراءة العامة بـ `status='published'` |
| `migrations/2026-10-13_section_category_icons.sql` | أعمدة الأيقونات + `store_sections.description` + bucket `category-icons` + RPCs + `catalog_icons_flag` |
| `migrations/2026-10-13_home_highlights.sql` | RPC `get_top_ordered_products` + `home_highlights_flag` |

**حالة التطبيق (2026-10-14):** الهجرات الاثنتا عشرة (من `2026-10-12_*` إلى `2026-10-14_*`) **مطبَّقة على القاعدة الحية** ومتحقَّق منها بالفحوص الحيّة — التفاصيل في `docs/FINAL_REPORT.md` §«جولة 2026-10-14 (ب)» و§«جولة 2026-10-14 (ج)».

## اختبارات

**حيّة على المشروع (تحتاج التوكن):**
```bash
bash db/tests/live_sql.sh --migrations        # تطبيق الهجرات بالترتيب
bash db/tests/live_sql.sh -c "select 1"       # استعلام سريع (-f لملف SQL)
bash db/tests/run_banners_security.sh         # 33 فحصًا لأمن البنر
bash db/tests/run_storefront_security.sh      # 29 فحصًا للأيقونات/الرئيسية/صحة رمز الإحالة/الملف الشخصي
bash db/tests/run_money_flow.sh               # 24 فحصًا لتدفقات المال (استدعاء فعلي داخل ROLLBACK)
bash db/tests/live_sql.sh -f db/tests/security_invariants.sql   # 23 ثابتًا: كلها passed=true
```
كل فحص يجري داخل معاملة تنتهي بـ `ROLLBACK`، فلا يلمس صفوف المشروع.

**محليّة بلا توكن:** `bash db/tests/local_sql_suite.sh` — PostgreSQL محلي + `tests/local_bootstrap.sql` (طبع القاعدة الحية بلا صفوفها) + الهجرات مرتين + الفحوص + التراجعات. `tests/run_money_flow.sh` خارج هذا التشغيل عمدًا (دواله من جولة 2026-10-08 غير الممثّلة في الطبع) ويرفض العمل هناك بـ exit 3 بدل نجاح زائف.

**اختبارا المشغّل نفسه:** `tests/probe_lib_selftest.sh` (واجهة الإدارة مقابل mock) و`tests/live_sql_selftest.sh` (المشغّل الحيّ مقابل mock، 18 فحصًا).

**فهارس الفحوص:** `tests/banners_security.sql` · `tests/storefront_security.sql` · `tests/money_flow_live.sql` · `tests/security_invariants.sql` (23 فحصًا ثابتًا: دفتر المحافظ، المنح، RLS، حراسة الأدمن، منع replay، منع الشحن بلا إيصال، سلامة التريجرات، وحدود نداء مساعدات التريجر).

**التوكن:** يُقرأ من `SUPABASE_ACCESS_TOKEN`، أو `$PROBE_TOKEN_FILE`، أو `$HOME/.raizey-audit/live_rw` (`0600`) — **لا يُوضع في المستودع ولا يُطبع**. أولوية أسماء الملفات: `live_rw` (قراءة/كتابة) ثم `live_ro` (القديم).

**اختبارات المستودع:** `npm test` (pipeline + judge)، و`python3 scripts/task10_js_syntax_check.py` لصحة سكربتات الصفحات.

## نموذج الأدلة المالية (Payment evidence model)
كل طلب يجب أن يرتبط بدليل دفع خادمي واحد على الأقل قبل أن يُكتمل:
| نوع الدفع | الدليل الإلزامي |
|---|---|
| `bank` | `receipt_id` → إيصال مُتحقق منه (`amount_verified` أو `needs_admin_check`) |
| `wallet` | قيد خصم في `wallet_transactions` مطابق للطلب |
| `code` | `payment_code_id` → رمز دفع `used` لنفس المستخدم |

أي إكمال بدون دليل يُرفض بـ`unverified_payment_evidence` إلا بـ**سبب تجاوز مكتوب** يُسجَّل في `audit_logs`.

## سلامة دفتر المحافظ
- تريجر `trg_assert_wallet_ledger` (مؤجَّل حتى COMMIT): أي تغيير في `wallets.balance` يجب أن يقابله قيد في `wallet_transactions` بنفس المعاملة.
- الأرصدة التاريخية غير المسنودة سُجّلت كقيد افتتاحي `opening_balance` (مرة واحدة).
