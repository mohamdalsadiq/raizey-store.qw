# Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** تقوية أمان الواجهة ولوحة الإدارة، توحيد إعداد Supabase، إزالة المخرجات غير الآمنة، وتحسين الواجهة دون كسر السلوك الحالي.

**Architecture:** التنفيذ محافظ وموضعي داخل ملفات HTML/JS/CSS الحالية. يتم بناء طبقة مرافق أمان مشتركة داخل `assets/js/supabase-client.js` ثم إعادة استخدام هذه الطبقة في الصفحات الأكثر حساسية، مع الإبقاء على تدفقات العمل الحالية كما هي.

**Tech Stack:** HTML, CSS, JavaScript, Supabase JS, SQL, Vercel headers

---

### Task 1: توحيد مرافق Supabase والأمان

**Files:**
- Modify: `/workspace/assets/js/supabase-client.js`
- Modify: `/workspace/supabase-client.js`
- Test: `/workspace/package.json`

- [ ] **Step 1: إضافة طبقة تهريب وتحكم مشتركة**

```js
function escapeAttribute(value) {
  return escapeHtml(value).replace(/`/g, '&#x60;');
}

function sanitizeUrl(value) {
  if (!value) return '';
  try {
    const url = new URL(String(value), window.location.origin);
    if (!['http:', 'https:'].includes(url.protocol)) return '';
    return url.href;
  } catch {
    return '';
  }
}
```

- [ ] **Step 2: تقييد أسماء الجداول الحساسة الممررة إلى الدوال المشتركة**

```js
const ALLOWED_DUPLICATE_TABLES = new Set(['orders', 'wallet_topups']);
if (!ALLOWED_DUPLICATE_TABLES.has(table)) return false;
```

- [ ] **Step 3: توحيد ملف الجذر مع الملف المعتمد**

```js
// طبقة توافق تمنع الانحراف بين نسختين مختلفتين
console.warn('[RAIZEY] Use assets/js/supabase-client.js as the canonical client file.');
```

- [ ] **Step 4: تشغيل البناء للتأكد من عدم وجود كسر عام**

Run: `npm run build`
Expected: اكتمال النسخ إلى `dist` بدون أخطاء.

### Task 2: إغلاق ثغرات XSS في صفحات الإدارة الحرجة

**Files:**
- Modify: `/workspace/admin-audit-log.html`
- Modify: `/workspace/admin-topups.html`
- Modify: `/workspace/admin-categories.html`
- Modify: `/workspace/admin-customers.html`
- Modify: `/workspace/admin-coupons.html`
- Modify: `/workspace/admin-giftcards.html`
- Modify: `/workspace/admin-payment-methods.html`
- Modify: `/workspace/admin-referral-milestones.html`
- Modify: `/workspace/admin-orders.html`

- [ ] **Step 1: تهريب النصوص والخصائص الديناميكية**

```js
const safeName = escapeHtml(customerName);
const safeWhatsapp = escapeHtml(customerWhatsapp);
const safeCopy = escapeAttribute(customerWhatsapp);
```

- [ ] **Step 2: تنظيف الروابط الديناميكية**

```js
const receiptUrl = sanitizeUrl(t.receipt_url);
const receiptHtml = receiptUrl
  ? `<a href="${escapeAttribute(receiptUrl)}" target="_blank" rel="noopener">عرض الإيصال</a>`
  : '';
```

- [ ] **Step 3: الحفاظ على نفس السلوك مع أحداث الأزرار الحالية**

```js
container.innerHTML = filtered.map(item => renderCard(item)).join('');
container.querySelectorAll('[data-action]').forEach(bindAction);
```

- [ ] **Step 4: التحقق من الملفات المعدلة**

Run: `npm run build`
Expected: نجاح البناء واستمرار ملفات الإدارة بدون أخطاء صياغية واضحة.

### Task 3: إغلاق الحقن في إدارة المنتجات والصفحات الديناميكية

**Files:**
- Modify: `/workspace/admin-products.html`
- Modify: `/workspace/product.html`
- Modify: `/workspace/checkout.html`
- Modify: `/workspace/category.html`
- Modify: `/workspace/wallet.html`

- [ ] **Step 1: تهريب قيم الحقول والخيارات قبل إدخالها في HTML**

```js
const safeLabel = escapeAttribute(label);
const safePlaceholder = escapeAttribute(placeholder);
const safeOptionId = escapeAttribute(safeId);
```

- [ ] **Step 2: استبدال رسائل الـ Emoji بمؤشرات نصية أو أيقونات متسقة**

```js
errorBox.textContent = 'يرجى اختيار الباقة الأساسية أولاً.';
```

- [ ] **Step 3: الحفاظ على رسائل النجاح الحالية بصياغة نظيفة**

```js
addToCartBtn.innerHTML = '<i class="fas fa-check-circle" aria-hidden="true"></i> تم!';
```

- [ ] **Step 4: التحقق من تدفقات المنتج والدفع**

Run: `npm run build`
Expected: نجاح البناء وعدم ظهور أخطاء تركيب في الصفحات الديناميكية.

### Task 4: تحسينات الواجهة والتجاوب

**Files:**
- Modify: `/workspace/assets/css/admin.css`
- Modify: `/workspace/assets/css/style.css`
- Modify: `/workspace/admin-categories.html`
- Modify: `/workspace/admin-payment-methods.html`
- Modify: `/workspace/admin-products.html`

- [ ] **Step 1: ضبط الأزرار والعناوين لتكون أكثر اتساقاً**

```css
.add-new-btn,
.back-link {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
```

- [ ] **Step 2: تحسين تجاوب القوائم والبطاقات في الشاشات الصغيرة**

```css
@media (max-width: 640px) {
  .manage-item,
  .order-top,
  .customer-info {
    flex-direction: column;
    align-items: stretch;
  }
}
```

- [ ] **Step 3: إبقاء التصميم الحالي مع تحسينات طفيفة فقط**

```css
.mini-copy-btn { min-height: 38px; }
```

- [ ] **Step 4: التحقق من صحة CSS**

Run: `npm run build`
Expected: نجاح البناء بدون تغييرات هيكلية كبيرة.

### Task 5: مراجعة SQL والرؤوس وتجهيز التسليم

**Files:**
- Modify: `/workspace/supabase-security.sql`
- Modify: `/workspace/vercel.json`
- Create: `/workspace/modified_files.zip`

- [ ] **Step 1: مراجعة وتعزيز ملف SQL بما يتوافق مع الجداول المستخدمة**

```sql
-- توثيق أو إضافة سياسات مساعدة للجداول المستخدمة من الواجهة
-- بدون كسر السياسات الحالية أو توسيع الصلاحيات
```

- [ ] **Step 2: الإبقاء على CSP والرؤوس متوافقة مع الملفات الحالية**

```json
{
  "key": "Content-Security-Policy",
  "value": "default-src 'self'; ..."
}
```

- [ ] **Step 3: فحص نهائي ثم ضغط الملفات المعدلة فقط**

Run: `git diff --name-only`
Expected: إظهار الملفات المعدلة فقط لاستخدامها في الأرشيف.

- [ ] **Step 4: إنشاء الأرشيف النهائي**

Run: `zip -r modified_files.zip <modified-files...>`
Expected: إنشاء `modified_files.zip` بمسارات الملفات الأصلية فقط.
