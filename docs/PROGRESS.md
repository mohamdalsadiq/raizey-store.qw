# MEEM STORE — حالة العمل (PROGRESS)

آخر تحديث: 2026-10-14 · الفرع الحالي: `meem-rebrand` · الفرع الأساسي: `main` (لم يُمسّ)

هذا الملف يشرح **ما انتهى، وما بقي، وكيف تكمل** لو توقّف العمل في منتصف الطريق.
التفاصيل والأدلة الكاملة في `docs/FINAL_REPORT.md`.

---

## 1. كيف تشغّل المشروع محليًا

```bash
npm install                                    # لا يعتمد على أي حزمة إنتاجية
npx serve . -l 3000                            # أو: npm run dev
```

فحوص الجودة (تحتاج متصفح Playwright، وهو أداة تطوير فقط وليست حزمة للموقع):

```bash
npm i --no-save playwright && npx playwright install chromium
# على هذه الـ VM لا صلاحية root: مكتبات و خطوط كروميوم مستخرجة تحت ~/local-libs
# وشغّل الجلسة عبر:  source ~/work/pwenv.sh
node scripts/ui_smoke.mjs                      # 36 صفحة × وضعين — لازم 72/72
node scripts/round_checks.mjs                  # الحقول + الـ fallback + لقطات الهيرو
node scripts/banners_check.mjs                 # بنر الصفحة الرئيسية — لازم صفر ملاحظات
node scripts/offers_check.mjs                  # صفحة العروض — لازم صفر ملاحظات
python3 scripts/task10_static_audit.py         # الثابت الحالي: 77 ملاحظة (خط أساس HEAD)
python3 scripts/task10_js_syntax_check.py      # كل السكربتات المدمجة تُحلَّل
npm test                                       # 0 فشل
```

فحوص SQL (كل فحص داخل معاملة تنتهي بـ ROLLBACK — لا تلمس أي صف):

```bash
bash db/tests/probe_lib_selftest.sh            # اختبار المشغّل نفسه (الواجهتان) — لازم: self-test OK
bash db/tests/local_sql_suite.sh               # بلا توكن: PostgreSQL محلي + الهجرات + الفحوص + التراجعات
                                               # لازم: self-test OK · 33/33 · 24/24 · RESULT: OK
# على القاعدة الحية (بعد تطبيق الهجرات، ولا يطبع أي سر):
SUPABASE_ACCESS_TOKEN=... bash db/tests/run_banners_security.sh      # 33 فحصًا
SUPABASE_ACCESS_TOKEN=... bash db/tests/run_storefront_security.sh   # 24 فحصًا
```

لتشغيل المحلي: PostgreSQL من حزمة `pgserver` (لا تحتاج root):

```bash
python3 -m venv ~/work/pgvenv && ~/work/pgvenv/bin/pip install pgserver   # مرة واحدة
# مفاتيح مساعدة: MEEM_KEEP_PG=1 (اترك الخادم يعمل) · MEEM_SKIP_ROLLBACK=1 · MEEM_PGDATA/MEEM_PGSOCK/MEEM_PGPORT
```

---

## 1.b جولة 2026-10-12 (المسائية) — ما أُنجز الآن وما تعطّل

### أُنجز وتحقّق منه

| # | العمل | الدليل القابل للتشغيل |
|---|---|---|
| 10 | أيقونة بوت المساعد رجعت أيقونة Lucide الوظيفية `#i-bot` (كانت حرف M)؛ الألوان فقط تغيّرت لهوية MEEM (ذهبي + أيقونة زرقاء داكنة) | `assets/js/meem-assistant.js`، لقطة `ui-shots/round/hero-desktop-1440.png` |
| 11 | مكوّن الحقل الموحّد: الأيقونة `inset-inline-start` والـ input له `padding-inline: 46px !important` وأيقونة الإجراء `inset-inline-end` — أصلح تداخل الأيقونة مع الـ placeholder | `assets/css/meem.css` (كتلة «unified icon field»)، `scripts/round_checks.mjs` |
| 12 | مثال كود الإحالة صار `MEEM7K2P9QMZ` (كان `RZY482` = الاسم القديم) + migration لتبديل بادئة المولّد إلى MEEM مع rollback | `register.html`، `db/migrations/2026-10-12_referral_prefix_meem.sql` |
| 13 | WebP البنرات في المكان المعتمد `assets/banners/banner-N-{desktop,mobile}.webp` (72–131KB كلها <300KB) + migration لإعادة توجيه الصفوف وضبط alt_text | `scripts/build_banner_assets.py`، `db/migrations/2026-10-12_banners_repoint_assets.sql` |
| 14 | الـ fallback صار تدرّجًا أزرق + الشعار (CSS فقط) مع بقاء النصوص الحيّة، وحتى لو فشلت صورة شريحة لا تظهر أيقونة صورة مكسورة ولا نص بديل | `assets/js/banners.js` (`error` handler + `defaultSlide`)، `assets/css/meem.css` (`.mm-slide-fallback`)، لقطة `ui-shots/round/fallback-1440.png` |
| 15 | نسبة بنر الموبايل صارت إعدادًا عامًا في `settings` (`banner_mobile_aspect`، الافتراضي `3:4`) بخيارات 3:4/4:5/1:1/4:3 ومعاينة حيّة داخل `admin-banners.html`؛ الديسكتوب ثابت 8:3 وكل الشرائح تتبع نفس النسبة | `admin-banners.html`، `assets/js/banners.js` (`applyAspect`)، `db/migrations/2026-10-12_banner_mobile_aspect.sql` |

