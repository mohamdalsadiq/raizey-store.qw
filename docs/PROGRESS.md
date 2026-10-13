# MEEM STORE — حالة العمل (PROGRESS)

آخر تحديث: 2026-10-12 (جولة مسائية) · الفرع الحالي: `meem-rebrand` · الفرع الأساسي: `main` (لم يُمسّ)

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

فحص أمان البنرات على القاعدة الحية (يحتاج توكن، ولا يطبع أي شيء سري، وكل فحص داخل معاملة تُلغى):

```bash
bash db/tests/run_banners_security.sh          # لازم 17/17
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
3. **المرحلة 4 (الأقسام والرئيسية والـ UI)**: شبكة بطاقات جديدة، صف أيقونات الأقسام،
   "الأكثر طلبًا"/"الجديد"، تنظيف أي بيانات ثابتة، ومكوّنات UI موحّدة — لم تُنفَّذ.
4. **المرحلة 5 (التدقيق النهائي من الصفر)** — لم تُنفَّذ.
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
