# `db/` — قاعدة بيانات RAIZEY STORE (المصدر الوحيد للحقيقة)

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

## اختبارات
- `tests/security_invariants.sql` — 20 فحصاً ثابتاً (دفتر المحافظ، المنح، RLS، حراسة الأدمن، منع replay، منع الشحن بلا إيصال، سلامة التريجرات...).
- اختبارات المستودع: `npm test` (pipeline + judge)، و`python3 scripts/task10_js_syntax_check.py` لصحة سكربتات الصفحات.

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