فحوص نُفّذت الآن على هذه التغييرات (كلها خضراء):

- `node scripts/round_checks.mjs` → **passed**: حشو الأيقونة ≥41px عند 320/360/390/768 على login/register/forgot/reset/verify، والـ fallback بلا صورة مكسورة، ونسبة الهيرو 8:3 ديسكتوب و3:4 موبايل.
- `node scripts/banners_check.mjs` → **passed** (صفر ملاحظات).
- `node scripts/ui_smoke.mjs` → **72/72**.
- `npm test` → **54 passed / 0 failed**. `task10_js_syntax_check.py` → 70/70. `task10_static_audit.py` → **77 = خط الأساس** (لا ملاحظات جديدة).
- اللقطات: `ui-shots/round/` (hero 1440 و390، login/register عند 320/360/390/768، fallback).

### متوقّف (سبب صريح)

- **إعادة اختبار تدفقات المال على القاعدة الحية (أهم بند متبقٍّ)**: لا وصول للقاعدة الآن — ملف التوكن `~/.raizey-audit/live_ro` غير موجود بعد إعادة تهيئة الـ VM، ولا يوجد أي ملف مفاتيح آخر. المطلوب: `SUPABASE_ACCESS_TOKEN` (أو إعادة إنشاء الملف) لأشغّل كل المسارات داخل ROLLBACK.
- **تطبيق الـ migrations الثلاث الجديدة** (بادئة الإحالة، نسبة بنر الموبايل، إعادة توجيه مسارات البنرات) يحتاج نفس الوصول.

### ملاحظة على تقرير الأمس

قرار ارتفاع الموبايل 3:4 **صحيح ولم يُرجع**؛ صور الموبايل فعلًا 3:4 (1086×1448) ولم تُقتص. وتحقّقنا الآن أن صور البنرات الست موجودة فعلًا وتُخدم بنجاح محليًا (`naturalWidth` > 0).

## 2. ما انتهى (بأدلّته)

| # | العمل | الدليل |
|---|---|---|
| 1 | دفعة التصليب الأمني والقاعدة والـ Edge (شغل سابق، مدموج في `hardening-complete`) | `git log main..hardening-complete` = `cfcfa66` |
| 2 | تسمية MEEM + لوحة الألوان + التوكنز + الخطوط + الأيقونات (شغل سابق) | `6e89a4c` … `337a6fc` |
| 3 | الشعار الحقيقي (الصور المرفوعة) مقصوص ومولَّد ومربوط بكل صفحة، وحذف كل نسخة مرسومة | `f9f8869`, `a978285`, `05dff43` |
| 4 | **بنرات الصفحة الرئيسية**: جدول + RLS + RPCs أدمن + تدقيق + bucket + 3 شرائح | `db/migrations/2026-10-12_banners*.sql`، `scripts/banners_check.mjs` |
| 5 | **كاروسيل حقيقي** بـ Swiper 11.2.10 محلي (مخزّن في `assets/vendor/swiper`) على `index.html` | `assets/js/banners.js`، لقطات `ui-shots/banners/` |
| 6 | **صفحة إدارة البنرات** (إضافة/تعديل/حذف/ترتيب/تفعيل + معاينة + قص داخل المتصفح) | `admin-banners.html` |
| 7 | **صفحة العروض** `offers.html` من `compare_at_price_usd` (بدون أي تغيير في منطق الأسعار) | `scripts/offers_check.mjs` |
| 8 | رقم واتساب صار بيانات في `settings` بدل رقم مكتوب يدويًا | `db/migrations/2026-10-12_settings_whatsapp_number.sql` |
| 9 | إزالة Sentry (كان أصله محجوبًا بـ CSP فلا يرسل شيئًا) | `280efd5` + فحص CSP في `vercel.json` |

## 3. ما بقي (مرتّبًا بالأولوية)

1. **إعدادات الأمان المفتوحة** — انظر الجدول الكامل في `docs/FINAL_REPORT.md`:
   حد معدل موحّد على `validate_coupon` / `validate_payment_code` / `check_tx_ref_available` /
   `report_fraud_alert` / `log_receipt_fraud_attempt`، وطول كود الكوبون (حاليًا 5 خانات،
   المطلوب 10)، وCSP (`'unsafe-inline'`)، وCAPTCHA للتسجيل.
2. **إعادة اختبار تدفقات المال** على القاعدة الحية داخل ROLLBACK (القسم 5 من المرحلة 1)
   لم تُنفَّذ بعد. هذا أهم بند متبقٍّ.
3. **المرحلة 4 (الأقسام والرئيسية والـ UI)** — **نُفّذت** (انظر القسم 7.ج): شبكة عمودين على الموبايل، وصف اختياري، صف أيقونات، «الأكثر طلبًا»/«الجديد» من مصادر حقيقية، بلا بيانات وهمية.
4. **المرحلة 5 (التدقيق النهائي من الصفر)** — **نُفّذت**: `ui_smoke` 72/72 على 36 صفحة × وضعين، و`task10_static_audit` = خط الأساس، وفحص RAIZEY/RZY نظيف.
5. نشر الـ Edge Functions من المستودع وضبط CORS على دومين الإنتاج + نمط preview —
   يحتاج قرارك/مفتاحك.

## 4. خطوات يدوية عليك

1. **دمج الفروع بالترتيب**: `db-compat-fixes` (لم يُنشأ بعد — لم أرَ حاجة فعليًا لأن
   `main` يحمل مسارات الطلبات نفسها) ثم `hardening-complete` ثم `meem-rebrand`.
