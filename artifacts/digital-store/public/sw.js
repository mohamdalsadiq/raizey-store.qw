// =========================================================
// RAIZEY STORE — Service Worker v2
// Strategy:
//   • Static assets (CSS/JS/fonts/images) → Cache-First
//   • HTML pages → Network-First with cache fallback
//   • External CDN → Cache-First (immutable)
// =========================================================

const CACHE_VERSION = 'raizey-v2';
const ASSET_CACHE   = `${CACHE_VERSION}-assets`;
const PAGE_CACHE    = `${CACHE_VERSION}-pages`;
const CDN_CACHE     = `${CACHE_VERSION}-cdn`;

const CORE_ASSETS = [
  '/assets/css/style.css',
  '/assets/css/admin.css',
  '/assets/css/auth.css',
  '/assets/js/supabase-client.js',
  '/assets/js/admin-rbac.js',
  '/manifest.json',
];

const CORE_PAGES = [
  '/index.html',
  '/login.html',
  '/register.html',
  '/cart.html',
  '/checkout.html',
  '/product.html',
  '/category.html',
  '/search.html',
  '/account.html',
  '/wallet.html',
  '/my-orders.html',
  '/notifications.html',
  '/referrals.html',
  '/receipt.html',
  '/verify.html',
  '/reset-password.html',
  '/admin.html',
  '/admin-orders.html',
  '/admin-products.html',
  '/admin-categories.html',
  '/admin-coupons.html',
  '/admin-customers.html',
  '/admin-settings.html',
  '/admin-audit-log.html',
  '/admin-topups.html',
  '/admin-giftcards.html',
  '/admin-payment-methods.html',
  '/admin-referral-milestones.html',
  '/admin-bootstrap.html',
];

// ── Install: pre-cache core assets ──────────────────────
self.addEventListener('install', (e) => {
  e.waitUntil(
    Promise.all([
      caches.open(ASSET_CACHE).then(c => c.addAll(CORE_ASSETS).catch(() => {})),
      caches.open(PAGE_CACHE).then(c => c.addAll(CORE_PAGES).catch(() => {})),
    ]).then(() => self.skipWaiting())
  );
});

// ── Activate: delete old caches ─────────────────────────
self.addEventListener('activate', (e) => {
  const keep = [ASSET_CACHE, PAGE_CACHE, CDN_CACHE];
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => !keep.includes(k)).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// ── Fetch: route by resource type ───────────────────────
self.addEventListener('fetch', (e) => {
  const { request } = e;
  const url = new URL(request.url);

  // Skip non-GET requests and chrome-extension requests
  if (request.method !== 'GET' || url.protocol === 'chrome-extension:') return;

  // Skip Supabase API calls — always network-only
  if (url.hostname.includes('supabase.co')) return;

  // External CDN (fonts, Font Awesome, Supabase JS) → Cache-First
  if (
    url.hostname.includes('fonts.googleapis.com') ||
    url.hostname.includes('fonts.gstatic.com') ||
    url.hostname.includes('cdnjs.cloudflare.com') ||
    url.hostname.includes('cdn.jsdelivr.net')
  ) {
    e.respondWith(cacheFirst(request, CDN_CACHE));
    return;
  }

  // Static assets → Cache-First
  if (/\.(css|js|woff2?|ttf|eot|svg|png|jpg|jpeg|webp|ico|gif)(\?.*)?$/.test(url.pathname)) {
    e.respondWith(cacheFirst(request, ASSET_CACHE));
    return;
  }

  // HTML pages → Network-First with stale fallback
  if (url.hostname === self.location.hostname) {
    e.respondWith(networkFirst(request, PAGE_CACHE));
    return;
  }
});

// ── Helpers ─────────────────────────────────────────────
async function cacheFirst(request, cacheName) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (e) {
    return new Response('', { status: 503, statusText: 'Offline' });
  }
}

async function networkFirst(request, cacheName) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (e) {
    const cached = await caches.match(request);
    return cached || new Response('', { status: 503, statusText: 'Offline' });
  }
}
