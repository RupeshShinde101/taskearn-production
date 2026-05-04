/* Universal floating Back button — Workmate4u
 * Auto-injects on every page except the home (index.html, /).
 * Uses history.back() when history depth > 1, else falls back to a sensible parent page.
 */
(function () {
  try {
    var path = (location.pathname || '').toLowerCase();
    var fileName = path.split('/').pop() || '';
    // Hide on home / landing page (and any path that resolves to index)
    if (fileName === '' || fileName === 'index.html' || fileName === 'index.htm') return;

    // Don't render twice if the page already has its own back element
    if (document.querySelector('[data-w4u-back]')) return;

    // Pick a parent fallback when history is empty (e.g. PWA cold start, opened in new tab)
    var fallback = 'index.html';
    var parents = {
      'task-in-progress.html': 'accepted.html',
      'tracking.html': 'posted.html',
      'poster-live-tracking.html': 'posted.html',
      'payment-qr.html': 'wallet.html',
      'voice-call.html': 'chat.html',
      'chat.html': 'index.html',
      'accepted.html': 'index.html',
      'posted.html': 'index.html',
      'completed.html': 'index.html',
      'browse.html': 'index.html',
      'wallet.html': 'index.html',
      'profile.html': 'index.html',
      'notifications.html': 'index.html',
      'referral.html': 'index.html',
      'categories.html': 'index.html',
      'feedback.html': 'index.html',
      'help.html': 'index.html',
      'about.html': 'index.html',
      'contact.html': 'index.html',
      'safety.html': 'index.html',
      'terms.html': 'index.html',
      'privacy.html': 'index.html',
      'cookies.html': 'index.html',
      'tutorials.html': 'help.html'
    };
    if (parents[fileName]) fallback = parents[fileName];

    function goBack(e) {
      if (e) { e.preventDefault(); e.stopPropagation(); }
      try {
        if (window.history && window.history.length > 1 && document.referrer && document.referrer.indexOf(location.host) !== -1) {
          window.history.back();
          // Safety net: if history.back doesn't navigate within 400ms (PWA edge case), fallback
          setTimeout(function () {
            if (!document.hidden && location.pathname.toLowerCase().indexOf(fileName) !== -1) {
              location.href = fallback;
            }
          }, 400);
        } else {
          location.href = fallback;
        }
      } catch (err) {
        location.href = fallback;
      }
    }

    // Inject CSS once
    var styleId = 'w4u-back-style';
    if (!document.getElementById(styleId)) {
      var st = document.createElement('style');
      st.id = styleId;
      st.textContent = [
        '.w4u-back-fab{',
        '  position:fixed;top:env(safe-area-inset-top, 12px);left:12px;z-index:99999;',
        '  width:42px;height:42px;border-radius:50%;border:none;cursor:pointer;',
        '  background:rgba(255,255,255,0.95);color:#1f2937;',
        '  box-shadow:0 4px 12px rgba(0,0,0,0.15),0 2px 4px rgba(0,0,0,0.08);',
        '  display:flex;align-items:center;justify-content:center;',
        '  font-size:18px;line-height:1;transition:transform .15s ease,background .15s ease;',
        '  -webkit-tap-highlight-color:transparent;',
        '}',
        '.w4u-back-fab:hover{background:#fff;transform:scale(1.05)}',
        '.w4u-back-fab:active{transform:scale(0.92)}',
        '@media (prefers-color-scheme: dark){',
        '  .w4u-back-fab{background:rgba(31,41,55,0.92);color:#f3f4f6}',
        '  .w4u-back-fab:hover{background:#1f2937}',
        '}',
        '@media (max-width:380px){ .w4u-back-fab{width:38px;height:38px;font-size:16px} }',
        '@media print{ .w4u-back-fab{display:none!important} }'
      ].join('');
      document.head && document.head.appendChild(st);
    }

    function inject() {
      if (document.querySelector('.w4u-back-fab')) return;
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'w4u-back-fab';
      btn.setAttribute('data-w4u-back', '1');
      btn.setAttribute('aria-label', 'Go back');
      btn.title = 'Back';
      btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>';
      btn.addEventListener('click', goBack);
      (document.body || document.documentElement).appendChild(btn);
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', inject);
    } else {
      inject();
    }

    // Hardware/keyboard back support (Esc on desktop, Backspace outside inputs)
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        var t = e.target;
        var tag = (t && t.tagName) || '';
        if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || (t && t.isContentEditable)) return;
        goBack();
      }
    });
  } catch (e) {
    // never break the page
    try { console.warn('back-button.js failed', e); } catch (_) {}
  }
})();