2. **صور البنرات الثلاثة**: الصور موجودة ومربوطة محليًا من المستودع، ولم تُرفع إلى bucket
   `banners` لأن ذلك يحتاج مفتاحًا. لو أردت رابط CDN بدل مسار المستودع، ارفعها من
   `admin-banners.html` (البكت جاهز وسياساته مطبَّقة) واستبدل الرابط في كل شريحة.
3. **مفتاح CAPTCHA** للتسجيل (Turnstile أو ما تفضّل) — لم أضع مفتاحًا وهميًا.
4. **مفتاح VAPID/بيانات الإشعارات** إن أردت إشعارات دفع حقيقية.
5. **مراجعة القيم في `settings`** خصوصًا `auto_accept_max_sdg` و`usd_to_sdg_rate`.

## 5. تحذيرات مهمة

- **لا تُعِد تطبيق** الملفات في `deprecated/` (لم يبقَ فيها إلا README).
- أي تجربة على القاعدة: داخل معاملة مع ROLLBACK. بيانات الزبائن (30 طلبًا، 3 قيود محفظة)
  لم تُلمَس في هذا العمل.
- لا تستخدم `git push --force` ولا `git reset --hard` ولا دمجًا في `main`؛ في `main` ما
  زال شغل غير مدموج.

---

## 6. جولة 2026-10-13 — بقية المرحلة 1 (المسارات القابلة للتحقق فقط)

### أ) ما نُفّذ وتحقّق منه في هذه الجولة

| # | العمل | الدليل القابل للتشغيل |
|---|---|---|
| 16 | **حد المعدل الموحّد + نطاق أوراكل الإيصالات**: migration جديد يعيد `check_tx_ref_available` ليفحص **صفوف المستخدم نفسه فقط** فوق `consume_chat_rate_limit('txref:<uid>',30,3600)`، ويرفع حد طول كود الدفع من 4 إلى 10، ويضيف تريجر `trg_enforce_coupon_code_strength` (كوبون جديد أو تغيير كود = 10 خانات أبجدية-رقمية على الأقل؛ الصفوف القديمة لا تُمسّ). حد المعدل على الدوال الأربع الأخرى (`validate_coupon`, `validate_payment_code`, `report_fraud_alert`, `log_receipt_fraud_attempt`) موجود أصلًا في `db/migrations/2026-10-08_security_hardening.sql`. | `db/migrations/2026-10-13_p1_oracle_scope_and_coupon_strength.sql` + `db/rollback/…_rollback.sql` (توازن `$fn$` وأقواس سليم؛ الملف مأخوذ حرفيًا من النسخة المعتمدة `2026-10-11_hardening_remaining.sql`) |
| 17 | **صفحة إدارة الكوبونات متوافقة مع القاعدة الجديدة** (كانت تسمح بكود 6 خانات فيُرفض من التريجر): تحقّق فوري ≥10 خانات أبجدية-رقمية + زر «توليد» + مثال صحيح + نص إرشادي. | `admin-coupons.html` |
| 18 | **CORS موحّد لدوال الـEdge**: وحدة نقية `_shared/cors.ts` تُطابق أصول الإنتاج الصريحة + **نمطًا دقيقًا** لروابط معاينة المشروع (`^https:\/\/raizey-store-qw(?:-[a-z0-9-]+)?\.vercel\.app$`، بلا `*` وبلا مسارات/منافذ)، وتقرأ `MEEM_PUBLIC_ORIGIN` ثم `RAIZEY_PUBLIC_ORIGIN`، ويمكن تجاوز النمط بـ`PREVIEW_ORIGIN_REGEX`. الدوال تستوردها بدل النسخ المكرّرة. | `supabase/functions/_shared/cors.ts`، `supabase/functions/{chat-assistant,process-receipt}/index.ts`، وفحص `node scripts/cors_check.mjs` |

فحوص نُفّذت الآن (كلها خضراء):

- `node scripts/cors_check.mjs` → **24/24**: الإنتاج يُعاد كما هو، ومعاينة المشروع تُقبل، و9 أشكال مموّهة/خطرة تُرفض وتُرجَع للإنتاج (بما فيها `http://`, منفذ, مسار, نطاق لاحق للنطاق, `*` مكتوبة صراحةً, regex مشوّه), والعقد `Allow-Methods/Headers/Vary` سليم وبلا `*` في أي ترويسة.
- `python3 scripts/task10_js_syntax_check.py` → **70/70** سكربتًا يُحلَّل (يشمل `admin-coupons.html` المعدّل).
- `npm test` → **54 passed / 0 failed**.
- تحليل TS عبر `module.stripTypeScriptTypes` + `vm.SourceTextModule` → الملفات الثلاثة (`cors.ts` والدالتان) تُحلَّل بلا خطأ.

### ب) مطابقة الدوال المنشورة بالمستودع (published-function parity)

قارنّا تعريفات `db/migrations/2026-10-08_security_hardening.sql` بلقطة القاعدة الحية (`~/.raizey-audit/out/11_defs.json`, بتاريخ 2026-10-08). النتيجة: النسخ متطابقة تقريبًا بعد استبعاد أسطر حد المعدل، والفرق الفعلي هو **التأخّر**: القاعدة الحية لا تحمل بعد أيًّا من الهجرات غير المطبَّقة أدناه (حد المعدل، نطاق `check_tx_ref_available`, قوة الكوبون, بنرات, بادئة الإحالة, نسبة بنر الموبايل). أي أن المستودع **متقدّم** على القاعدة، وليس العكس.

### ج) تصحيح مهم في وصف الفروع

