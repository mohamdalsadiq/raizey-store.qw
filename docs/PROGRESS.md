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
