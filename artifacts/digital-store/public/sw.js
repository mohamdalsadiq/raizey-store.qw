const CACHE_NAME = 'raizey-admin-v1';
const ASSETS = [
  '/admin.html',
  '/admin-orders.html',
  '/admin-products.html',
  '/admin-categories.html',
  '/admin-coupons.html',
  '/assets/css/admin.css',
  '/assets/css/style.css',
  '/assets/js/supabase-client.js'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
});

self.addEventListener('fetch', (e) => {
  e.respondWith(
    caches.match(e.request).then(response => {
      return response || fetch(e.request);
    })
  );
});