التقرير السابق قال إن `meem-rebrand` «يحتوي `hardening-complete`». **هذا غير صحيح** (فحص `git merge-base --is-ancestor cfcfa66 HEAD` = false). الفرعان شقيقان يتفرّعان من `main` (`41a31b5`):

- `hardening-complete` = `cfcfa66` (5 كوميتات، فيها `2026-10-11_hardening_remaining.sql` و`2026-10-11_fix_wallet_refund_guard.sql`).
- `meem-rebrand` = هذا العمل (12 كوميت، لا يحتوي سابقه).

لذلك: بنود المرحلة 1 المتعلقة بـ`check_tx_ref` وقوة الكوبون أُعيد إنتاجها هنا في migration مستقل (البند 16) كي يكون الفرع مكتفيًا بذاته حتى قبل الدمج.

### د) لا يزال متوقّفًا على الوصول

- **تطبيق أي هجرة** (بما فيها هجرات 2026-10-12 الثلاث والهجرة الجديدة 2026-10-13) يحتاج `SUPABASE_ACCESS_TOKEN`.
- **إعادة اختبار تدفقات المال** على القاعدة الحية (أهم بند) — متوقّف لنفس السبب.

---

## 7. جولة 2026-10-13 (MASTER_SPEC) — البنر + الأيقونات + الرئيسية

المرجع الكامل للمواصفات: `docs/MASTER_SPEC.md` (منسوخة حرفيًا من رسالة المالك).
هذه الجولة التزمت بالترتيب: البنر أولاً، ثم الأيقونات، ثم الرئيسية/المرحلة 4، ثم تدقيق المرحلة 5.

### أ) البنر (الأولوية الأولى) — منفَّذ ومُتحقَّق منه في متصفح حقيقي

| بند المواصفة | ما نُفّذ | الدليل القابل للتشغيل |
|---|---|---|
| أ) الحاوية والمقاسات | ديسكتوب 8:3 بحد أقصى 1440 متوسّط، موبايل بنسبة عامة؛ هامش 12px وزوايا 16-20px؛ `<picture>` بمصدرين + width/height + skeleton؛ أول صورة `fetchpriority=high` بلا lazy | لقطات `ui-shots/banners/{desktop-1440,mobile-390}-hero.png` + قياس النسبة في `report.json` (2.667 و0.75) |
| أ) نسبة الموبايل إعداد عام | مفتاح `banner_mobile_ratio` (نسقط إلى `banner_mobile_aspect`)، خيارات 3:4/4:5/1:1/4:3 ومعاينة حيّة داخل `admin-banners.html` | `db/migrations/2026-10-13_banners_v2.sql`، `assets/js/banners.js#applyAspect`، `admin-banners.html#mobileRatioSelect` |
| ب) Swiper v11 محلي | `assets/vendor/swiper` (11.2.10) — RTL، نقاط وأسهم للديسكتوب، سحب لمسي، loop، انتقال slide أو fade تلقائيًا | `assets/js/banners.js`، `report.json` (rtl/allowTouchMove=true) |
| ب) إمكانية الوصول | زر إيقاف/تشغيل ظاهر (44px، `aria-pressed`)، تنقّل بلوحة المفاتيح، `aria-roledescription`، واحترام `prefers-reduced-motion` | اختبارات جديدة في `scripts/banners_check.mjs`: وقفة/تشغيل + ArrowLeft + reduced-motion |
| ج) مصدر البيانات بلا القاعدة | إن فشل/فرغ RPC تقرأ `assets/banners/default-banners.json` برؤوس cache قصيرة؛ ولا تظهر أيقونة مكسورة أبدًا | `assets/banners/default-banners.json` + لقطتا `db-down-1440.png` و`total-failure-1440.png` |
| د) الصور الثلاث | صُنّفت بعين الأداة وحُوّلت WebP في `assets/banners` | جدول التصنيف في `docs/FINAL_REPORT.md`؛ `curl -I` = 200 `image/webp` لكل ملف |
| هـ) نمطا البنر + النصوص | `image_only` / `image_text` مع تدرّج داكن، عنوان أبيض عريض، فرعي فضي، زر ذهبي `#FFD400` بأيقونة سهم RTL وتوهّج `#087BFF`، وارتفاع 44px | لقطات `*-hero.png` (ctaH=44، ctaBg=rgb(255,212,0)) |
| و) الروابط | none/page/product/category/offers/whatsapp/url، قوائم منسدلة من البيانات الحقيقية، ورقم واتساب من `settings` | `buildLink()` + `banners_check` يقرأ href الفعلي لواتساب/المحفظة/المنتجات |
| ز) الأدمن | CRUD + إعادة ترتيب + تفعيل + نسخ + مسودة/منشور + جدولة بتوقيت الخرطوم + رفع صورتين مع اقتصاص WebP | `admin-banners.html` |
| ح) القاعدة | جدول/RLS/RPCs + نسخ + ترتيب ذرّي + تحقق صارم للروابط ضمن bucket المشروع | `db/migrations/2026-10-13_banners_v2.sql` + rollback |
| ط) الاختبارات | لقطات 390/1440 تُظهر الصور، قياسات `getBoundingClientRect`، فحص `naturalWidth>0`، لوحة المفاتيح، الإيقاف/التشغيل، reduced-motion، حالات الفراغ/الفشل، وregression | `node scripts/banners_check.mjs` → passed؛ `offers_check` → passed؛ `ui_smoke` → 72/72 |

### ب) أيقونات الأقسام والتصنيفات — منفَّذ ومُتحقَّق منه

