// DEPLOY_VERSION: Update this string on each deploy to bust caches automatically.
// The browser detects byte-level changes to sw.js and triggers an update.
const CACHE_NAME = 'workmate4u-v20260428d';
const STATIC_ASSETS = [
  '/index.html',
  '/browse.html',
  '/posted.html',
  '/accepted.html',
  '/completed.html',
  '/profile.html',
  '/wallet.html',
  '/help.html',
  '/styles.css',
  '/app.js',
  '/api-client.js',
  '/sw-register.js',
  '/shared.js',
  '/favicon.svg',
  '/icon-192x192.png',
  '/icon-512x512.png'
];

// Install — activate INSTANTLY, cache assets in background (non-blocking)
self.addEventListener('install', event => {
  self.skipWaiting();
  // Cache assets in background — don't block install on this
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      // Fire-and-forget: cache each asset individually, failures are fine
      STATIC_ASSETS.forEach(url => {
        cache.add(url).catch(() => {});
      });
      return Promise.resolve(); // Resolve immediately — don't wait for caching
    })
  );
});

// Activate — clean ALL old caches and notify clients to refresh
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => {
      // Notify all open tabs that a new version is active
      self.clients.matchAll({ type: 'window' }).then(clients => {
        clients.forEach(client => client.postMessage({ type: 'SW_UPDATED' }));
      });
    })
  );
  self.clients.claim();
});

// Listen for skip-waiting message from the page
self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
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

// ========================================
// PUSH NOTIFICATIONS
// ========================================

self.addEventListener('push', event => {
  let data = { title: 'Workmate4u', body: 'You have a new notification', icon: '/icon-192x192.png' };
  
  if (event.data) {
    try {
      data = Object.assign(data, event.data.json());
    } catch (e) {
      data.body = event.data.text();
    }
  }

  const options = {
    body: data.body,
    icon: data.icon || '/icon-192x192.png',
    badge: '/icon-192x192.png',
    vibrate: [200, 100, 200],
    tag: data.tag || 'workmate4u-notification',
    renotify: true,
    data: {
      url: data.url || '/',
      notificationId: data.notificationId
    }
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || '/';
  
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
      // Focus existing tab if open
      for (const client of clients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      // Open new tab
      return self.clients.openWindow(targetUrl);
    })
  );
});
