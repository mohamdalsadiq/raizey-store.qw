/* =========================================================
   MEEM STORE — storefront banner carousel
   Data source, in order:
     1. public.get_banners_public()  (RLS-safe, validated server side)
     2. A neutral brand slide on an unavailable or empty response
   Slides are built with DOM APIs only — never innerHTML with DB data.
   ========================================================= */
(function () {
  'use strict';

  var MOBILE_MAX = 767;
  var REDUCED = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  var SETTINGS_URL = 'assets/banners/default-settings.json';

  // Mobile slide ratio is a store setting (public.settings.banner_mobile_ratio).
  // Desktop stays 3:1. Every slide shares one ratio so the height never
  // jumps between slides during autoplay.
  var MOBILE_RATIOS = window.MeemBannerUtils.ratios;
  var DEFAULT_MOBILE_RATIO = '16 / 9';

  // Store settings with their safe defaults (used when the DB is unreachable).
  var DEFAULTS = { mobile: '16:9', autoplay: true, interval: 5, effect: 'slide' };

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
  function safeImageUrl(u, preview) {
    if (typeof u !== 'string' || u.includes('..')) return '';
    var v = u.trim();
    if (preview && v.startsWith('blob:' + location.origin + '/')) return v;
    if (/^\/assets\/banners\/[A-Za-z0-9_@.-]+\.(webp|png|jpg|jpeg)$/.test(v)) return v;
    if (/^https:\/\/dvcsdbsnnbdpzaiccjej\.supabase\.co\/storage\/v1\/object\/public\/banners\/(?:[A-Za-z0-9_-]+\/)*[A-Za-z0-9_@.-]+\.(webp|png|jpg|jpeg)$/.test(v)) return v;
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

  function appendPicture(box, b, eager, options) {
    options = options || {};
    var d = safeImageUrl(b.image_desktop_url, options.preview);
    var m = safeImageUrl(b.image_mobile_url, options.preview);
    if (!d) return false;

    var pic = el('picture', 'mm-slide-media');
    // Only reference files that exist. Uploaded WebP does not imply an @2x asset.
    if (m && !options.preview) {
      var mobile = document.createElement('source');
      mobile.media = '(max-width: ' + MOBILE_MAX + 'px)';
      mobile.srcset = m;
      pic.appendChild(mobile);
    }
    var img = el('img');
    img.setAttribute('src', options.preview && options.view === 'mobile' ? (m || d) : d);
    img.setAttribute('alt', typeof b.alt_text === 'string' ? b.alt_text : '');
    img.setAttribute('width', '1920');
    img.setAttribute('height', '640');
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

  function buildSlide(b, index, options) {
    var slide = el('div', 'swiper-slide mm-slide');
    slide.setAttribute('data-style', b.banner_style === 'image_text' ? 'image_text' : 'image_only');
    slide.setAttribute('data-ovd', b.overlay_position_desktop === 'left' ? 'left' : 'right');
    slide.setAttribute('data-ovm', b.overlay_position_mobile === 'bottom' ? 'bottom' : 'top');
    slide.setAttribute('role', 'group');
    slide.setAttribute('aria-roledescription', 'slide');
    if (!appendPicture(slide, b, index === 0, options)) return null;

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
      keyboard: { enabled: false },
      a11y: { enabled: true, prevSlideMessage: 'الشريحة السابقة', nextSlideMessage: 'الشريحة التالية', paginationBulletMessage: 'اذهب للشريحة {{index}}' }
    };
    if (settings && settings.effect === 'fade' && slides > 1 && !REDUCED) {
      cfg.effect = 'fade';
      cfg.fadeEffect = { crossFade: true };
    }
    var autoplayOn = !REDUCED && settings && settings.autoplay && slides > 1;
    if (slides > 1) {
      cfg.autoplay = {
        enabled: !!autoplayOn,
        delay: (settings.interval || DEFAULTS.interval) * 1000,
        disableOnInteraction: false,
        pauseOnMouseEnter: false
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

    wireCarouselInteraction(swiper, root, autoplayOn, slides);
    root.setAttribute('data-ready', '1');
    track('weem.banners.ready', { slides: slides, effect: cfg.effect || 'slide', autoplay: !!autoplayOn });
    return swiper;
  }

  function wireCarouselInteraction(swiper, root, autoplayOn, slides) {
    if (!swiper.autoplay || slides < 2) return;
    root.tabIndex = 0;
    var playing = !!autoplayOn, hovering = false, focused = false, touching = false;
    var pointerStart = null, moved = false;
    function sync() {
      if (playing && !hovering && !focused && !touching && !document.hidden) swiper.autoplay.start();
      else swiper.autoplay.stop();
      root.dataset.motion = playing ? 'playing' : 'paused';
    }
    function toggle() { playing = !playing; if (playing) { focused = false; hovering = false; } sync(); }
    root.onpointerenter = function (e) { if (e.pointerType === 'mouse') { hovering = true; sync(); } };
    root.onpointerleave = function () { hovering = false; sync(); };
    root.onpointerdown = function (e) { pointerStart = { x: e.clientX, y: e.clientY }; moved = false; touching = true; sync(); };
    root.onpointermove = function (e) { if (pointerStart && Math.hypot(e.clientX - pointerStart.x, e.clientY - pointerStart.y) > 10) moved = true; };
    function release() { if (!touching) return; touching = false; pointerStart = null; sync(); }
    document.addEventListener('pointerup', release);
    document.addEventListener('pointercancel', release);
    root.onclick = function (e) {
      if (!moved && !e.target.closest('a,button')) toggle();
    };
    root.onfocusin = function () { focused = !touching; sync(); };
    root.onfocusout = function (e) { focused = root.contains(e.relatedTarget); sync(); };
    root.onkeydown = function (e) {
      if (/INPUT|SELECT|TEXTAREA/.test(e.target.tagName)) return;
      if (e.key === 'ArrowLeft') { e.preventDefault(); swiper.slideNext(); }
      if (e.key === 'ArrowRight') { e.preventDefault(); swiper.slidePrev(); }
      if (e.key === ' ' && e.target === root) { e.preventDefault(); toggle(); }
    };
    function visibility() { sync(); }
    document.addEventListener('visibilitychange', visibility);
    swiper.on('destroy', function () {
      document.removeEventListener('visibilitychange', visibility);
      document.removeEventListener('pointerup', release);
      document.removeEventListener('pointercancel', release);
      root.onclick = root.onpointerdown = root.onpointermove = root.onpointerenter = root.onpointerleave = root.onfocusin = root.onfocusout = root.onkeydown = null;
    });
    sync();
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
        var s = buildSlide(b, built);
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
    // Failed reads cannot prove a campaign is published or within its schedule.
    return Promise.resolve([]);
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
        if (Array.isArray(data)) { render(data, settings); return; }
        // An authoritative empty result must not resurrect unpublished promotions.
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