- وحدة مشتركة `assets/js/category-icons.js`: تطبيع عربي (همزات/تاء مربوطة/تشكيل/تطويل) + جدول كلمات مفتاحية عربي/إنجليزي + مكتبة أزرار (86 أيقونة Lucide) + `resolve()` بأولوية custom → preset → auto → `layout-grid`.
- اختبارات وحدة `scripts/category_icons_check.mjs` → **56/56** (مضافة إلى `npm test`).
- الـ sprite أُعيد بناؤه محليًا: `assets/icons/lucide-sprite.svg` → **141** أيقونة (كان 82)، وكلها موجودة فعلًا.
- الشكل الموحّد `.mm-ico`: مربع مدوّر بتدرّج أزرق ملكي→كهربائي، حد ذهبي رفيع، أيقونة بيضاء بسُمك 1.75 — تحقّق بصريًا في `ui-shots/icons-shape-390.png`.
- القاعدة: `db/migrations/2026-10-13_section_category_icons.sql` (أعمدة + bucket `category-icons` + RPCs + mark) مع rollback.
- الأدمن: `assets/js/admin-icon-picker.js` (تلقائي/مكتبة بحث عربي-إنجليزي/رفع صورة تُقصّ 256×256 WebP <100KB) مربوط في `admin-sections.html` و`admin-categories.html`.

### ج) الرئيسية (المرحلة 4) — منفَّذ جزئيًا بمصادر بيانات حقيقية

- شبكة التصنيفات صارت **عمودين على الموبايل** (كانت تترك نصفًا فارغًا مع تصنيف واحد).
- الوصف الآلي غير الدقيق (`1 من الألعاب...`) أُزيل؛ صار **وصفًا اختياريًا يكتبه الأدمن** ويختفي عندما يكون فارغًا (`store_sections.description`).
- **صف أيقونات الأقسام** أعلى الكتالوج (تمرير أفقي، ينقل للقسم).
- **الأكثر طلبًا** و**جديد في MEEM** من مصادر حقيقية فقط:
  - الأكثر طلبًا عبر RPC `get_top_ordered_products` التي تُجمّع `orders` الحقيقية (لا أرقام وهمية).
  - الجديد عبر `products.created_at`.
  - لا يظهر أي قسم إذا لم تتوفر البيانات (لا تلفيق).
- لم تُوجد أرقام مبيعات/تقييمات وهمية في `index.html` (فحص نصي).

### د) صحة الفروع والإصلاحات المتوافقة مع القاعدة

- تأكيد: `meem-rebrand` **لا يحتوي** `hardening-complete`؛ الفرعان شقيقان من `main` (`41a31b5`). لذلك أُعيد إنتاج بنود التصليب المتوافقة هنا.
- **پarity واجهة my-orders:** موجود بالفعل في `meem-rebrand` — زر «إلغاء الطلب» يستدعي RPC `cancel_my_order` (لا تحديث مباشر)، والهجرة `db/migrations/2026-10-08_user_cancel_order.sql` موجودة.
- صفحات ما زالت تكتب مباشرة (تعتمد على سياسة قائمة): `account.html` تُحدّث صف `profiles` الخاص بالمستخدم (`full_name`/`whatsapp_number`/`player_ids`/`avatar_url`). لم تُسحب هذه السياسة في ملفات التصليب الموجودة في المستودع، لكن يجب تأكيدها على القاعدة الحية (متوقّف على التوكن).

### هـ) الهجرات الجديدة (مكتوبة ومفحوصة ثابتًا، غير مطبَّقة)

| الهجرة | rollback |
|---|---|
| `db/migrations/2026-10-13_banners_v2.sql` | `db/rollback/2026-10-13_banners_v2_rollback.sql` |
| `db/migrations/2026-10-13_section_category_icons.sql` | `db/rollback/2026-10-13_section_category_icons_rollback.sql` |
| `db/migrations/2026-10-13_home_highlights.sql` | `db/rollback/2026-10-13_home_highlights_rollback.sql` |

كلها idempotent، وتوازن `$$`/`begin`/`commit` مفحوص. الواجهة تتحمّل غياب الأعمدة/الدوال عبر علامات قدرة في `settings` (`offers_use_flag`, `catalog_icons_flag`, `home_highlights_flag`).

### و) فحوص هذه الجولة (كلها خضراء)

`npm test` 110 (54 + 56) · `category_icons_check` 56/56 · `task10_js_syntax_check` 70/70 · `task10_static_audit` 77 = خط الأساس · `banners_check` passed (يشمل الإيقاف/التشغيل والإخفاق الكلّي) · `offers_check` passed · `ui_smoke` 72/72.

### ز) لا يزال متوقّفًا على `SUPABASE_ACCESS_TOKEN`

- إعادة اختبار تدفقات المال داخل `BEGIN…ROLLBACK`.
- تطبيق أي من هجرات 2026-10-12 و2026-10-13.
- التحقق من سياسات `profiles` ومدى مطابقة الدوال المنشورة.

---

## 8. جولة 2026-10-14 — اختبارات SQL للمواصفة (§1ط) + تشغيلها فعليًا بلا توكن

### أ) ما نُفّذ وتحقّق منه

