/* Shared customer input rules. The database enforces the same limits. */
(function (root) {
  'use strict';
  const MAX_QUANTITY = 20;
  function digits(value) {
    return String(value ?? '').replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 1632))
      .replace(/[۰-۹]/g, d => String(d.charCodeAt(0) - 1776));
  }
  function fieldLabel(labels, key) {
    const label = labels?.[key];
    return typeof label === 'string' && label.trim() ? label : 'بيانات الطلب';
  }
  function validateField(field, raw) {
    const value = digits(raw).trim();
    const type = field.type || 'text';
    const min = Number(field.min_length ?? 1), max = Number(field.max_length ?? 500);
    if (!Number.isInteger(min) || !Number.isInteger(max) || min < 1 || max > 500 || max < min) return { value, error: 'تعريف الحقل غير صالح؛ تواصل مع الدعم.' };
    if (value.length < min || value.length > max) return { value, error: `أدخل ${field.label || 'البيانات'} بطول من ${min} إلى ${max} خانة.` };
    if (type === 'numeric_id' && !/^[0-9]+$/.test(value)) return { value, error: `${field.label || 'المعرّف'} يقبل أرقاماً فقط.` };
    if (type === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return { value, error: 'أدخل بريداً إلكترونياً صحيحاً.' };
    if (!['text', 'numeric_id', 'email'].includes(type)) return { value, error: 'نوع الحقل غير مدعوم.' };
    return { value, error: '' };
  }
  function validQuantity(value) { return Number.isInteger(value) && value >= 1 && value <= MAX_QUANTITY; }
  function cartError(items) {
    return !Array.isArray(items) || !items.length || items.length > 30 || items.some(item => !item || !validQuantity(item.quantity ?? 1))
      ? 'راجع السلة: الكمية المسموحة لكل باقة من 1 إلى 20، وبحد أقصى 30 عنصراً.' : '';
  }
  root.MeemStoreRules = { MAX_QUANTITY, digits, fieldLabel, validateField, validQuantity, cartError };
})(window);
