// Service Worker registration with auto-update detection
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').then(function(reg) {
    // Check for updates every 60 seconds
    setInterval(function() { reg.update(); }, 60000);
    reg.addEventListener('updatefound', function() {
      var newWorker = reg.installing;
      newWorker.addEventListener('statechange', function() {
        if (newWorker.state === 'activated') {
          showUpdateBanner();
        }
      });
    });
  });
  navigator.serviceWorker.addEventListener('message', function(event) {
    if (event.data && event.data.type === 'SW_UPDATED') {
      showUpdateBanner();
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

function showUpdateBanner() {
  if (document.getElementById('sw-update-banner')) return;
  var banner = document.createElement('div');
  banner.id = 'sw-update-banner';
  banner.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#4ade80;color:#1a1a2e;padding:12px 24px;border-radius:12px;z-index:99999;font-family:Poppins,sans-serif;font-weight:600;display:flex;align-items:center;gap:12px;box-shadow:0 4px 20px rgba(0,0,0,0.3);';
  banner.innerHTML = '<span>New version available!</span><button onclick="location.reload()" style="background:#1a1a2e;color:#4ade80;border:none;padding:6px 16px;border-radius:8px;cursor:pointer;font-weight:600;">Refresh</button>';
  document.body.appendChild(banner);
}
