/* =========================================================
   MEEM STORE — storefront banner carousel
   Data source, in order:
     1. public.get_banners_public()  (RLS-safe, validated server side)
     2. assets/banners/default-banners.json  (repo fallback, short cache)
   Slides are built with DOM APIs only — never innerHTML with DB data.
   ========================================================= */
(function () {
  'use strict';

  var MOBILE_MAX = 767;
  var REDUCED = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  var FALLBACK_URL = 'assets/banners/default-banners.json';
  var SETTINGS_URL = 'assets/banners/default-settings.json';

  // Mobile slide ratio is a store setting (public.settings.banner_mobile_ratio).
  // Desktop stays 8:3 always. Every slide shares one ratio so the height never
  // jumps between slides during autoplay.
  var MOBILE_RATIOS = { '3:4': '3 / 4', '4:5': '4 / 5', '1:1': '1 / 1', '4:3': '4 / 3' };
  var DEFAULT_MOBILE_RATIO = '3 / 4';

  // Store settings with their safe defaults (used when the DB is unreachable).
  var DEFAULTS = { mobile: '3:4', autoplay: true, interval: 5, effect: 'slide' };

  function applyAspect(value) {
    var root = document.getElementById('mmHeroSwiper');
    if (!root) return;
    var css = MOBILE_RATIOS[String(value == null ? '' : value).trim()];
    root.style.setProperty('--mm-hero-ar-mobile', css || DEFAULT_MOBILE_RATIO);
  }

  function boolish(v, dflt) {
    var s = String(v == null ? '' : v).trim().toLowerCase();
    if (s === 'false' || s === 'off' || s === '0' || s === 'no') return false;
    if (s === 'true' || s === 'on' || s === '1' || s === 'yes') return true;
    return dflt;
  }

  function clampInterval(v) {
    var n = parseInt(v, 10);
    if (isNaN(n)) return DEFAULTS.interval;
    return Math.min(10, Math.max(3, n));
  }

  function normEffect(v) {
    var s = String(v == null ? '' : v).trim().toLowerCase();
    return s === 'fade' ? 'fade' : 'slide';
  }

  function readSettings() {
    var client = window.supabaseClient;
    var result = { mobile: DEFAULTS.mobile, autoplay: DEFAULTS.autoplay, interval: DEFAULTS.interval, effect: DEFAULTS.effect };
    if (!client || typeof client.from !== 'function') {
      // No DB: try the tiny repo fallback so a support override still works.
      return fetch(SETTINGS_URL, { cache: 'no-cache' })
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (j) { return j ? mergeSettings(result, j) : result; })
        ['catch'](function () { return result; });
    }
    return client.from('settings')
      .select('key,value')
      .in('key', ['banner_mobile_ratio', 'banner_mobile_aspect', 'banner_autoplay', 'banner_interval', 'banner_effect'])
      .then(function (res) {
        if (res && !res.error && Array.isArray(res.data)) {
          var map = {};
          res.data.forEach(function (row) { map[row.key] = row.value; });
          mergeSettings(result, {
            mobile: map.banner_mobile_ratio || map.banner_mobile_aspect,
            autoplay: map.banner_autoplay,
            interval: map.banner_interval,
            effect: map.banner_effect
          });
        }
        return result;
      })
      ['catch'](function () { return result; });
  }

  function mergeSettings(target, src) {
    if (!src) return target;
    if (src.mobile != null && MOBILE_RATIOS[String(src.mobile).trim()]) target.mobile = String(src.mobile).trim();
    if (src.autoplay != null) target.autoplay = boolish(src.autoplay, target.autoplay);
    if (src.interval != null) target.interval = clampInterval(src.interval);
    if (src.effect != null) target.effect = normEffect(src.effect);
    return target;
  }

  // keep in sync with public.banners_validate()'s page whitelist
  var ALLOWED_PAGES = {
    'index.html': 1, 'offers.html': 1, 'wallet.html': 1, 'cart.html': 1,
    'my-orders.html': 1, 'product.html': 1, 'category.html': 1, 'search.html': 1,
    'referrals.html': 1, 'notifications.html': 1, 'account.html': 1, 'privacy.html': 1
  };

  function isUuid(v) { return /^[0-9a-fA-F-]{36}$/.test(String(v || '')); }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function svgIcon(id, cls) {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', cls || 'mm-i');
    svg.setAttribute('aria-hidden', 'true');
    var use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
    use.setAttribute('href', 'assets/icons/lucide-sprite.svg#' + id);
    svg.appendChild(use);
    return svg;
  }

  // only same-origin relative paths, https URLs, or Supabase storage URLs
  function safeImageUrl(u) {
    if (typeof u !== 'string') return '';
    var v = u.trim();
    if (/^\/[^/]/.test(v)) return v;
    if (/^https:\/\//i.test(v)) return v;
    return '';
  }

  function safeAnchor(href) {
    if (typeof href !== 'string') return '';
    var h = href.trim();
    if (/^\/[^/]/.test(h) || /^#[A-Za-z0-9_-]+$/.test(h)) return h;
    var parts = h.split('#');
    if (ALLOWED_PAGES[parts[0]] && (parts.length === 1 || /^[A-Za-z0-9_-]+$/.test(parts[1]))) return h;
    if (/^https:\/\//i.test(h)) return h;
    return '';
  }

  function buildLink(b) {
    var href = '';
    var external = false;
    var type = String(b.link_type || 'none');
    var target = b.link_target == null ? '' : String(b.link_target);

    if (type === 'page') {
      href = safeAnchor(target);
    } else if (type === 'product' && isUuid(target)) {
      href = 'product.html?id=' + encodeURIComponent(target);
    } else if (type === 'category' && isUuid(target)) {
      href = 'category.html?id=' + encodeURIComponent(target);
    } else if (type === 'offers') {
      href = 'offers.html';
    } else if (type === 'url') {
      var u = safeAnchor(target);
      if (/^https:\/\//i.test(u)) { href = u; external = true; }
    } else if (type === 'whatsapp') {
      external = true;
      var msg = typeof b.whatsapp_message === 'string' ? b.whatsapp_message.trim() : '';
      var base = 'https://wa.me/__NUMBER__';
      var get = (window.MeemStore && window.MeemStore.getWhatsapp)
        ? window.MeemStore.getWhatsapp()
        : Promise.resolve('');
      return {
        external: true,
        resolve: function () {
          return get.then(function (num) {
            num = String(num || '').replace(/[^0-9]/g, '');
            if (!num) return '';
            return base.replace('__NUMBER__', num) + (msg ? '?text=' + encodeURIComponent(msg) : '');
          });
        }
      };
    }
    if (!href) return null;
    return { href: href, external: external };
  }

  function applyLink(node, b) {
    var link = buildLink(b);
    if (!link) return;
    if (link.resolve) {
      link.resolve().then(function (href) {
        if (!href) return;
        node.setAttribute('href', href);
        node.setAttribute('target', '_blank');
        node.setAttribute('rel', 'noopener');
      });
      node.setAttribute('href', 'https://wa.me/');
      node.setAttribute('target', '_blank');
      node.setAttribute('rel', 'noopener');
      return;
    }
    node.setAttribute('href', link.href);
    if (link.external) {
      node.setAttribute('target', '_blank');
      node.setAttribute('rel', 'noopener');
    }
  }

  function appendPicture(box, b, eager) {
    var d = safeImageUrl(b.image_desktop_url);
    var m = safeImageUrl(b.image_mobile_url);
    if (!d) return false;

    var d2 = d.replace(/\.webp$/i, '@2x.webp');
    var m2 = m ? m.replace(/\.webp$/i, '@2x.webp') : '';
    var pic = el('picture', 'mm-slide-media');

    if (m) {
      var s1 = document.createElement('source');
      s1.setAttribute('media', '(max-width: ' + MOBILE_MAX + 'px)');
      s1.setAttribute('type', 'image/webp');
      s1.setAttribute('srcset', m + ' 1x' + (m2 !== m ? ', ' + m2 + ' 2x' : ''));
      pic.appendChild(s1);
    }
    var s2 = document.createElement('source');
    s2.setAttribute('media', '(min-width: ' + (MOBILE_MAX + 1) + 'px)');
    s2.setAttribute('type', 'image/webp');
    s2.setAttribute('srcset', d + ' 1x' + (d2 !== d ? ', ' + d2 + ' 2x' : ''));
    pic.appendChild(s2);

    var img = el('img');
    img.setAttribute('src', m && window.matchMedia && window.matchMedia('(max-width: ' + MOBILE_MAX + 'px)').matches ? m : d);
    img.setAttribute('alt', typeof b.alt_text === 'string' ? b.alt_text : '');
    img.setAttribute('width', '1920');
    img.setAttribute('height', '720');
    img.setAttribute('decoding', 'async');
    img.setAttribute('loading', eager ? 'eager' : 'lazy');
    if (eager) img.setAttribute('fetchpriority', 'high');
    // Never show a broken-image icon or alt text: if an artwork fails to load
    // the slide drops to the branded backdrop and keeps its live heading/CTA.
    img.addEventListener('error', function () {
      box.classList.add('mm-slide-fallback');
      if (pic.parentNode) pic.parentNode.removeChild(pic);
    });
    pic.appendChild(img);
    box.appendChild(pic);
    return true;
  }

  function buildSlide(b, index) {
    var slide = el('div', 'swiper-slide mm-slide');
    slide.setAttribute('data-style', b.banner_style === 'image_text' ? 'image_text' : 'image_only');
    slide.setAttribute('data-ovd', b.overlay_position_desktop === 'left' ? 'left' : 'right');
    slide.setAttribute('data-ovm', b.overlay_position_mobile === 'bottom' ? 'bottom' : 'top');
    slide.setAttribute('role', 'group');
    slide.setAttribute('aria-roledescription', 'slide');
    if (!appendPicture(slide, b, index === 0)) return null;

    var hasText = b.banner_style === 'image_text' &&
      typeof b.title === 'string' && b.title.trim() !== '';
    var label = (typeof b.title === 'string' && b.title.trim()) ||
      (typeof b.alt_text === 'string' && b.alt_text) || 'عرض';
    slide.setAttribute('aria-label', label);

    if (hasText) {
      slide.appendChild(el('div', 'mm-slide-scrim'));
      var body = el('div', 'mm-slide-body');
      body.appendChild(el('h2', 'mm-slide-title', b.title.trim()));
      if (typeof b.subtitle === 'string' && b.subtitle.trim()) {
        body.appendChild(el('p', 'mm-slide-sub', b.subtitle.trim()));
      }
      var cta = el('a', 'mm-slide-cta mm-stretched');
      cta.appendChild(el('span', null, (typeof b.cta_text === 'string' && b.cta_text.trim()) || 'اعرف المزيد'));
      cta.appendChild(svgIcon('i-arrow-left', 'mm-i mm-slide-cta-icon'));
      applyLink(cta, b);
      body.appendChild(cta);
      slide.appendChild(body);
    } else {
      var hit = el('a', 'mm-slide-hit mm-stretched');
      hit.setAttribute('aria-label', label);
      applyLink(hit, b);
      if (hit.getAttribute('href')) slide.appendChild(hit);
    }
    return slide;
  }

  function defaultSlide() {
    // No <img> here on purpose: the backdrop is the MEEM gradient + mark drawn
    // by CSS, so a missing file can never render a broken-image placeholder.
    var slide = el('div', 'swiper-slide mm-slide mm-slide-default mm-slide-fallback');
    slide.setAttribute('data-style', 'image_only');
    slide.setAttribute('role', 'group');
    slide.setAttribute('aria-label', 'MEEM STORE');
    return slide;
  }

  function skeleton() {
    var s = el('div', 'swiper-slide mm-slide mm-slide-skeleton');
    s.setAttribute('aria-hidden', 'true');
    return s;
  }

  var tracker = null;
  function track(event, detail) {
    if (tracker) tracker(event, detail);
  }

  function init(root, wrapper, dots, prevBtn, nextBtn, settings) {
    var slides = wrapper.children.length;
    var cfg = {
      slidesPerView: 1,
      loop: slides > 1,
      rtl: true,
      speed: REDUCED ? 0 : 600,
      watchOverflow: true,
      keyboard: { enabled: true, onlyInViewport: true },
      a11y: { enabled: true, prevSlideMessage: 'الشريحة السابقة', nextSlideMessage: 'الشريحة التالية', paginationBulletMessage: 'اذهب للشريحة {{index}}' }
    };
    if (settings && settings.effect === 'fade' && slides > 1 && !REDUCED) {
      cfg.effect = 'fade';
      cfg.fadeEffect = { crossFade: true };
    }
    var autoplayOn = !REDUCED && settings && settings.autoplay && slides > 1;
    if (autoplayOn) {
      cfg.autoplay = {
        delay: (settings.interval || DEFAULTS.interval) * 1000,
        disableOnInteraction: false,
        pauseOnMouseEnter: true
      };
    }
    if (slides > 1 && dots) {
      cfg.pagination = { el: dots, clickable: true, bulletElement: 'button' };
    }
    if (slides > 1 && prevBtn && nextBtn) {
      cfg.navigation = { prevEl: prevBtn, nextEl: nextBtn };
    }

    var swiper = new window.Swiper(root, cfg);
    if (root.swiper === undefined) { try { root.swiper = swiper; } catch (e) {} }

    if (autoplayOn && swiper.autoplay && window.matchMedia('(hover: none)').matches) {
      root.addEventListener('touchstart', function () { if (swiper.autoplay) swiper.autoplay.stop(); }, { passive: true });
      root.addEventListener('touchend', function () { if (swiper.autoplay) swiper.autoplay.start(); }, { passive: true });
    }

    wirePlayPause(swiper, root, autoplayOn);
    root.setAttribute('data-ready', '1');
    track('weem.banners.ready', { slides: slides, effect: cfg.effect || 'slide', autoplay: !!autoplayOn });
    return swiper;
  }

  function wirePlayPause(swiper, root, autoplayOn) {
    var btn = document.getElementById('mmHeroPlayPause');
    if (!btn) return;
    if (!swiper.autoplay || !autoplayOn) { btn.hidden = true; return; }
    btn.hidden = false;
    var paused = REDUCED;
    function paint() {
      btn.setAttribute('aria-pressed', paused ? 'false' : 'true');
      btn.setAttribute('aria-label', paused ? 'تشغيل الحركة التلقائية' : 'إيقاف الحركة التلقائية');
      btn.dataset.state = paused ? 'paused' : 'playing';
    }
    paint();
    btn.addEventListener('click', function () {
      paused = !paused;
      if (paused) { swiper.autoplay.stop(); } else { swiper.autoplay.start(); }
      paint();
      track('weem.banners.toggle', { paused: paused });
    });
    // An explicit user pause also stops autoplay if the pointer leaves the box.
    btn.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); btn.click(); } });
  }

  function render(slidesData, settings) {
    settings = settings || { mobile: DEFAULTS.mobile, autoplay: DEFAULTS.autoplay, interval: DEFAULTS.interval, effect: DEFAULTS.effect };
    var root = document.getElementById('mmHeroSwiper');
    var wrapper = document.getElementById('mmHeroWrapper');
    if (!root || !wrapper) return;
    var dots = document.getElementById('mmHeroDots');
    var prevBtn = document.getElementById('mmHeroPrev');
    var nextBtn = document.getElementById('mmHeroNext');

    applyAspect(settings.mobile);

    // Tear down a previous instance (used by the admin live preview too).
    if (root.swiper && typeof root.swiper.destroy === 'function') {
      try { root.swiper.destroy(true, true); } catch (e) {}
      root.swiper = undefined;
    }
    while (wrapper.firstChild) wrapper.removeChild(wrapper.firstChild);

    var built = 0;
    if (Array.isArray(slidesData) && slidesData.length) {
      slidesData.forEach(function (b, i) {
        var s = buildSlide(b, i);
        if (s) { wrapper.appendChild(s); built++; }
      });
    }
    if (!built) wrapper.appendChild(defaultSlide());

    var real = wrapper.querySelectorAll('.mm-slide:not(.mm-slide-skeleton)').length;
    if (dots) dots.hidden = real < 2;
    if (prevBtn) prevBtn.hidden = real < 2;
    if (nextBtn) nextBtn.hidden = real < 2;

    if (window.Swiper) {
      init(root, wrapper, dots, prevBtn, nextBtn, settings);
    } else {
      root.setAttribute('data-ready', '1');
      root.classList.add('mm-hero-noswiper');
      track('weem.banners.degraded', { reason: 'swiper-missing' });
    }
  }

  function showSkeleton() {
    var wrapper = document.getElementById('mmHeroWrapper');
    if (!wrapper || wrapper.children.length) return;
    wrapper.appendChild(skeleton());
  }

  function fetchDefault() {
    // Short cache headers on purpose: a stale fallback must not outlive the DB.
    return fetch(FALLBACK_URL, { cache: 'no-cache' })
      .then(function (r) { return r.ok ? r.json() : []; })
      ['catch'](function () { return []; });
  }

  function load() {
    var root = document.getElementById('mmHeroSwiper');
    if (!root) return;
    showSkeleton();

    var settingsPromise = readSettings();
    var client = window.supabaseClient;

    if (!client || typeof client.rpc !== 'function') {
      settingsPromise.then(function (settings) {
        return fetchDefault().then(function (rows) { render(rows, settings); });
      });
      return;
    }

    settingsPromise.then(function (settings) {
      client.rpc('get_banners_public').then(function (res) {
        var data = res && res.data;
        if (res && res.error) {
          track('weem.banners.error', { message: String(res.error.message || '') });
          data = null;
        }
        if (typeof data === 'string') {
          try { data = JSON.parse(data); } catch (e) { data = null; }
        }
        if (Array.isArray(data) && data.length) { render(data, settings); return; }
        // DB reachable but empty/unavailable → repo fallback, never a broken box.
        fetchDefault().then(function (rows) { render(rows, settings); });
      })['catch'](function (e) {
        track('weem.banners.error', { message: String((e && e.message) || e) });
        fetchDefault().then(function (rows) { render(rows, settings); });
      });
    });
  }

  window.MeemBanners = {
    render: render,
    load: load,
    buildSlide: buildSlide,
    defaultSlide: defaultSlide,
    buildLink: buildLink,
    applyAspect: applyAspect,
    readSettings: readSettings,
    track: function (fn) { tracker = fn; }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', load);
  } else {
    load();
  }
})();
