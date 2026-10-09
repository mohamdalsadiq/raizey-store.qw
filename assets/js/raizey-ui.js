/* =============================================================================
   RAIZEY STORE — UI behaviour layer (vanilla, no dependencies)
   Pairs with assets/css/raizey.css. Exposes a single global: window.RZUI.
   Loaded in <head> on every page so inline page scripts can use it immediately.
   ============================================================================= */
(function () {
  'use strict';

  var SPRITE = 'assets/icons/lucide-sprite.svg';
  var reduced = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ── Icons ─────────────────────────────────────────────────────────────── */
  function iconMarkup(name, className, style) {
    return '<svg class="rz-i ' + (className || '') + '" aria-hidden="true"' + (style ? ' style="' + style + '"' : '') +
      '><use href="' + SPRITE + '#i-' + name + '"></use></svg>';
  }
  function icon(name, className, style) {
    var wrap = document.createElement('span');
    wrap.innerHTML = iconMarkup(name, className, style);
    return wrap.firstElementChild;
  }
  /** Legacy helper: accepts either a Lucide name or an old "fas fa-x" class list. */
  function iconFromLegacy(value) {
    var v = String(value || '').trim();
    if (v.indexOf('fa-') === -1) return icon(v);
    var map = window.RZ_FA_ICONS || {};
    var tokens = v.split(/\s+/);
    for (var i = 0; i < tokens.length; i++) {
      if (map[tokens[i]]) return icon(map[tokens[i]]);
    }
    return icon('circle-help');
  }

  /* ── Legacy icon names (Font Awesome) → Lucide, for progressive call sites ─ */
  window.RZ_FA_ICONS = {
    "fa-arrow-left": "arrow-left",
    "fa-arrow-right": "arrow-right",
    "fa-arrow-right-arrow-left": "arrow-right-left",
    "fa-bag-shopping": "shopping-bag",
    "fa-ban": "ban",
    "fa-basket-shopping": "shopping-basket",
    "fa-bell": "bell",
    "fa-bolt": "zap",
    "fa-box": "package",
    "fa-box-open": "package-open",
    "fa-bullseye": "target",
    "fa-camera": "camera",
    "fa-cart-plus": "shopping-cart",
    "fa-check": "check",
    "fa-check-circle": "circle-check",
    "fa-chevron-down": "chevron-down",
    "fa-chevron-left": "chevron-left",
    "fa-circle-check": "circle-check",
    "fa-circle-exclamation": "circle-alert",
    "fa-circle-info": "info",
    "fa-circle-notch": "loader-circle",
    "fa-circle-xmark": "circle-x",
    "fa-clipboard-list": "clipboard-list",
    "fa-clock": "clock",
    "fa-clock-rotate-left": "history",
    "fa-cloud-arrow-up": "cloud-upload",
    "fa-coins": "coins",
    "fa-copy": "copy",
    "fa-database": "database",
    "fa-envelope-circle-check": "mail-check",
    "fa-file-lines": "file-text",
    "fa-floppy-disk": "save",
    "fa-gamepad": "gamepad-2",
    "fa-gears": "settings",
    "fa-gift": "gift",
    "fa-hashtag": "hash",
    "fa-headset": "headset",
    "fa-home": "house",
    "fa-id-card": "id-card",
    "fa-image": "image",
    "fa-key": "key-round",
    "fa-laptop": "laptop",
    "fa-layer-group": "layers",
    "fa-link": "link",
    "fa-list-check": "list-checks",
    "fa-lock": "lock",
    "fa-mobile-screen-button": "smartphone",
    "fa-paper-plane": "send",
    "fa-paperclip": "paperclip",
    "fa-pen": "pen",
    "fa-pen-to-square": "square-pen",
    "fa-play": "play",
    "fa-plus": "plus",
    "fa-qr": "qr-code",
    "fa-receipt": "receipt-text",
    "fa-right-from-bracket": "log-out",
    "fa-rotate": "rotate-cw",
    "fa-rotate-left": "rotate-ccw",
    "fa-rotate-right": "rotate-cw",
    "fa-save": "save",
    "fa-screwdriver-wrench": "wrench",
    "fa-share-nodes": "share-2",
    "fa-shield-halved": "shield-half",
    "fa-shopping-cart": "shopping-cart",
    "fa-sliders": "sliders-horizontal",
    "fa-sparkles": "sparkles",
    "fa-spinner": "loader",
    "fa-store": "store",
    "fa-tag": "tag",
    "fa-ticket": "ticket",
    "fa-times-circle": "circle-x",
    "fa-trash-arrow-up": "trash-2",
    "fa-trash-can": "trash-2",
    "fa-triangle-exclamation": "triangle-alert",
    "fa-university": "landmark",
    "fa-upload": "upload",
    "fa-user": "user",
    "fa-user-check": "user-check",
    "fa-user-lock": "user-lock",
    "fa-user-plus": "user-plus",
    "fa-user-shield": "shield-user",
    "fa-users": "users",
    "fa-wallet": "wallet",
    "fa-whatsapp": "whatsapp",
    "fa-xmark": "x"
  };

  /* ── Safe HTML escaping (use before interpolating user data into strings) ── */
  function esc(value) {
    if (value === null || value === undefined) return '';
    return String(value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  /* ── Numbers (Arabic-Indic digits stay LTR and tabular) ────────────────── */
  function num(value, digits) {
    var n = Number(value);
    if (!isFinite(n)) return '0';
    return n.toLocaleString('en-US', {
      minimumFractionDigits: digits || 0,
      maximumFractionDigits: digits === undefined ? 2 : digits
    });
  }

  /* ── Toasts ────────────────────────────────────────────────────────────── */
  var TONES = {
    success: { icon: 'circle-check', label: 'تم' },
    danger: { icon: 'circle-x', label: 'خطأ' },
    warning: { icon: 'triangle-alert', label: 'تنبيه' },
    info: { icon: 'info', label: 'معلومة' }
  };

  function toastHost() {
    var host = document.getElementById('rzToasts');
    if (!host) {
      host = document.createElement('div');
      host.id = 'rzToasts';
      host.className = 'rz-toasts';
      host.setAttribute('role', 'status');
      host.setAttribute('aria-live', 'polite');
      document.body.appendChild(host);
    }
    return host;
  }

  function toast(options) {
    var opts = typeof options === 'string' ? { title: options } : (options || {});
    var tone = TONES[opts.tone] ? opts.tone : (opts.type && TONES[opts.type] ? opts.type : 'info');
    var meta = TONES[tone];
    var el = document.createElement('div');
    el.className = 'rz-toast rz-toast--' + tone;
    el.innerHTML =
      '<span class="rz-toast__icon">' + iconMarkup(opts.icon || meta.icon) + '</span>' +
      '<div style="flex:1;min-width:0">' +
        '<div class="rz-toast__title">' + esc(opts.title || meta.label) + '</div>' +
        (opts.body ? '<div class="rz-toast__body">' + esc(opts.body) + '</div>' : '') +
      '</div>' +
      '<button type="button" class="rz-toast__close" aria-label="إغلاق">' + iconMarkup('x') + '</button>';
    var timer = null;
    function close() {
      if (!el.parentNode) return;
      el.classList.add('is-leaving');
      setTimeout(function () { el.remove(); }, reduced ? 0 : 180);
    }
    el.querySelector('.rz-toast__close').addEventListener('click', close);
    toastHost().appendChild(el);
    var duration = opts.duration === undefined ? (tone === 'danger' ? 7000 : 4200) : opts.duration;
    if (duration) timer = setTimeout(close, duration);
    el.addEventListener('mouseenter', function () { if (timer) clearTimeout(timer); });
    return { close: close };
  }

  /* ── Modal / bottom sheet with focus management ────────────────────────── */
  var lastFocus = null;

  function openModal(target, options) {
    var opts = options || {};
    var el = typeof target === 'string' ? document.querySelector(target) : target;
    if (!el) return null;
    lastFocus = document.activeElement;
    el.hidden = false;
    el.classList.add('is-open');
    document.documentElement.style.overflow = 'hidden';
    var focusTarget = el.querySelector('[data-rz-autofocus]') || el.querySelector('button, [href], input, select, textarea');
    if (focusTarget) focusTarget.focus({ preventScroll: true });

    function onKey(event) {
      if (event.key === 'Escape' && opts.dismissible !== false) { close(); return; }
      if (event.key !== 'Tab') return;
      var nodes = el.querySelectorAll('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])');
      if (!nodes.length) return;
      var first = nodes[0], last = nodes[nodes.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    function onBackdrop(event) { if (event.target === el && opts.dismissible !== false) close(); }
    function close() {
      el.hidden = true;
      el.classList.remove('is-open');
      document.documentElement.style.overflow = '';
      document.removeEventListener('keydown', onKey);
      el.removeEventListener('mousedown', onBackdrop);
      if (lastFocus && lastFocus.focus) lastFocus.focus({ preventScroll: true });
      if (typeof opts.onClose === 'function') opts.onClose();
    }
    document.addEventListener('keydown', onKey);
    el.addEventListener('mousedown', onBackdrop);
    el.querySelectorAll('[data-rz-close]').forEach(function (btn) { btn.addEventListener('click', close); });
    return { close: close, el: el };
  }

  /** Accessible replacement for window.confirm — returns a Promise<boolean>. */
  function confirmDialog(options) {
    var opts = options || {};
    return new Promise(function (resolve) {
      var overlay = document.createElement('div');
      overlay.className = 'rz-overlay';
      overlay.innerHTML =
        '<div class="rz-modal rz-sheet-handle" role="alertdialog" aria-modal="true" aria-labelledby="rzConfirmTitle">' +
          '<div class="rz-modal__head">' +
            '<div><h2 class="rz-modal__title" id="rzConfirmTitle">' + esc(opts.title || 'تأكيد العملية') + '</h2>' +
            (opts.body ? '<p class="rz-modal__desc">' + esc(opts.body) + '</p>' : '') + '</div>' +
          '</div>' +
          '<div class="rz-modal__foot">' +
            '<button type="button" class="rz-btn rz-btn--ghost" data-rz-close>' + esc(opts.cancelText || 'إلغاء') + '</button>' +
            '<button type="button" class="rz-btn ' + (opts.danger ? 'rz-btn--danger' : 'rz-btn--primary') + '" data-rz-confirm>' +
              iconMarkup(opts.danger ? 'triangle-alert' : 'check') + esc(opts.confirmText || 'تأكيد') + '</button>' +
          '</div>' +
        '</div>';
      document.body.appendChild(overlay);
      var confirmed = false;
      var modal = openModal(overlay, {
        onClose: function () { overlay.remove(); resolve(confirmed); }
      });
      overlay.querySelector('[data-rz-confirm]').addEventListener('click', function () {
        confirmed = true;
        modal.close();
      });
    });
  }

  /* ── Reveal on scroll (progressive: without JS the content is visible) ─── */
  function initReveal(root) {
    var nodes = (root || document).querySelectorAll('.rz-reveal:not(.is-visible)');
    if (!nodes.length) return;
    if (reduced || typeof IntersectionObserver !== 'function') {
      nodes.forEach(function (n) { n.classList.add('is-visible'); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        io.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: .05 });
    nodes.forEach(function (n) { io.observe(n); });
  }

  /* ── Count-up for stat values ──────────────────────────────────────────── */
  function initCounters(root) {
    var nodes = (root || document).querySelectorAll('[data-rz-count]:not([data-rz-done])');
    nodes.forEach(function (node) {
      node.setAttribute('data-rz-done', '1');
      var target = Number(node.getAttribute('data-rz-count'));
      var digits = Number(node.getAttribute('data-rz-digits') || 0);
      var suffix = node.getAttribute('data-rz-suffix') || '';
      if (!isFinite(target) || reduced) { node.textContent = num(target, digits) + suffix; return; }
      var start = performance.now();
      var from = 0;
      (function step(now) {
        var p = Math.min(1, (now - start) / 650);
        var eased = 1 - Math.pow(1 - p, 3);
        node.textContent = num(from + (target - from) * eased, digits) + suffix;
        if (p < 1) requestAnimationFrame(step);
      })(start);
    });
  }

  /* ── Tabs ──────────────────────────────────────────────────────────────── */
  function initTabs(root) {
    (root || document).querySelectorAll('[data-rz-tabs]').forEach(function (group) {
      if (group.dataset.rzReady) return;
      group.dataset.rzReady = '1';
      var tabs = Array.prototype.slice.call(group.querySelectorAll('[role="tab"], .rz-tab'));
      function select(tab) {
        tabs.forEach(function (t) {
          var active = t === tab;
          t.setAttribute('aria-selected', active ? 'true' : 'false');
          t.classList.toggle('is-active', active);
          t.tabIndex = active ? 0 : -1;
          var panel = document.getElementById(t.getAttribute('aria-controls') || ('panel-' + t.dataset.rzTab));
          if (panel) panel.hidden = !active;
        });
      }
      tabs.forEach(function (tab, index) {
        tab.addEventListener('click', function () { select(tab); });
        tab.addEventListener('keydown', function (event) {
          var dir = event.key === 'ArrowLeft' ? -1 : event.key === 'ArrowRight' ? 1 : 0;
          if (!dir) return;
          event.preventDefault();
          var next = tabs[(index + dir + tabs.length) % tabs.length];
          next.focus(); select(next);
        });
      });
      var initial = tabs.filter(function (t) { return t.getAttribute('aria-selected') === 'true'; })[0] || tabs[0];
      if (initial) select(initial);
    });
  }

  /* ── Menus & dropdowns ─────────────────────────────────────────────────── */
  function initMenus(root) {
    (root || document).querySelectorAll('[data-rz-menu-toggle]').forEach(function (btn) {
      if (btn.dataset.rzReady) return;
      btn.dataset.rzReady = '1';
      var menu = document.getElementById(btn.getAttribute('aria-controls'));
      if (!menu) return;
      btn.setAttribute('aria-expanded', 'false');
      btn.addEventListener('click', function (event) {
        event.stopPropagation();
        var open = menu.hidden;
        menu.hidden = !open;
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      });
      document.addEventListener('click', function (event) {
        if (menu.hidden) return;
        if (!menu.contains(event.target) && event.target !== btn) { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
      });
      document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape' && !menu.hidden) { menu.hidden = true; btn.setAttribute('aria-expanded', 'false'); btn.focus(); }
      });
    });
  }

  /* ── Copy to clipboard with toast feedback ─────────────────────────────── */
  function copyText(text, label) {
    var value = String(text || '');
    function done() { toast({ tone: 'success', title: 'تم النسخ', body: label || value }); }
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(value).then(done).catch(function () { fallback(); });
    }
    fallback();
    function fallback() {
      var ta = document.createElement('textarea');
      ta.value = value;
      ta.setAttribute('readonly', '');
      ta.style.cssText = 'position:fixed;inset-inline-start:-1000px;opacity:0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); done(); }
      catch (err) { toast({ tone: 'danger', title: 'تعذّر النسخ', body: 'انسخ القيمة يدوياً' }); }
      finally { ta.remove(); }
    }
  }

  function initCopyTargets(root) {
    (root || document).querySelectorAll('[data-rz-copy]').forEach(function (el) {
      if (el.dataset.rzReady) return;
      el.dataset.rzReady = '1';
      el.addEventListener('click', function () {
        var selector = el.getAttribute('data-rz-copy');
        var source = selector ? document.querySelector(selector) : null;
        copyText(source ? (source.value || source.textContent) : el.textContent, el.getAttribute('data-rz-copy-label'));
      });
    });
  }

  /* ── Busy state for submit buttons ─────────────────────────────────────── */
  function busy(button, isBusy, busyLabel) {
    if (!button) return;
    if (isBusy) {
      button.dataset.rzLabel = button.dataset.rzLabel || button.innerHTML;
      button.setAttribute('aria-busy', 'true');
      button.disabled = true;
      button.innerHTML = '<span class="rz-spinner rz-spinner--sm" aria-hidden="true"></span>' + esc(busyLabel || 'جارٍ التنفيذ...');
    } else {
      button.removeAttribute('aria-busy');
      button.disabled = false;
      if (button.dataset.rzLabel) button.innerHTML = button.dataset.rzLabel;
    }
  }

  /* ── Drop zones ────────────────────────────────────────────────────────── */
  function initDropZones(root) {
    (root || document).querySelectorAll('[data-rz-drop]').forEach(function (zone) {
      if (zone.dataset.rzReady) return;
      zone.dataset.rzReady = '1';
      ['dragenter', 'dragover'].forEach(function (type) {
        zone.addEventListener(type, function (event) { event.preventDefault(); zone.classList.add('is-dragover'); });
      });
      ['dragleave', 'drop'].forEach(function (type) {
        zone.addEventListener(type, function () { zone.classList.remove('is-dragover'); });
      });
    });
  }

  /* ── Ripple feedback on primary actions ────────────────────────────────── */
  function initRipple(root) {
    if (reduced) return;
    (root || document).querySelectorAll('.rz-btn--primary, .btn-primary, .buy-btn').forEach(function (btn) {
      if (btn.dataset.rzRipple) return;
      btn.dataset.rzRipple = '1';
      btn.addEventListener('pointerdown', function (event) {
        var rect = btn.getBoundingClientRect();
        var dot = document.createElement('span');
        var size = Math.max(rect.width, rect.height);
        dot.style.cssText = 'position:absolute;border-radius:50%;pointer-events:none;background:rgba(255,248,240,.35);' +
          'width:' + size + 'px;height:' + size + 'px;transform:translate(-50%,-50%) scale(0);opacity:.9;' +
          'transition:transform .45s cubic-bezier(.16,1,.3,1),opacity .45s;' +
          'inset-inline-start:' + ((event.clientX || rect.left + rect.width / 2) - rect.left) + 'px;top:' + ((event.clientY || rect.top + rect.height / 2) - rect.top) + 'px;';
        btn.appendChild(dot);
        requestAnimationFrame(function () { dot.style.transform = 'translate(-50%,-50%) scale(1)'; dot.style.opacity = '0'; });
        setTimeout(function () { dot.remove(); }, 500);
      });
    });
  }

  /* ── Theme (light · dark · auto) ───────────────────────────────────────── */
  var THEME_KEY = 'raizey-theme';
  function applyTheme(mode) {
    var value = mode || localStorage.getItem(THEME_KEY) || 'auto';
    if (value === 'auto') document.documentElement.removeAttribute('data-theme');
    else document.documentElement.setAttribute('data-theme', value);
    document.documentElement.setAttribute('data-theme-mode', value);
    document.querySelectorAll('[data-rz-theme-toggle]').forEach(function (btn) {
      var next = value === 'dark' ? 'light' : 'dark';
      btn.setAttribute('aria-label', next === 'dark' ? 'تفعيل الوضع الليلي' : 'تفعيل الوضع النهاري');
      btn.title = btn.getAttribute('aria-label');
      btn.setAttribute('data-next', next);
      var use = btn.querySelector('use');
      if (use) use.setAttribute('href', SPRITE + (value === 'dark' ? '#i-sun' : '#i-moon'));
    });
    return value;
  }
  function initTheme() {
    applyTheme(localStorage.getItem(THEME_KEY) || 'auto');
    document.querySelectorAll('[data-rz-theme-toggle]').forEach(function (btn) {
      if (btn.dataset.rzReady) return;
      btn.dataset.rzReady = '1';
      btn.addEventListener('click', function () {
        var next = btn.getAttribute('data-next') || 'dark';
        localStorage.setItem(THEME_KEY, next);
        applyTheme(next);
      });
    });
  }

  /* ── Progressive enhancement pass ──────────────────────────────────────── */
  function enhance(root) {
    initTabs(root); initMenus(root); initReveal(root); initCounters(root);
    initCopyTargets(root); initDropZones(root); initRipple(root); initTheme();
    // legacy alert() → non-blocking toast (keeps old call sites usable)
    if (!window.__rzNativeAlert) {
      window.__rzNativeAlert = window.alert;
      window.alert = function (message) { toast({ tone: 'info', title: String(message === undefined ? '' : message) }); };
    }
  }

  window.RZUI = {
    icon: icon, iconMarkup: iconMarkup, iconFromLegacy: iconFromLegacy,
    esc: esc, num: num, toast: toast, openModal: openModal, confirm: confirmDialog,
    busy: busy, copy: copyText, enhance: enhance, theme: applyTheme,
    reducedMotion: reduced, sprite: SPRITE
  };
  window.rzIcon = iconFromLegacy;
  window.rzIconMarkup = iconMarkup;
  window.rzToast = toast;
  window.rzNum = num;
  window.rzEsc = esc;
  window.rzConfirm = confirmDialog;

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { enhance(document); });
  else enhance(document);
})();
