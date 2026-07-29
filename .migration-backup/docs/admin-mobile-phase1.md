# RAIZ3Y STORE — Phase 1

## الملفات المضافة

- `supabase/migrations/202607280001_admin_mobile_app_shell_phase1.sql`
- `assets/js/admin-rbac.js`
- `admin-bootstrap.html`

## ما الذي تنفذه الهجرة؟

- إنشاء جدول `store_settings` كسجل موحد لوضع الصيانة وسعر الصرف.
- إنشاء جدول `admin_permissions` بصلاحيات دقيقة ودعم `is_super_admin`.
- إنشاء جدول `admin_audit_logs` لتسجيل النشاطات الإدارية.
- إضافة دوال آمنة:
  - `is_super_admin()`
  - `has_admin_permission(permission_key text)`
  - `get_my_admin_context()`
  - `append_admin_audit_log(...)`
  - `set_store_exchange_rate(...)`
  - `set_store_maintenance(...)`
  - `upsert_admin_permissions(...)`
  - `bootstrap_super_admin()`
- تفعيل `RLS` ومنع الكتابة المباشرة على الجداول الحساسة.
- إضافة `store_settings` إلى `supabase_realtime` لاستخدام وضع الصيانة لحظياً.

## طريقة التنفيذ

1. نفّذ ملف الهجرة داخل Supabase SQL Editor أو ضمن نظام migrations المعتمد لديك.
2. سجّل الدخول بحساب يملك حالياً `profiles.role = 'admin'`.
3. افتح المسار `admin-bootstrap.html`.
4. اضغط `تهيئة الحساب الحالي`.
5. بعد نجاح التهيئة يصبح الحساب الحالي أول `Super Admin`.

## ملاحظة التوافق

- النظام الحالي ما زال يحتوي على فحص legacy عبر `profiles.role = 'admin'`.
- دالة `is_admin()` تم تحديثها لتبقى متوافقة مع النظام القديم أثناء الانتقال إلى RBAC الجديد.
- المرحلة الثانية يمكنها البدء مباشرة بالاعتماد على `admin-rbac.js` و `store_settings`.
