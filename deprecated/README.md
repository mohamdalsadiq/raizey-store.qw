# DEPRECATED — DO NOT APPLY

> **⚠️ تحذير: لا تُشغّل أي ملف في هذا المجلد في Supabase SQL Editor.**
> هذه الملفات تاريخية. المصدر الوحيد للحقيقة هو `supabase/migrations/`.
> إعادة تطبيق أي ملف هنا قد **تعيد ثغرات أمنية** تم إصلاحها (مثل نسخ `claim_payment_receipt`
> الخطرة التي تثق بـ OCR المتصفح).

## Classification (P2-DB-001, 2026-10-08)

| File | Status | Notes |
|---|---|---|
| supabase-critical-fixes-5.sql | **DANGEROUS** | Contains a `claim_payment_receipt` variant that trusts client OCR. Never apply. |
| supabase-critical-fixes-7.sql | **DANGEROUS** | Contains a `claim_payment_receipt` variant that trusts client OCR. Never apply. |
| supabase-SQL-rollback-my-last-catalog-changes.sql | **DANGEROUS** | Rollback — undoes applied changes. |
| supabase-SQL-rollback-to-legacy-catalog.sql | **DANGEROUS** | Rollback — undoes applied changes. |
| supabase-SQL-rollback-نقل-فحص-الإيصالات.sql | **DANGEROUS** | Rollback — removes receipt-scan guards. |
| supabase-SQL-المهمة-6-ربط-الفحص-الخادمي.sql | REFERENCE | Secure claim variant — canonized in migration `20261008030000`. Kept for history. |
| supabase-SQL-المهمة-*.sql (others) | LEGACY | Old task files (2,3,4,5,6-تحقق,7,35-bin) — superseded by migrations. |
| supabase-critical-fixes-{2,3,4,6,8}.sql | LEGACY | Old fix batches — superseded by migrations. |
| supabase-fix-payment-code-overload.sql | LEGACY | Overload fix — already applied, superseded. |
| supabase-security.sql | LEGACY | Old "single source of truth" — superseded by `supabase/migrations/`. |
| supabase-smart-verify-upgrade.sql | LEGACY | Superseded. |
| supabase-SQL-catalog-*.sql, *-إعادة-هيكلة-الكتالوج.sql, *-التوسعة-*.sql, *-خيارات-المنتج-*.sql, *-نقل-فحص-*.sql | LEGACY | Catalog/structural changes — superseded. |

## Rule (going forward)

- Every database change ships as a new file in `supabase/migrations/` (timestamped, additive, with rollback notes).
- Nothing in `deprecated/` is ever applied again.
- Canonical live objects are pinned with `COMMENT ON ... IS 'P<priority>-<id> ...'` markers.
