# مراجع المهمة الرابعة

## متطلبات Notion

المهمة الرابعة هي تحسين `referrals.html` بصريًا مع الحفاظ على المنطق، وإضافة كود إحالة قصير من 5–6 خانات مربوط بنظام الإحالة الحالي، وإضافة خانة اختيارية في `register.html`، ثم إزالة صور أعلام الدول والاكتفاء باسم الدولة ورمز الاتصال نصيًا.

## ما تم فحصه

- `referrals.html` يعرض رابط الإحالة من `profiles.referral_code` ويقرأ `referred_by` و`referral_rewarded` ومستويات المكافآت وإشعارات الأرباح.
- `register.html` يمرر `referral_code_used` داخل `auth.signUp` metadata عند وجود `?ref=CODE`.
- `assets/js/country-codes.js` كان يستخدم `flagcdn.com` داخل زر الدولة وقائمة الدول.
- `supabase-critical-fixes-3.sql` يحمي `referral_code` و`referred_by` عبر `protect_profile_fields` ويمنع العميل من تعديلهما.
- المهمة تحتاج migration مستقلة لإضافة `referral_short_code`، وفهرس unique، وتوليد الأكواد، والتحقق الآمن عبر RPC، وربط metadata عند إنشاء profile.

## قواعد UI/UX المطبقة

ستُستخدم مهارة `.manus/skills/uiux-master/SKILL.md`: mobile-first، ألوان RAIZEY الحالية، Font Awesome، حالات focus-visible، نصوص واضحة، escape لكل النصوص الديناميكية، وتحسين التباعد دون تغيير هوية الصفحة.

## نتيجة المعاينة المحمولة

تم التقاط `task4-register-mobile.png` بعرض 393 بكسل. ظهر الشعار، عنوان التسجيل، منتقي الدولة النصي (السودان +249)، وحقل كود الإحالة الاختياري مع أيقونة Font Awesome والنص المساعد ضمن العرض دون قص أو تداخل. بقيت هوية Paper & Ember والهوامش المريحة واضحة على الهاتف.

تم التقاط `task4-referrals-mobile-real.png` بعرض 393 بكسل من نسخة معاينة مؤقتة لا تستدعي جلسة Supabase. ظهرت بطاقتا رابط الإحالة والكود القصير، وأزرار النسخ، وبطاقة شرح النظام ضمن تخطيط عمودي مريح دون خروج أفقي أو قص للنص.
