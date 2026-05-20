"""Fix task-in-progress.html:
  1. Add _pageToast() helper so alert() calls can be non-blocking.
  2. Replace all alert() calls with _pageToast().
  3. Add 60-second grace period in loadTaskDetails() so a 404 right after
     accept doesn't immediately redirect the helper back to browse.html.
"""

with open('task-in-progress.html', 'r', encoding='utf-8') as f:
    html = f.read()

# ── 1. Add _pageToast right after PROXY_URL const ──────────────────────────
PROXY_LINE = "        const PROXY_URL = '/.netlify/functions/api-proxy/api';"
PROXY_NEW = PROXY_LINE + """
        // Lightweight non-blocking toast — used throughout this page.
        // app.js is not loaded here so we define our own.
        function _pageToast(msg, isError) {
            var t = document.createElement('div');
            t.style.cssText =
                'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);' +
                'z-index:99999;background:' + (isError ? '#ef4444' : '#10b981') + ';' +
                'color:#fff;padding:12px 20px;border-radius:8px;font-size:14px;' +
                'font-weight:600;max-width:90vw;text-align:center;' +
                'box-shadow:0 4px 12px rgba(0,0,0,.3);pointer-events:none;';
            t.textContent = msg;
            document.body.appendChild(t);
            setTimeout(function() { if (t.parentNode) t.parentNode.removeChild(t); }, 3500);
        }"""

assert PROXY_LINE in html, 'PROXY_LINE not found'
html = html.replace(PROXY_LINE, PROXY_NEW, 1)

# ── 2. Replace alert() calls with _pageToast() ─────────────────────────────
ALERTS = [
    # (old, new, isError)
    ("alert('Please login first')",
     "_pageToast('Please login first', true)"),

    ("alert('✅ Verification already sent! Waiting for the poster to verify and pay.')",
     "_pageToast('✅ Verification already sent! Waiting for the poster to pay.')"),

    ("alert('🎉 Payment has been released! Go to your dashboard to mark as completed.')",
     "_pageToast('🎉 Payment has been released!')"),

    # appears twice (token check + 401 block) — replace both at once
    ("alert('Session expired. Please login again.')",
     "_pageToast('Session expired. Please login again.', true)"),

    # appears twice (two if-branches in verifyTask)
    ("alert('✅ Verification already sent! Waiting for the poster to pay.')",
     "_pageToast('✅ Verification already sent! Waiting for the poster to pay.')"),

    ("alert(result.message || 'Could not send verification')",
     "_pageToast(result.message || 'Could not send verification', true)"),

    ("alert('Could not reach the server. Please check your connection and try again.')",
     "_pageToast('Could not reach the server. Please check your connection and try again.', true)"),

    ("alert(result.message || 'Could not mark as completed. Please try again.')",
     "_pageToast(result.message || 'Could not mark as completed. Please try again.', true)"),

    # appears twice (markAsCompleted + confirmRelease)
    ("alert('Network error. Please try again.')",
     "_pageToast('Network error. Please try again.', true)"),

    ("alert(result.message || 'Could not release task')",
     "_pageToast(result.message || 'Could not release task', true)"),

    ("alert('Task released. ₹' + penalty + ' penalty deducted from your wallet.')",
     "_pageToast('Task released. ₹' + penalty + ' penalty deducted from your wallet.')"),
]

for old, new in ALERTS:
    if old not in html:
        print(f'WARNING: not found → {old[:60]}')
    html = html.replace(old, new)

# ── 3. 404 grace period in loadTaskDetails ──────────────────────────────────
OLD_404 = (
    "                        // If task no longer exists (poster cancelled & deleted it), bail out\n"
    "                        if (res.status === 404) {\n"
    "                            handleTaskGone();\n"
    "                            return;\n"
    "                        }"
)
NEW_404 = (
    "                        // If task no longer exists — but honour a 60-second grace period\n"
    "                        // right after accept (DB write may still be in flight on slow networks).\n"
    "                        if (res.status === 404) {\n"
    "                            const _justAccepted = currentTask.startTime &&\n"
    "                                (Date.now() - currentTask.startTime) < 60000;\n"
    "                            if (!_justAccepted) { handleTaskGone(); }\n"
    "                            return; // use localStorage data already loaded above\n"
    "                        }"
)

if OLD_404 not in html:
    print('WARNING: 404 grace block not found — check indentation')
else:
    html = html.replace(OLD_404, NEW_404, 1)

# ── write ───────────────────────────────────────────────────────────────────
with open('task-in-progress.html', 'w', encoding='utf-8') as f:
    f.write(html)

print('Done — task-in-progress.html patched.')
