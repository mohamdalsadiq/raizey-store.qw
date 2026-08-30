# RAIZEY STORE — Next storefront

الواجهة الجديدة للمتجر، مبنية تدريجياً بجانب الموقع الحالي حتى تكتمل مسارات الشراء والإدارة ويصبح الانتقال آمناً.

## التشغيل المحلي

```bash
cp .env.example .env.local
pnpm install
pnpm dev
```

أضف إلى `.env.local` رابط مشروع Supabase والمفتاح العام `publishable` فقط. لا تستخدم مفتاح `service_role` في هذه الواجهة.

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_PUBLISHABLE_KEY=your-public-key
```

## التحقق

```bash
pnpm lint
pnpm build
```

الصفحة الرئيسية تقرأ الأقسام والمنتجات النشطة من الخادم. إلى أن تكتمل الهجرة، تنتقل إجراءات الشراء والحساب إلى صفحات HTML الحالية حتى لا تتوقف أي وظيفة موجودة.
