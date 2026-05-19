// DEPLOY_VERSION: Update this string on each deploy to bust caches automatically.
// The browser detects byte-level changes to sw.js and triggers an update.
const CACHE_NAME = 'workmate4u-v20260520c';
const STATIC_ASSETS = [
  '/index.html',
  '/browse.html',
  '/categories.html',
  '/feedback.html',
  '/posted.html',
  '/accepted.html',
  '/completed.html',
  '/profile.html',
  '/wallet.html',
  '/chat.html',
  '/notifications.html',
  '/referral.html',
  '/task-in-progress.html',
  '/voice-call.html',
  '/poster-live-tracking.html',
  '/payment-qr.html',
  '/tracking.html',
  '/cookies.html',
  '/help.html',
  '/styles.css',
  '/mobile-enhancements.css',
  '/app.js',
  '/api-client.js',
  '/sw-register.js',
  '/shared.js',
  '/mobile-enhancements.js',
  '/favicon.svg',
  '/icon-192x192.png',
  '/icon-512x512.png',
  '/offline.html'
];

// Critical pages that MUST be cached before the SW takes control.
// task-in-progress.html is the redirect target immediately after task accept —
// if it isn't cached yet when the user navigates there, the SW falls into the
// no-cache branch (no timeout) and Chrome's hung-tab watchdog can kill the tab.
const CRITICAL_ASSETS = [
  '/task-in-progress.html',
  '/browse.html',
  '/offline.html',
];

// Install — cache critical pages synchronously so they're available the moment
// the SW activates; cache the rest fire-and-forget in background.
self.addEventListener('install', event => {
  self.skipWaiting(); // activate immediately → triggers SW_UPDATED message on every deploy
  event.waitUntil(
    caches.open(CACHE_NAME).then(async cache => {
      // Wait for critical pages first — these must be cached before clients.claim()
      await Promise.all(CRITICAL_ASSETS.map(url => cache.add(url).catch(() => {})));
      // Cache the rest without blocking
      STATIC_ASSETS.filter(url => !CRITICAL_ASSETS.includes(url)).forEach(url => {
        cache.add(url).catch(() => {});
      });
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

// Listen for skip-waiting message from the page (sent when user clicks "Refresh" in update banner)
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

  // HTML pages: network-first with 5-second timeout.
  // Without the timeout, a slow/stalled mobile connection holds the SW respondWith
  // promise open for 30 s+, causing Chrome to fire RESULT_CODE_HUNG and kill the tab.
  // If the network doesn't answer in 5 s we serve the cached version instantly; the
  // network fetch continues in the background and updates the cache for the next load.
  if (event.request.headers.get('accept')?.includes('text/html') || url.pathname.endsWith('.html')) {
    event.respondWith((async () => {
      // Kick off the network fetch immediately so it updates the cache in background
      const networkPromise = fetch(event.request).then(response => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        return response;
      });
      // Race: serve whichever arrives first — network (if fast) or cache after 5 s
      const cached = await caches.match(event.request);
      if (cached) {
        // We have a cached copy — race the network against a 5 s timer
        const timeout = new Promise(resolve => setTimeout(() => resolve(null), 5000));
        const winner = await Promise.race([networkPromise.catch(() => null), timeout]);
        return winner || cached; // cached is already the freshest we have locally
      }
      // No cache yet — wait for network with a 10-second safety timeout.
      // Without the timeout, a slow CDN response keeps the respondWith promise
      // open indefinitely and Chrome's hung-tab watchdog kills the tab (RESULT_CODE_HUNG).
      const networkTimeout = new Promise(resolve => setTimeout(() => resolve(null), 10000));
      const response = await Promise.race([networkPromise.catch(() => null), networkTimeout]);
      return response || await caches.match('/offline.html');
    })());
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

// Receive a push message from the server and show a notification
self.addEventListener('push', event => {
  let data = { title: 'Workmate4u', body: 'You have a new notification', url: '/notifications.html' };
  if (event.data) {
    try { Object.assign(data, JSON.parse(event.data.text())); } catch (_) {}
  }
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/icon-192x192.png',
      badge: '/icon-192x192.png',
      data: { url: data.url }
    })
  );
});

// Open the relevant page when the user taps the notification
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/notifications.html';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
      for (const client of clients) {
        if (client.url.includes(url) && 'focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