| # | العمل | الدليل القابل للتشغيل |
|---|---|---|
| 19 | **فحوص البنر v2** (المواصفة §1ط): زائر لا يرى غير المؤهل، والمجدولة مستقبلًا/المنتهية/المعطّلة/المسودات تختفي، وغير الأدمن ممنوع من `admin_copy_banner`/`admin_set_banner_status`/`admin_reorder_banners`، والترتيب يُحفظ ذرّيًا (نجاح كامل + رفض التكرار دون تحريك أي صف)، ونطاق روابط الصور، وحقول الأدمن (إنشاء/نسخ/نشر) | `db/tests/run_banners_security.sh` — **33/33** |
| 20 | **فحوص الأيقونات والأكثر طلبًا** (§2و/§3): عقد bucket `category-icons` (عام + 200KB + png/webp/jpeg بلا svg)، منع anon وغير الأدمن من RPCs الأيقونات، رفض `mode`/`key`/`javascript:`/مضيف خارج البكت، وجود الأعمدة بقيمة `auto`، علامات القدرة، إخفاء مفاتيح `settings` غير المسموحة، وأن كل رقم في «الأكثر طلبًا» يساوي تجميعًا حقيقيًا على `orders` | `db/tests/run_storefront_security.sh` — **24/24** |
| 21 | **مشغّل فحوص مشترك** بواجهتين: Management API (حيّ) أو `psql` (محلي) — نفس الفحص لا يتغيّر | `db/tests/probe_lib.sh` |
| 22 | **تشغيل بلا توكن**: PostgreSQL 16 محلي (حزمة `pgserver`) + `local_bootstrap.sql` بطبع القاعدة الحية (بلا أي صف حقيقي) + تطبيق الهجرات العشر **مرتين** + الفحوص + ملفات التراجع بالترتيب العكسي | `bash db/tests/local_sql_suite.sh` → `RESULT: OK` |
| 23 | **اختبار المشغّل نفسه**: واجهة الإدارة (بلا توكن، مقابل mock يحاكي شكل ردّ API) + مسارات التصحيح/الفشل/التخطي | `bash db/tests/probe_lib_selftest.sh` → `self-test OK` (3 ناجحة/2 فاشلة/1 متخطّاة كما هو متوقّع) |

### ب) عيبان حقيقيان كشفهما الفحص (وأُصلحا)

1. **تسريب المسودات (أمني)**: سياسة القراءة العامة `banners_public_read` من نسخة v1 كانت `is_active + النافذة` فقط، فأي زائر يقرأ الجدول مباشرة يرى **البنرات المسودة**. أضفت في `2026-10-13_banners_v2.sql` إعادة إنشاء السياسة بشرط `status='published'`، وأصبح الـ rollback يعيد سياسة v1. الفحص `18` هو الذي أسقط الحقن التجريبي.
2. **إعادة تطبيق غير آمنة**: إعادة تشغيل `2026-10-12_banners.sql` بعد v2 كانت تفشل (`hide_when_target_disabled` صار اسمه `hide_if_target_inactive`). وحّدت الملف على الاسم المعتمد في المواصفة §1ح مع حارس إعادة تسمية.
3. تصحيح مطابقة: حجم bucket `category-icons` صار `204800` بايت (200KB كما في §2و) بدل `209715`.

### ج) إثبات أن الفحوص ليست ورقية (mutation test)

| الحقن | النتيجة |
|---|---|
| سياسة القراءة العامة بلا شرط `status` | `FAIL 18` — 32/33 |
| `get_top_ordered_products` بلا شرط `is_active` | `FAIL 20` + `FAIL 21` — 22/24 |

وبعد إعادة تطبيق الهجرات: 33/33 و24/24.

### د) ما بقي متوقّفًا على `SUPABASE_ACCESS_TOKEN`

- تطبيق الهجرات العشر على القاعدة الحية (الجاهزية مثبتة محليًا فقط).
- إعادة اختبار تدفقات المال داخل ROLLBACK.
- تأكيد سياسات `profiles` حيًّا.

### هـ) ملاحظة على §7.ج (تصحيح)

في القسم 7.ج كُتب أن «الواجهة تتحمّل غياب الأعمدة/الدوال عبر علامات قدرة في `settings`». دقيق: العلامات موجودة ومقروءة، وصارت الآن مُختبَرة محليًا (الفحص 17 في مجموعة المتجر).

---

## 9. جولة 2026-10-14 (ب) — التوكن وصل: تطبيق حيّ + فحوص حيّة

### أ) التحقق والتخزين

- `GET /v1/projects` → 200؛ `raizey-store` (`rglbfizqolrenwfsndyv`, `eu-central-1`, `ACTIVE_HEALTHY`)؛ استعلام حقيقي → PostgreSQL 17.6.
- التوكن في `$HOME/.raizey-audit/live_rw` (`0600`، خارج المستودع). الترتيب: `SUPABASE_ACCESS_TOKEN` → `PROBE_TOKEN_FILE` → `live_rw` → `live_ro`. لا يُطبع ولا يُرفع في Git.

### ب) ما نُفّذ على القاعدة الحية

| # | العمل | الدليل |
|---|---|---|
| 24 | **تطبيق الهجرات العشر** بالترتيب الموثّق | `bash db/tests/live_sql.sh --migrations` → 10/10 `ok` |
| 25 | **فحوص أمن البنر** (§1ط) حيًّا | `run_banners_security.sh` → **33/33** (كانت 28 + 1 متخطّى قبل إصلاح المشغّل) |
| 26 | **الأيقونات + الرئيسية** حيًّا | `run_storefront_security.sh` → **27/27** |
| 27 | **تدفقات المال** (استدعاء فعلي للـ RPCs داخل ROLLBACK) | `run_money_flow.sh` → **24/24** |
| 28 | **الثوابت الأمنية/المالية** | `live_sql.sh -f db/tests/security_invariants.sql` → **21/21 passed** |
| 29 | **لقطة استعادة** قبل أي تغيير (صفوف/سياسات/تعريفات/مفاتيح/بكتات) | `~/.raizey-audit/out/live_prechange_20261014-090633.json` |

