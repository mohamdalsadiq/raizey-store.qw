/* Compatibility only. Active preview builds replace this file and remove its UI. */
(function () {
  'use strict';
  const box = () => document.querySelector('[data-receipt-consent] input[type="checkbox"]');
  window.MeemReceiptConsent = Object.freeze({
    mode: 'legacy',
    context: () => box()?.checked === true,
    async require() { return box()?.checked === true; },
    message:()=> 'وافق على معالجة الإيصال آلياً ثم أعد اختيار الصورة؛ لا يمكن الإرسال دون فحص.',
    bindChange(callback) { box()?.addEventListener('change',callback); },
    userId: () => null
  });
})();
