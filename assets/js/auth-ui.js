/* =========================================================
   RAIZEY STORE — منطق واجهات الحساب المشترك
   إظهار كلمة السر، التحقق اللحظي، قوة كلمة السر،
   خانات الكود، ومؤقت إعادة الإرسال
   ========================================================= */
(function (global) {
  'use strict';

  var EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,24}$/;

  function isValidEmail(value) {
    var v = String(value || '').trim();
    if (!EMAIL_RE.test(v)) return false;
    if (v.length > 254) return false;
    if (v.indexOf('..') !== -1) return false;
    var domain = v.split('@')[1] || '';
    if (domain.length < 4) return false;
    return true;
  }

  function fieldOf(el) { return el.closest('.field'); }

  function setState(el, state, hint) {
    var field = fieldOf(el);
    if (!field) return;
    field.classList.remove('is-valid', 'is-invalid');
    if (state) field.classList.add(state === 'valid' ? 'is-valid' : 'is-invalid');
    var hintBox = field.querySelector('.field-hint');
    if (hintBox && typeof hint === 'string') hintBox.textContent = hint;
  }

  /* إظهار / إخفاء كلمة السر */
  function bindPasswordToggles(scope) {
    (scope || document).querySelectorAll('[data-toggle-password]').forEach(function (btn) {
      var input = document.getElementById(btn.getAttribute('data-toggle-password'));
      if (!input) return;
      btn.addEventListener('click', function () {
        var show = input.type === 'password';
        input.type = show ? 'text' : 'password';
        btn.innerHTML = show ? ICONS.eyeOff : ICONS.eye;
        btn.setAttribute('aria-label', show ? 'إخفاء كلمة السر' : 'إظهار كلمة السر');
        input.focus();
      });
      btn.innerHTML = ICONS.eye;
    });
  }

  /* تحقق لحظي من البريد */
  function bindEmailValidation(input) {
    if (!input) return;
    var run = function () {
      var v = input.value.trim();
      if (!v) { setState(input, null, ''); return; }
      isValidEmail(v)
        ? setState(input, 'valid', 'بريد إلكتروني صالح')
        : setState(input, 'invalid', 'صيغة البريد غير صحيحة، مثال: name@gmail.com');
    };
    input.addEventListener('input', run);
    input.addEventListener('blur', run);
  }

  /* قوة كلمة السر */
  function scorePassword(pw) {
    return {
      length: pw.length >= 8,
      letter: /[A-Za-z]/.test(pw),
      digit: /[0-9]/.test(pw),
      symbol: /[^A-Za-z0-9]/.test(pw),
      long: pw.length >= 12,
      mixed: /[A-Z]/.test(pw) && /[a-z]/.test(pw)
    };
  }

  function bindPasswordStrength(input, fill, label, rulesList) {
    if (!input) return;
    var run = function () {
      var pw = input.value;
      var r = scorePassword(pw);
      if (rulesList) {
        rulesList.querySelectorAll('[data-rule]').forEach(function (li) {
          var ok = !!r[li.getAttribute('data-rule')];
          li.classList.toggle('ok', ok);
          li.querySelector('[data-rule-icon]').innerHTML = ok ? ICONS.checkSm : ICONS.dotSm;
        });
      }
      var score = ['length', 'letter', 'digit', 'symbol', 'long', 'mixed']
        .filter(function (k) { return r[k]; }).length;
      var levels = [
        { pct: 12,  color: '#e5484d', text: 'ضعيفة جداً' },
        { pct: 28,  color: '#e5484d', text: 'ضعيفة جداً' },
        { pct: 45,  color: '#f59e0b', text: 'ضعيفة' },
        { pct: 62,  color: '#f59e0b', text: 'متوسطة' },
        { pct: 78,  color: '#65a30d', text: 'قوية' },
        { pct: 90,  color: '#16a34a', text: 'قوية جداً' },
        { pct: 100, color: '#16a34a', text: 'ممتازة' }
      ];
      var lvl = levels[Math.min(score, levels.length - 1)];
      if (!pw) {
        if (fill) fill.style.width = '0%';
        if (label) label.textContent = '';
        setState(input, null, '');
        return;
      }
      if (fill) { fill.style.width = lvl.pct + '%'; fill.style.background = lvl.color; }
      if (label) { label.textContent = 'قوة كلمة السر: ' + lvl.text; label.style.color = lvl.color; }
      (r.length && r.letter && r.digit)
        ? setState(input, 'valid', '')
        : setState(input, 'invalid', '');
    };
    input.addEventListener('input', run);
    run();
    return run;
  }

  function bindConfirmPassword(passwordInput, confirmInput) {
    if (!passwordInput || !confirmInput) return;
    var run = function () {
      if (!confirmInput.value) { setState(confirmInput, null, ''); return; }
      confirmInput.value === passwordInput.value
        ? setState(confirmInput, 'valid', 'كلمتا السر متطابقتان')
        : setState(confirmInput, 'invalid', 'كلمتا السر غير متطابقتين');
    };
    confirmInput.addEventListener('input', run);
    passwordInput.addEventListener('input', run);
    return run;
  }

  /* خانات الكود */
  function bindOtpInputs(container, onComplete) {
    var digits = Array.prototype.slice.call(container.querySelectorAll('.otp-digit'));
    digits.forEach(function (input, idx) {
      input.addEventListener('input', function () {
        input.value = input.value.replace(/\D/g, '').slice(0, 1);
        input.classList.toggle('filled', !!input.value);
        if (input.value && idx < digits.length - 1) digits[idx + 1].focus();
        var code = digits.map(function (d) { return d.value; }).join('');
        if (code.length === digits.length && typeof onComplete === 'function') onComplete(code);
      });
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Backspace' && !input.value && idx > 0) digits[idx - 1].focus();
        if (e.key === 'ArrowLeft' && idx > 0) digits[idx - 1].focus();
        if (e.key === 'ArrowRight' && idx < digits.length - 1) digits[idx + 1].focus();
      });
      input.addEventListener('paste', function (e) {
        var pasted = (e.clipboardData || window.clipboardData).getData('text').replace(/\D/g, '').slice(0, digits.length);
        if (!pasted) return;
        e.preventDefault();
        pasted.split('').forEach(function (v, i) {
          if (digits[i]) { digits[i].value = v; digits[i].classList.add('filled'); }
        });
        digits[Math.min(pasted.length, digits.length) - 1].focus();
        if (pasted.length === digits.length && typeof onComplete === 'function') onComplete(pasted);
      });
    });
    return {
      value: function () { return digits.map(function (d) { return d.value; }).join(''); },
      clear: function () {
        digits.forEach(function (d) { d.value = ''; d.classList.remove('filled'); });
        digits[0].focus();
      },
      focus: function () { digits[0].focus(); }
    };
  }

  /* مؤقت إعادة الإرسال — 60 ثانية */
  function createResendTimer(button, timerEl, seconds) {
    var total = seconds || 60;
    var left = 0;
    var handle = null;
    var idleLabel = button.getAttribute('data-idle-label') || button.textContent.trim();

    function tick() {
      left--;
      if (left <= 0) { stop(); return; }
      render();
    }
    function render() {
      button.disabled = true;
      var mm = String(Math.floor(left / 60)).padStart(2, '0');
      var ss = String(left % 60).padStart(2, '0');
      if (timerEl) { timerEl.style.display = ''; timerEl.textContent = mm + ':' + ss; }
      button.textContent = 'إعادة الإرسال بعد';
    }
    function stop() {
      clearInterval(handle);
      handle = null;
      left = 0;
      button.disabled = false;
      button.textContent = idleLabel;
      if (timerEl) { timerEl.textContent = ''; timerEl.style.display = 'none'; }
    }
    function start(sec) {
      clearInterval(handle);
      left = sec || total;
      render();
      handle = setInterval(tick, 1000);
    }
    if (timerEl) timerEl.style.display = 'none';
    return { start: start, stop: stop };
  }

  /* حالة تحميل الأزرار */
  function setLoading(button, isLoading, loadingText) {
    if (!button) return;
    if (isLoading) {
      button.dataset.idleHtml = button.dataset.idleHtml || button.innerHTML;
      button.classList.add('loading');
      button.disabled = true;
      button.innerHTML = '<span class="spin"></span><span>' + (loadingText || 'جارِ التنفيذ...') + '</span>';
    } else {
      button.classList.remove('loading');
      button.disabled = false;
      if (button.dataset.idleHtml) button.innerHTML = button.dataset.idleHtml;
    }
  }

  var ICONS = {
    eye: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>',
    eyeOff: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M17.9 17.9A10.4 10.4 0 0 1 12 19c-6.4 0-10-7-10-7a18.7 18.7 0 0 1 5.1-5.9"/><path d="M9.9 4.2A10.6 10.6 0 0 1 12 4c6.4 0 10 7 10 7a18.8 18.8 0 0 1-2.2 3.2"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/><path d="M2 2l20 20"/></svg>',
    checkSm: '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>',
    dotSm: '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><circle cx="12" cy="12" r="4"/></svg>'
  };

  global.RaizeyAuthUI = {
    icons: ICONS,
    isValidEmail: isValidEmail,
    setFieldState: setState,
    bindPasswordToggles: bindPasswordToggles,
    bindEmailValidation: bindEmailValidation,
    bindPasswordStrength: bindPasswordStrength,
    bindConfirmPassword: bindConfirmPassword,
    bindOtpInputs: bindOtpInputs,
    createResendTimer: createResendTimer,
    setLoading: setLoading
  };
})(window);