الحالة النهائية للقاعدة: أعمدة `banners` (بـ `status` و`hide_if_target_inactive`) · 8 دوال بنر · `admin_set_section_icon`/`admin_set_category_icon`/`get_top_ordered_products` · 20 مفتاح `settings` · bucket `category-icons` (عام، 204800، png/webp/jpeg) · `icon_key`/`description` على الأقسام والتصنيفات · `products.is_on_offer` · سياسة قراءة البنرات مقيّدة بـ `status='published'`. **صفوف المشروع لم تتغيّر** (3 بنرات كما هي).

### ج) عيبان في أدوات الفحص كشفهما التشغيل الحيّ

1. **المشغّل الحيّ كان يقرأ العمود باسم `v` فقط** → `None` بصمت لأي استعلام باسم آخر، ولهذا تخطّى فحوص الأدمن 28–32 رغم وجود أدمن. صار يقرأ أول عمود من أول صف (كسلوك `psql -At`)، مع فحص انحدار في `probe_lib_selftest.sh` (عمود باسم مختلف، صف فارغ، `probe_any`).
2. **`live_sql.sh -f` مع مسار مطلق** كان يفشل (سبق المسار بمسار المستودع). أُصلح + `live_sql_selftest.sh` (18 فحصًا على mock لإدارة Supabase، بلا توكن).

### د) المجموعة المحلية (بلا توكن)

`bash db/tests/local_sql_suite.sh` → **exit 0 · RESULT: OK**: bootstrap → 10 هجرات ×2 → اختبارا المشغّل (`probe_lib_selftest` و`live_sql_selftest`) → البنر 33/33 → الواجهة 26 + 1 متخطّى → 9 تراجعات.

في هذه الجولة صار الـ bootstrap يمثّل حقيقة القاعدة أكثر: سياسة `profiles_update_own` (account.html يكتب صف نفسه) ومنح `UPDATE` على `profiles` لـ `authenticated` — بدونهما كان فحص «العميل يحدّث ملفه» يفشل محليًا بينما ينجح حيًّا.

`run_money_flow.sh` **خارج** التشغيل المحلي عمدًا: دوال المال من جولة 2026-10-08 (غير الممثّلة في الـ bootstrap)، والمجموعة ترفض العمل هناك (exit 3) بدل نجاح زائف.

### هـ) ما بقي متوقّفًا

CSP · CAPTCHA · نشر Edge Functions/الأسرار · تأكيد تدفّقات المتصفح (تسجيل دخول/دفع) داخل متصفح حقيقي.

---

## 10. جولة 2026-10-14 (ج) — أقل صلاحية ممكنة + إصلاح رمز الإحالة + تحقق نهائي

### أ) تغييران في القاعدة (مع تراجع مرفق لكل منهما)

| الهجرة | ماذا تفعل | لماذا |
|---|---|---|
| `db/migrations/2026-10-14_revoke_internal_execute.sql` | `REVOKE EXECUTE … FROM public, anon, authenticated` على 19 دالة تريجر داخلية، مع `GRANT … TO service_role` | PostgreSQL يمنح `EXECUTE` لـ `PUBLIC` على كل دالة جديدة افتراضيًا، فصارت كل مساعدات التريجر واجهة قابلة للنداء. نداء التريجر لا يفحص `EXECUTE` (الآلة الداخلية تنادي الدالة)، فسحب المنح لا يغيّر أي سلوك. `profile_guard_fields_unchanged` مستثناة عمدًا: تعبير سياسة `profiles_update_own` يُنفَّذ بهوية المُنادي فيحتاجها `authenticated`. الفحص الذاتي داخل الملف يرفع استثناءً إن بقي أي دور عميل يملك `EXECUTE` |
| `db/migrations/2026-10-14_referral_code_check_for_anon.sql` | `GRANT EXECUTE … TO anon` على `validate_referral_short_code(text)` | `register.html` يتحقق من كود الإحالة **قبل** إنشاء الحساب (أي كـ `anon`) ويمنع الإرسال عند الفشل؛ بلا هذا المنح يعود **كل** كود — صحيحًا كان أو خطأً — برسالة «كود الإحالة غير موجود أو غير صالح» ويُمنع التسجيل بكود إحالة. آمن لأن الدالة تُرجع `(valid, reason)` فقط بلا أي بيانات، وفضاء الأكواد صار `MEEM` + 8 خانات من 32 رمزًا (≈1.1e12)، والدالة `STABLE SECURITY DEFINER` بـ `search_path` مثبّت ولا تكتب. الإسناد نفسه يحسمه التريجر لا العميل |

كلاهما idempotent، ولهما ملف تراجع في `db/rollback/`.

### ب) التحقق الحيّ بعد التغييرين

