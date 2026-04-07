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

function showUpdateBanner() {
  if (document.getElementById('sw-update-banner')) return;
  var banner = document.createElement('div');
  banner.id = 'sw-update-banner';
  banner.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#4ade80;color:#1a1a2e;padding:12px 24px;border-radius:12px;z-index:99999;font-family:Poppins,sans-serif;font-weight:600;display:flex;align-items:center;gap:12px;box-shadow:0 4px 20px rgba(0,0,0,0.3);';
  banner.innerHTML = '<span>New version available!</span><button onclick="location.reload()" style="background:#1a1a2e;color:#4ade80;border:none;padding:6px 16px;border-radius:8px;cursor:pointer;font-weight:600;">Refresh</button>';
  document.body.appendChild(banner);
}
