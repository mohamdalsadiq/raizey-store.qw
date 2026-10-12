/* =========================================================
   MEEM STORE — storefront banner carousel
   Data: public.get_banners_public()  (RLS-safe, validated server side)
   Slides are built with DOM APIs only — never innerHTML.
   ========================================================= */
(function () {
  'use strict';

  var MOBILE_MAX = 767;
  var REDUCED = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);

  // keep in sync with public.banners_validate()'s page whitelist
  var ALLOWED_PAGES = {
    'index.html': 1, 'offers.html': 1, 'wallet.html': 1, 'cart.html': 1,
    'my-orders.html': 1, 'product.html': 1, 'category.html': 1, 'search.html': 1,
    'referrals.html': 1, 'notifications.html': 1, 'account.html': 1, 'privacy.html': 1
  };

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
    } else if (type === 'product' && /^[0-9a-fA-F-]{36}$/.test(target)) {
      href = 'product.html?id=' + encodeURIComponent(target);
    } else if (type === 'category' && /^[0-9a-fA-F-]{36}$/.test(target)) {
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
    img.setAttribute('src', d);
    img.setAttribute('alt', typeof b.alt_text === 'string' ? b.alt_text : '');
    img.setAttribute('width', '1920');
    img.setAttribute('height', '720');
    img.setAttribute('decoding', 'async');
    img.setAttribute('loading', eager ? 'eager' : 'lazy');
    if (eager) img.setAttribute('fetchpriority', 'high');
    pic.appendChild(img);
    box.appendChild(pic);
    return true;
  }

  function buildSlide(b, index) {
    var slide = el('div', 'swiper-slide mm-slide');
    slide.setAttribute('data-style', b.banner_style === 'image_text' ? 'image_text' : 'image_only');
    slide.setAttribute('data-ovd', b.overlay_position_desktop === 'left' ? 'left' : 'right');
    slide.setAttribute('data-ovm', b.overlay_position_mobile === 'bottom' ? 'bottom' : 'top');
    if (!appendPicture(slide, b, index === 0)) return null;

    var hasText = b.banner_style === 'image_text' &&
      typeof b.title === 'string' && b.title.trim() !== '';

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
      slide.setAttribute('role', 'group');
      slide.setAttribute('aria-label', b.title.trim());
    } else {
      var hit = el('a', 'mm-slide-hit mm-stretched');
      hit.setAttribute('aria-label', (typeof b.alt_text === 'string' && b.alt_text) || 'عرض');
      applyLink(hit, b);
      if (hit.getAttribute('href')) slide.appendChild(hit);
      slide.setAttribute('role', 'group');
      slide.setAttribute('aria-label', (typeof b.alt_text === 'string' && b.alt_text) || 'عرض');
    }
    return slide;
  }

  function defaultSlide() {
    var slide = el('div', 'swiper-slide mm-slide mm-slide-default');
    slide.setAttribute('data-style', 'image_only');
    var pic = el('picture', 'mm-slide-media');
    var s = document.createElement('source');
    s.setAttribute('type', 'image/webp');
    s.setAttribute('srcset', 'assets/img/meem-og.webp');
    pic.appendChild(s);
    var img = el('img');
    img.setAttribute('src', 'assets/img/meem-og.png');
    img.setAttribute('alt', 'MEEM STORE');
    img.setAttribute('width', '1200');
    img.setAttribute('height', '630');
    img.setAttribute('loading', 'eager');
    img.setAttribute('decoding', 'async');
    pic.appendChild(img);
    slide.appendChild(pic);
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

  function init(root, wrapper, dots, prevBtn, nextBtn) {
    var slides = wrapper.children.length;
    var cfg = {
      slidesPerView: 1,
      loop: slides > 1,
      rtl: true,
      speed: REDUCED ? 0 : 600,
      watchOverflow: true,
      keyboard: { enabled: true },
      a11y: { enabled: true, prevSlideMessage: 'الشريحة السابقة', nextSlideMessage: 'الشريحة التالية', paginationBulletMessage: 'اذهب للشريحة {{index}}' }
    };
    if (slides > 1 && !REDUCED) {
      cfg.autoplay = { delay: 5000, disableOnInteraction: false, pauseOnMouseEnter: true };
    }
    if (slides > 1 && dots) {
      cfg.pagination = { el: dots, clickable: true, bulletElement: 'button' };
    }
    if (slides > 1 && prevBtn && nextBtn) {
      cfg.navigation = { prevEl: prevBtn, nextEl: nextBtn };
    }

    var swiper = new window.Swiper(root, cfg);

    if (slides > 1 && swiper.autoplay && window.matchMedia('(hover: none)').matches) {
      root.addEventListener('touchstart', function () {
        if (swiper.autoplay) swiper.autoplay.stop();
      }, { passive: true });
      root.addEventListener('touchend', function () {
        if (swiper.autoplay) swiper.autoplay.start();
      }, { passive: true });
    }
    root.setAttribute('data-ready', '1');
    track('weem.banners.ready', { slides: slides });
    return swiper;
  }

  function render(slidesData) {
    var root = document.getElementById('mmHeroSwiper');
    var wrapper = document.getElementById('mmHeroWrapper');
    if (!root || !wrapper) return;
    var dots = document.getElementById('mmHeroDots');
    var prevBtn = document.getElementById('mmHeroPrev');
    var nextBtn = document.getElementById('mmHeroNext');

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
      init(root, wrapper, dots, prevBtn, nextBtn);
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

  function load() {
    var root = document.getElementById('mmHeroSwiper');
    if (!root) return;
    showSkeleton();

    var client = window.supabaseClient;
    if (!client) { render([]); return; }

    client.rpc('get_banners_public').then(function (res) {
      var data = res && res.data;
      if (res && res.error) {
        track('weem.banners.error', { message: String(res.error.message || '') });
        data = [];
      }
      if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch (e) { data = []; }
      }
      render(data);
    })['catch'](function (e) {
      track('weem.banners.error', { message: String((e && e.message) || e) });
      render([]);
    });
  }

  window.MeemBanners = {
    render: render,
    load: load,
    buildSlide: buildSlide,
    defaultSlide: defaultSlide,
    buildLink: buildLink,
    track: function (fn) { tracker = fn; }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', load);
  } else {
    load();
  }
})();