| القياس | الأمر | النتيجة |
|---|---|---|
| المنح الفعلي لـ `anon` | استعلام `has_function_privilege` | **3 دوال فقط**: `get_banners_public()` · `get_top_ordered_products(integer)` · `validate_referral_short_code(text)` |
| دوال `SECURITY DEFINER` بلا `search_path` | استعلام `pg_proc`/`proconfig` | **0** |
| جداول بلا `RLS` | استعلام `pg_class`/`relrowsecurity` | **0** (81 سياسة) |
| صحة رمز الإحالة كـ`anon` | `run_storefront_security.sh` الفحص 27 و28 | **نجح**: كود مجهول → `false/not_found`، والنداء لا يفشل |
| أمن البنر | `bash db/tests/run_banners_security.sh` | **33/33** |
| الأيقونات/الرئيسية/الملف الشخصي/الإحالة | `bash db/tests/run_storefront_security.sh` | **29/29** (كان 27 في الجولة السابقة: أُضيف فحصا الحس الشخصي والإحالة) |
| تدفقات المال | `bash db/tests/run_money_flow.sh` | **24/24** |
| الثوابت الأمنية/المالية | `bash db/tests/live_sql.sh -f db/tests/security_invariants.sql` | **23/23 `passed`** (فحصان جديدان: حدود نداء مساعدات التريجر، وبقاء `profile_guard_fields_unchanged` مناحةً لـ`authenticated`) |

### ج) ثلاث علل حقيقية في أدوات الفحص/الواجهة كُشفت وأُصلحت

1. **`scripts/offers_check.mjs` كان يقيس الصفحة قبل أن تستقر**: `#content` تبدأ `hidden` في الترميز، فالشرط القديم كان يصدُق فورًا ثم يفشل بلا سبب واضح. الشرط الجديد: «صندوق الحالة مخفي» أو «لم يعد يحمل نص التحميل» — **لا** «نص التحميل غائب»، لأن مسار النجاح يضبط `hidden` ولا يمسح النص (عقدة مخفية تبقى تحتفظ بنصها). وأي انتهاء مهلة صار يُبلَّغ عنه بسبب مقروء (الأخطاء/الطلبات الفاشلة) بدل انهيار استثناء.
2. **`npm run test:edge` كان معطّلًا**: الوحدة المولَّدة في `scripts/.tmp/` تحمل `import … from "../_shared/cors.ts"` الذي يُحلّ إلى `scripts/_shared/cors.ts` غير الموجود. أُعيد كتابة المُحدِّد إلى `../../supabase/functions/_shared/cors.ts` → **94 فحصًا ناجحًا**. وأُضيف `scripts/.tmp/` إلى `.gitignore`.
3. **تناقض قياس التباين**: `getComputedStyle` يُرجع ألوان `oklab()/oklch()` الناتجة عن `color-mix()`، وكان المقياس يقرؤها كثلاثيات 0..255 فيبلّغ عن نسب خاطئة (1.44:1) لنص مقروء بوضوح. صار يحوّل oklab/oklch فعليًا ويدمج الشفافية قبل الحساب، وكل نص على خلفية `--primary` صار يستخدم `--mm-on-primary` (نص داكن على الذهبي) بدل `--ink`.

### د) التحقق النهائي الشامل (كل ما أُعيد تشغيله بعد آخر تعديل)

| المجموعة | الأمر | النتيجة |
|---|---|---|
| اختبارات المستودع | `npm test` | **54 + 56 فحصًا، 0 فاشل** |
| Edge Function | `npm run test:edge` | **94 ناجح، 0 فاشل** |
| المجموعة المحلية | `bash db/tests/local_sql_suite.sh` | **exit 0 · RESULT: OK** (12 هجرة ×2، البنر 33/33، الواجهة 28 + 1 متخطّى، 10 تراجعات) |
| اختبارا المشغّل | `probe_lib_selftest.sh` · `live_sql_selftest.sh` | **self-test OK** لكلٍّ منهما |
| تباين الألوان | `node scripts/ui_contrast.mjs` | **36 صفحة نظيفة** |
| دخان الواجهة | `node scripts/ui_smoke.mjs` | **72/72 صفحة×مقاس** |
| العروض | `node scripts/offers_check.mjs` | **ناجح** (بيانات حيّة + عقد البطاقة + المقاسان) |
| البنر (متصفح) | `node scripts/banners_check.mjs` | **ناجح** |
| CORS | `node scripts/cors_check.mjs` | **24/24** |
| فحوص الجولة | `node scripts/round_checks.mjs` | **ناجح** |

### و) توسيع الثوابت: 23 بدل 21

أُضيف فحصان إلى `db/tests/security_invariants.sql`: `no_client_exec_trigger_helpers` (أي من مساعدات التريجر الـ19 لا يستطيع `anon` ولا `authenticated` نداءها) و`profile_guard_exec_kept` (بقاء `profile_guard_fields_unchanged` مناحةً لـ`authenticated` لأن تعبير سياسة `profiles_update_own` ينفَّذ بهويته، وسحبها من `anon`).

وإثباتًا لأنهما ليسا ورقيَّين: `grant execute on function public.handle_new_user() to anon` داخل معاملة يجعل القياس يعود `1` (أي تفحص بفشل)، وبعد `ROLLBACK` يعود `0`. منح المشروع لم يتغيّر ولا صف واحد تحرّك.

### هـ) ما زال متوقّفًا (بلا ادّعاء إنجاز)

- تأكيد تدفّقات حقيقية بتسجيل دخول ودفع داخل متصفح: يحتاج حسابًا/جلسة مستخدم حقيقية، والفحوص كلها تعمل بلا كتابة أي صف.
- CSP بدون `unsafe-inline`، وCAPTCHA، ونشر Edge Functions وضبط الأسرار: قرار المالك.
- شبكة هذه الـ VM تتعثّر أحيانًا في `cdn.jsdelivr.net` (تحميل `supabase-js`) فيتعطّل أي فحص متصفح يعتمد على بيانات حيّة في تلك المحاولة؛ إعادة التشغيل تُنجح الفحص. الصفحات نفسها تُحمّل المكتبة بنجاح في التشغيل النظيف.
