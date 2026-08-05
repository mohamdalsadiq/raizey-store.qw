// =========================================================
// RAIZEY STORE — Auth UI Utilities
// أدوات مشتركة لصفحات المصادقة (login / register / reset / verify)
// تُحمَّل بعد supabase-client.js
// =========================================================
(function (global) {
  'use strict';

  // ---------- جاهزية عميل Supabase ----------
  // supabaseClient مُعرَّف بـ let في supabase-client.js، وبالتالي هو في
  // نطاق السكربت لا على window — فحص window.supabaseClient يرجع undefined دائماً.
  function isClientReady() {
    try {
      return typeof supabaseClient !== 'undefined' && !!supabaseClient;
    } catch (e) {
      return false;
    }
  }

  function getClient() {
    return isClientReady() ? supabaseClient : null;
  }

  // ---------- الرسائل ----------
  // نستخدم textContent دائماً (لا innerHTML) لمنع أي XSS.
  function setMessage(el, text) {
    if (!el) return;
    el.textContent = text || '';
  }

  function clearMessages() {
    for (let i = 0; i < arguments.length; i++) setMessage(arguments[i], '');
  }

  // ---------- حالة التحميل للأزرار (تمنع الإرسال المتكرر) ----------
  function startLoading(btn, loadingText) {
    if (!btn) return function () {};
    const originalHtml = btn.innerHTML;
    const wasDisabled  = btn.disabled;
    btn.disabled = true;
    btn.setAttribute('aria-busy', 'true');
    btn.innerHTML = '';
    const spinner = document.createElement('span');
    spinner.className = 'btn-spinner';
    spinner.setAttribute('aria-hidden', 'true');
    btn.appendChild(spinner);
    btn.appendChild(document.createTextNode(loadingText || 'جارِ التنفيذ...'));

    let restored = false;
    return function restore() {
      if (restored) return;
      restored = true;
      btn.innerHTML = originalHtml;
      btn.disabled = wasDisabled;
      btn.removeAttribute('aria-busy');
    };
  }

  // ---------- التحقق من المدخلات ----------
  function isValidEmail(value) {
    const email = String(value || '').trim();
    if (email.length < 6 || email.length > 254) return false;
    return /^[^\s@]+@[^\s@,]+\.[A-Za-z]{2,}$/.test(email);
  }

  // رقم الواتساب: أرقام فقط (مع + اختيارية) بطول منطقي دولي
  function normalizePhone(value) {
    const raw = String(value || '').replace(/[\s\-().]/g, '');
    if (!/^\+?[0-9]{8,15}$/.test(raw)) return null;
    return raw.startsWith('+') ? raw : '+' + raw;
  }

  // قواعد كلمة السر — لازم تطابق إعدادات Supabase Auth
  const PASSWORD_RULES = [
    { id: 'len',   label: '8 أحرف على الأقل',     test: (p) => p.length >= 8 },
    { id: 'lower', label: 'حرف إنجليزي صغير (a-z)', test: (p) => /[a-z]/.test(p) },
    { id: 'upper', label: 'حرف إنجليزي كبير (A-Z)', test: (p) => /[A-Z]/.test(p) },
    { id: 'digit', label: 'رقم واحد على الأقل (0-9)', test: (p) => /[0-9]/.test(p) }
  ];

  function validatePassword(password) {
    const pw = String(password || '');
    const failed = PASSWORD_RULES.filter((r) => !r.test(pw));
    if (pw.length > 72) {
      return { valid: false, message: 'كلمة السر طويلة جداً (الحد 72 حرفاً).', failed: [] };
    }
    if (failed.length) {
      return {
        valid: false,
        message: 'كلمة السر لازم تحتوي: ' + failed.map((r) => r.label).join('، ') + '.',
        failed: failed
      };
    }
    return { valid: true, message: '', failed: [] };
  }

  // ---------- مؤشر قوة كلمة السر + قائمة الشروط ----------
  function renderPasswordRules(listEl, password) {
    if (!listEl) return;
    const pw = String(password || '');
    listEl.innerHTML = '';
    PASSWORD_RULES.forEach((rule) => {
      const li = document.createElement('li');
      li.textContent = rule.label;
      if (pw && rule.test(pw)) li.classList.add('ok');
      listEl.appendChild(li);
    });
  }

  function renderPasswordStrength(fillEl, labelEl, password) {
    const pw = String(password || '');
    if (!fillEl || !labelEl) return;
    if (!pw) {
      fillEl.style.width = '0%';
      labelEl.textContent = '';
      return;
    }

    let score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) score++;
    if (/[0-9]/.test(pw)) score++;
    if (/[^A-Za-z0-9]/.test(pw)) score++;

    const levels = [
      { pct: 20,  color: 'var(--danger)',  text: 'ضعيفة جداً' },
      { pct: 40,  color: 'var(--danger)',  text: 'ضعيفة' },
      { pct: 60,  color: 'var(--warning)', text: 'متوسطة' },
      { pct: 80,  color: '#65a30d',        text: 'قوية' },
      { pct: 100, color: 'var(--success)', text: 'قوية جداً' }
    ];
    const lvl = levels[Math.min(Math.max(score - 1, 0), levels.length - 1)];
    fillEl.style.width = lvl.pct + '%';
    fillEl.style.background = lvl.color;
    labelEl.textContent = 'قوة كلمة السر: ' + lvl.text;
    labelEl.style.color = lvl.color;
  }

  // ---------- زر إظهار/إخفاء كلمة السر ----------
  function initPasswordToggles(root) {
    const scope = root || document;
    scope.querySelectorAll('.pw-toggle[data-target]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const input = document.getElementById(btn.getAttribute('data-target'));
        if (!input) return;
        const show = input.type === 'password';
        input.type = show ? 'text' : 'password';
        btn.setAttribute('aria-pressed', String(show));
        btn.setAttribute('aria-label', show ? 'إخفاء كلمة السر' : 'إظهار كلمة السر');
        const icon = btn.querySelector('i');
        if (icon) icon.className = show ? 'fa-regular fa-eye-slash' : 'fa-regular fa-eye';
      });
    });
  }

  // ---------- إعادة توجيه آمنة (تمنع open redirect) ----------
  // البق القديم: savedRedirect.startsWith(location.origin) يمرّر
  // "https://site.com.evil.com" لأنه يبدأ بنفس النص.
  function resolveSafeRedirect(candidate, fallback) {
    const fb = fallback || 'index.html';
    if (!candidate) return fb;
    try {
      const url = new URL(String(candidate), window.location.href);
      if (url.origin !== window.location.origin) return fb;
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return fb;
      // لا نرجّع المستخدم لصفحات المصادقة نفسها
      if (/\/(login|register|verify|reset-password)\.html$/i.test(url.pathname)) return fb;
      return url.pathname + url.search + url.hash;
    } catch (e) {
      return fb;
    }
  }

  function goToSafeRedirect(fallback) {
    let saved = null;
    try {
      saved = sessionStorage.getItem('redirect_after_login');
      sessionStorage.removeItem('redirect_after_login');
    } catch (e) { /* sessionStorage غير متاح */ }
    window.location.replace(resolveSafeRedirect(saved, fallback));
  }

  global.AuthUI = {
    isClientReady: isClientReady,
    getClient: getClient,
    setMessage: setMessage,
    clearMessages: clearMessages,
    startLoading: startLoading,
    isValidEmail: isValidEmail,
    normalizePhone: normalizePhone,
    validatePassword: validatePassword,
    renderPasswordRules: renderPasswordRules,
    renderPasswordStrength: renderPasswordStrength,
    initPasswordToggles: initPasswordToggles,
    resolveSafeRedirect: resolveSafeRedirect,
    goToSafeRedirect: goToSafeRedirect,
    PASSWORD_RULES: PASSWORD_RULES
  };
})(window);
