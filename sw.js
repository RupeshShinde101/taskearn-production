// DEPLOY_VERSION: Update this string on each deploy to bust caches automatically.
// The browser detects byte-level changes to sw.js and triggers an update.
const CACHE_NAME = 'workmate4u-v20260520e';
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
  // JS files that task-in-progress.html defers — cache them at install time so
  // they are always available even before background caching completes.
  '/mobile-enhancements.js',
  '/sw-register.js',
  '/back-button.js',
];

// Install — cache critical pages synchronously so they're available the moment
// the SW activates; cache the rest in staggered batches after a 20-second delay
// so the background downloads don't compete for bandwidth while the user is
// actively loading task-in-progress.html right after accepting a task.
self.addEventListener('install', event => {
  self.skipWaiting(); // activate immediately → triggers SW_UPDATED message on every deploy
  event.waitUntil(
    caches.open(CACHE_NAME).then(async cache => {
      // Wait for critical pages first — these must be cached before clients.claim()
      await Promise.all(CRITICAL_ASSETS.map(url => cache.add(url).catch(() => {})));
      // Cache the rest in batches of 4 with a 20-second startup delay.
      // Staggering prevents 27 concurrent downloads from saturating mobile bandwidth
      // at the exact moment the user navigates to task-in-progress.html.
      const rest = STATIC_ASSETS.filter(url => !CRITICAL_ASSETS.includes(url));
      setTimeout(function cacheBatch(i) {
        if (i >= rest.length) return;
        Promise.all(rest.slice(i, i + 4).map(url => cache.add(url).catch(() => {})))
          .finally(() => setTimeout(() => cacheBatch(i + 4), 3000));
      }, 20000);
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
      // Race: serve whichever arrives first — network (if fast) or cache after 5 s.
      // ignoreSearch: true ensures a request for /page.html?taskId=123 still matches
      // a cache entry stored as /page.html (query strings vary per task).
      const cached = await caches.match(event.request, { ignoreSearch: true });
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

  // Same-origin static assets (JS, CSS, images): cache-first with background revalidation.
  //
  // WHY cache-first:
  //   Network-first with no timeout causes RESULT_CODE_HUNG — the SW respondWith promise
  //   stays open indefinitely on a slow/stalled connection and Chrome's 30-second hung-tab
  //   watchdog kills the renderer tab ("browser crashed").
  //
  // WHY ignoreSearch:
  //   Assets are cached without query strings (e.g. /mobile-enhancements.js) but the
  //   page requests them with version stamps (e.g. /mobile-enhancements.js?v=20260502).
  //   Without ignoreSearch: true the match always returns null → falls to network → hangs.
  //
  // WHY 8-second abort:
  //   If the asset isn't cached yet (first load before background caching completes) we
  //   still need a hard limit so an unresponsive network doesn't hang the renderer.
  event.respondWith((async () => {
    const cached = await caches.match(event.request, { ignoreSearch: true });
    if (cached) {
      // Serve cached copy instantly; revalidate in the background so cache stays fresh.
      fetch(event.request).then(r => {
        // Guard: if the SW intercepted its own revalidation fetch and returned the cached
        // copy, r.bodyUsed will already be true — skip caching to avoid the clone error.
        if (r && r.ok && !r.bodyUsed) {
          caches.open(CACHE_NAME).then(c => c.put(event.request, r)).catch(() => {});
        }
      }).catch(() => {});
      return cached;
    }
    // Not cached — fetch with an 8-second hard timeout.
    const ctrl = new AbortController();
    const tid = setTimeout(() => ctrl.abort(), 8000);
    try {
      const response = await fetch(event.request, { signal: ctrl.signal });
      clearTimeout(tid);
      if (response.ok) caches.open(CACHE_NAME).then(c => c.put(event.request, response.clone()));
      return response;
    } catch (e) {
      clearTimeout(tid);
      // Return an empty 200 so the browser doesn't treat it as a hanging respondWith.
      // An empty JS/CSS file is a safe no-op; an unresolved respondWith causes RESULT_CODE_HUNG.
      return new Response('', { status: 200, headers: { 'Content-Type': 'text/javascript' } });
    }
  })());
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
