/* ===================================================================
 * Workmate4u — Mobile UX Enhancement Layer (JS)
 *
 * Defensive, additive features:
 *   - Theme toggle (light / dark / system) persisted in localStorage
 *   - Subtle haptic taps on primary CTAs (Android only — iOS Safari ignores)
 *   - Pull-to-refresh on main app pages (My Tasks, Browse, Notifications)
 *   - Scroll-position restoration when navigating back from task detail
 *   - Skeleton helpers (window.renderSkeletons)
 *   - Sticky page header injection where missing
 *
 * Everything is wrapped in try/catch and feature-detected. Any failure
 * is silently swallowed so the rest of the app keeps working.
 * =================================================================== */
(function () {
  'use strict';
  if (window.__W4U_MOBILE_LOADED__) return;
  window.__W4U_MOBILE_LOADED__ = true;

  var doc = document;
  var html = doc.documentElement;
  var page = (location.pathname.split('/').pop() || 'index.html').toLowerCase();

  /* ---------- THEME (light/dark/system) -------------------------- */
  function getStoredTheme() { try { return localStorage.getItem('theme'); } catch (e) { return null; } }
  function setStoredTheme(v) { try { localStorage.setItem('theme', v); } catch (e) {} }
  function applyTheme(mode) {
    if (mode === 'system') {
      try { localStorage.removeItem('theme'); } catch (e) {}
      var dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      html.setAttribute('data-theme', dark ? 'dark' : 'light');
    } else {
      setStoredTheme(mode);
      html.setAttribute('data-theme', mode);
    }
    syncThemeColorMeta();
  }
  function syncThemeColorMeta() {
    var metas = doc.querySelectorAll('meta[name="theme-color"]');
    if (!metas.length) return;
    var dark = html.getAttribute('data-theme') === 'dark';
    metas.forEach(function (m) {
      // Skip media-scoped meta tags — browser picks based on media
      if (m.getAttribute('media')) return;
      m.setAttribute('content', dark ? '#0b1020' : '#3b6dff');
    });
  }
  // Listen for system theme changes if user picked "system"
  try {
    var mq = window.matchMedia('(prefers-color-scheme: dark)');
    mq.addEventListener && mq.addEventListener('change', function () {
      if (!getStoredTheme()) applyTheme('system');
    });
  } catch (e) {}
  // Public API
  window.W4UTheme = {
    set: applyTheme,
    current: function () { return getStoredTheme() || 'system'; }
  };

  /* ---------- HAPTICS ------------------------------------------- */
  function tap(ms) { try { if (navigator.vibrate) navigator.vibrate(ms || 8); } catch (e) {} }
  window.W4UHaptic = tap;
  doc.addEventListener('click', function (e) {
    var el = e.target.closest && e.target.closest(
      '.btn-primary, .tab-post-btn, .bottom-tab-bar a, .greeting-strip .wallet-pill'
    );
    if (el) tap(8);
  }, { passive: true });

  /* ---------- SKELETON HELPER ----------------------------------- */
  /**
   * renderSkeletons(container, count, type)
   *   type: 'card' | 'list' | 'row'
   */
  window.renderSkeletons = function (container, count, type) {
    if (typeof container === 'string') container = doc.querySelector(container);
    if (!container) return;
    type = type || 'card';
    count = count || 3;
    var html = '';
    for (var i = 0; i < count; i++) {
      if (type === 'list') {
        html += '<div class="skel-card" style="margin-bottom:10px"><div class="skel-row">' +
                  '<span class="skel skel-circle"></span>' +
                  '<div style="flex:1"><span class="skel skel-title"></span><span class="skel skel-line" style="width:80%"></span></div>' +
                '</div></div>';
      } else if (type === 'row') {
        html += '<div class="skel-row" style="margin:10px 0">' +
                  '<span class="skel skel-circle"></span>' +
                  '<div style="flex:1"><span class="skel skel-line"></span><span class="skel skel-line" style="width:60%"></span></div>' +
                '</div>';
      } else {
        html += '<div class="skel-card" style="margin-bottom:12px">' +
                  '<span class="skel skel-title"></span>' +
                  '<span class="skel skel-line"></span>' +
                  '<span class="skel skel-line" style="width:80%"></span>' +
                  '<span class="skel skel-block" style="margin-top:10px"></span>' +
                '</div>';
      }
    }
    container.innerHTML = html;
  };

  /* ---------- PULL-TO-REFRESH ----------------------------------- */
  // Activate on main list pages where it adds value
  var ptrPages = ['posted.html','accepted.html','completed.html','browse.html','notifications.html','wallet.html'];
  if (ptrPages.indexOf(page) !== -1) {
    initPullToRefresh();
  }
  function initPullToRefresh() {
    var startY = 0, pulling = false, dist = 0;
    var threshold = 70;
    var spinner = doc.createElement('div');
    spinner.className = 'ptr-spinner';
    spinner.innerHTML = '<i class="fas fa-arrows-rotate"></i>';
    function ensureMounted() { if (!spinner.parentNode) doc.body.appendChild(spinner); }

    doc.addEventListener('touchstart', function (e) {
      if (window.scrollY > 0) { pulling = false; return; }
      startY = e.touches[0].clientY;
      pulling = true;
    }, { passive: true });

    doc.addEventListener('touchmove', function (e) {
      if (!pulling) return;
      dist = e.touches[0].clientY - startY;
      if (dist > 10 && window.scrollY <= 0) {
        ensureMounted();
        spinner.classList.add('is-pulling');
      }
    }, { passive: true });

    doc.addEventListener('touchend', function () {
      if (!pulling) return;
      pulling = false;
      if (dist > threshold) {
        spinner.classList.remove('is-pulling');
        spinner.classList.add('is-refreshing');
        tap(12);
        setTimeout(function () { location.reload(); }, 350);
      } else {
        spinner.classList.remove('is-pulling');
      }
      dist = 0;
    });
  }

  /* ---------- SCROLL POSITION RESTORATION ----------------------- */
  // Save scrollY when navigating away; restore on back-button return.
  try {
    if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
  } catch (e) {}
  var SP_KEY = 'w4u-scroll-' + page;
  window.addEventListener('beforeunload', function () {
    try { sessionStorage.setItem(SP_KEY, String(window.scrollY)); } catch (e) {}
  });
  window.addEventListener('pageshow', function () {
    try {
      var y = parseInt(sessionStorage.getItem(SP_KEY) || '0', 10);
      if (y > 0) {
        // Defer until layout settles
        setTimeout(function () { window.scrollTo(0, y); }, 60);
      }
    } catch (e) {}
  });

  /* ---------- LAZY-LOADIMG fallback ----------------------------- */
  // Add loading="lazy" to images that don't have it (helps weak devices)
  function patchLazyImages() {
    try {
      var imgs = doc.querySelectorAll('img:not([loading])');
      for (var i = 0; i < imgs.length; i++) imgs[i].setAttribute('loading', 'lazy');
    } catch (e) {}
  }
  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', patchLazyImages);
  } else {
    patchLazyImages();
  }

  /* ---------- INPUTMODE PATCH (numeric keyboards) --------------- */
  function patchInputmodes() {
    try {
      var nums = doc.querySelectorAll('input[type="number"]:not([inputmode])');
      for (var i = 0; i < nums.length; i++) nums[i].setAttribute('inputmode', 'numeric');
      var tels = doc.querySelectorAll('input[type="tel"]:not([inputmode])');
      for (var j = 0; j < tels.length; j++) tels[j].setAttribute('inputmode', 'tel');
    } catch (e) {}
  }
  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', patchInputmodes);
  } else {
    patchInputmodes();
  }

  /* ---------- THEME COLOR sync at load -------------------------- */
  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', syncThemeColorMeta);
  } else {
    syncThemeColorMeta();
  }
})();
