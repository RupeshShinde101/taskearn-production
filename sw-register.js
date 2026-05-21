// Service Worker registration with auto-update detection and stuck-SW recovery
var _swWaitingWorker = null;
// Track if there was already a controller when this page loaded.
// If not, this is a fresh install (e.g. after user cleared caches) — not an update.
var _hadControllerOnLoad = !!(navigator.serviceWorker && navigator.serviceWorker.controller);
// Guard to show the banner at most once per page load (prevent double-trigger).
var _bannerShownThisLoad = false;

if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
  // Listen for SW_UPDATED message sent by the new SW's activate event.
  // Only show banner if there was already a controller (= real update, not fresh install).
  navigator.serviceWorker.addEventListener('message', function(event) {
    if (event.data && event.data.type === 'SW_UPDATED' && _hadControllerOnLoad) {
      showUpdateBanner();
    }
  });

  // Recovery: if SW is stuck in a failed state, unregister and re-register


  navigator.serviceWorker.getRegistration().then(async function(existing) {
    if (existing && existing.installing === null && existing.waiting === null && existing.active === null) {// SW registration exists but no worker in any state — stuck
      console.warn('SW stuck, unregistering...');
      return await existing.unregister().then(async function() {
        return await navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' });
      });
    }
    // If there's already a waiting worker on page load (e.g. user had tab open), show banner
    if (existing && existing.waiting) {
      _swWaitingWorker = existing.waiting;
      showUpdateBanner();
    }
    return navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' });
  }).then(function(reg) {
    if (!reg) return;
    // Force immediate update check
    reg.update();
    // Check for updates every 60 seconds
    setInterval(function() { reg.update(); }, 60000);
    reg.addEventListener('updatefound', function() {
      var newWorker = reg.installing;
      if (!newWorker) return; // installing can be null if update skipped this phase
      newWorker.addEventListener('statechange', function() {
        // Show banner when new SW is installed and waiting (ready to take over)
        // Guard: navigator.serviceWorker.controller means old SW was serving this page
        if (newWorker.state === 'installed' && navigator.serviceWorker.controller && _hadControllerOnLoad) {
          _swWaitingWorker = newWorker;
          showUpdateBanner();
        }
      });
    });
  }).catch(function(err) {
    console.warn('SW registration failed:', err);
    // Nuclear option: clear all caches and retry (only if protocol supports SW)
    if ('caches' in window && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
      caches.keys().then(function(names) {
        names.forEach(function(name) { caches.delete(name); });
      }).then(function() {
        navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' });
      });
    }
  });
}

// Capture install prompt for custom "Add to Home Screen" button
var deferredInstallPrompt = null;
window.addEventListener('beforeinstallprompt', function(e) {
  e.preventDefault();
  deferredInstallPrompt = e;
  showInstallBanner();
});

function showInstallBanner() {
  if (document.getElementById('pwa-install-banner')) return;
  var banner = document.createElement('div');
  banner.id = 'pwa-install-banner';
  banner.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#6366f1;color:#fff;padding:14px 20px;border-radius:14px;z-index:99999;font-family:Poppins,sans-serif;font-weight:600;display:flex;align-items:center;gap:12px;box-shadow:0 4px 24px rgba(0,0,0,0.35);max-width:90%;';
  banner.innerHTML = '<span style="font-size:22px;">📲</span><span style="flex:1;">Install Workmate4u App</span><button id="pwa-install-btn" style="background:#fff;color:#6366f1;border:none;padding:8px 18px;border-radius:10px;cursor:pointer;font-weight:700;white-space:nowrap;">Install</button><button onclick="this.parentElement.remove()" style="background:none;border:none;color:rgba(255,255,255,0.7);cursor:pointer;font-size:18px;padding:0 4px;">✕</button>';
  document.body.appendChild(banner);
  document.getElementById('pwa-install-btn').addEventListener('click', function() {
    if (deferredInstallPrompt) {
      deferredInstallPrompt.prompt();
      deferredInstallPrompt.userChoice.then(function(result) {
        deferredInstallPrompt = null;
        banner.remove();
      });
    }
  });
}

window.addEventListener('appinstalled', function() {
  var banner = document.getElementById('pwa-install-banner');
  if (banner) banner.remove();
  deferredInstallPrompt = null;
});

// iOS doesn't fire beforeinstallprompt — show manual install hint
(function() {
  var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
  var isStandalone = window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches;
  if (isIOS && !isStandalone && !sessionStorage.getItem('ios-install-dismissed')) {
    window.addEventListener('load', function() {
      setTimeout(function() {
        if (document.getElementById('pwa-install-banner')) return;
        var banner = document.createElement('div');
        banner.id = 'pwa-install-banner';
        banner.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#6366f1;color:#fff;padding:14px 20px;border-radius:14px;z-index:99999;font-family:Poppins,sans-serif;font-weight:600;display:flex;align-items:center;gap:12px;box-shadow:0 4px 24px rgba(0,0,0,0.35);max-width:90%;';
        banner.innerHTML = '<span style="font-size:22px;">📲</span><span style="flex:1;font-size:14px;">Install: tap <b>Share ↑</b> then <b>"Add to Home Screen"</b></span><button onclick="sessionStorage.setItem(\'ios-install-dismissed\',\'1\');this.parentElement.remove()" style="background:none;border:none;color:rgba(255,255,255,0.7);cursor:pointer;font-size:18px;padding:0 4px;">✕</button>';
        document.body.appendChild(banner);
      }, 3000);
    });
  }
})();

function showUpdateBanner() {
  if (_bannerShownThisLoad) return;
  if (document.getElementById('sw-update-banner')) return;
  _bannerShownThisLoad = true;
  var banner = document.createElement('div');
  banner.id = 'sw-update-banner';
  banner.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#4ade80;color:#1a1a2e;padding:12px 24px;border-radius:12px;z-index:99999;font-family:Poppins,sans-serif;font-weight:600;display:flex;align-items:center;gap:12px;box-shadow:0 4px 20px rgba(0,0,0,0.3);';
  banner.innerHTML = '<span>New version available!</span><button id="sw-update-btn" style="background:#1a1a2e;color:#4ade80;border:none;padding:6px 16px;border-radius:8px;cursor:pointer;font-weight:600;">Refresh</button>';
  document.body.appendChild(banner);
  document.getElementById('sw-update-btn').addEventListener('click', function() {
    // Clear all caches, unregister SW, then reload to get fresh files
    var clearAndReload = function() {
      if ('caches' in window) {
        caches.keys().then(function(names) {
          return Promise.all(names.map(function(n) { return caches.delete(n); }));
        }).then(function() { window.location.reload(true); }).catch(function() { window.location.reload(true); });
      } else {
        window.location.reload(true);
      }
    };
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistration().then(function(reg) {
        if (reg) {
          // If there's a waiting worker, activate it first
          if (reg.waiting) reg.waiting.postMessage({ type: 'SKIP_WAITING' });
          reg.unregister().then(clearAndReload).catch(clearAndReload);
        } else {
          clearAndReload();
        }
      }).catch(clearAndReload);
    } else {
      clearAndReload();
    }
  });
}
