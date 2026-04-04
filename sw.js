const CACHE_NAME = 'workmate4u-v7';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/browse.html',
  '/posted.html',
  '/accepted.html',
  '/completed.html',
  '/profile.html',
  '/wallet.html',
  '/chat.html',
  '/help.html',
  '/styles.css',
  '/app.js',
  '/api-client.js',
  '/shared.js',
  '/favicon.svg'
];

// Install — cache static assets
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

// Activate — clean old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch — only cache same-origin resources; let browser handle CDN/cross-origin
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Skip non-GET, API requests, and cross-origin CDN requests (Font Awesome, Google Fonts, Leaflet, etc.)
  if (event.request.method !== 'GET' || url.pathname.startsWith('/api') || url.pathname.includes('netlify')) {
    return;
  }

  // Let browser handle cross-origin requests natively (CDN icons, fonts, map tiles)
  if (url.origin !== self.location.origin) {
    return;
  }

  // HTML pages: network-first (always fresh)
  if (event.request.headers.get('accept')?.includes('text/html') || url.pathname.endsWith('.html')) {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Same-origin static assets (JS, CSS, images): network-first (so code updates deploy instantly)
  event.respondWith(
    fetch(event.request)
      .then(response => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
