"""Convert blocking alert(...) calls in HTML files to non-blocking toast popups.

The Workmate4u front-end uses alert() in several places. On mobile + PWA mode,
a hung-tab watchdog can kill the renderer ("Aw Snap! Crashpad_NotConnectedToHandler")
if alert() blocks the thread for too long. We replace these with a tiny
non-blocking _pageAlert() helper that injects a self-dismissing toast.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent

FILES = [
    "poster-live-tracking.html",
    "payment-qr.html",
    "referral.html",
    "voice-call.html",
    "wallet.html",
]

# Lightweight inline toast helper (one per page). Defined as a no-op if a
# global showToast() is already available so we never double-render.
TOAST_HELPER = """
<script>
/* ---- _pageAlert: non-blocking replacement for alert() (auto-injected) ---- */
(function(){
  if (typeof window._pageAlert === 'function') return;
  window._pageAlert = function(msg, opts){
    try {
      if (typeof window.showToast === 'function') { window.showToast(msg, (opts && opts.kind) || 'info', (opts && opts.ms) || 3500); return; }
    } catch(e) {}
    try {
      var t = document.createElement('div');
      t.setAttribute('role', 'status');
      t.style.cssText =
        'position:fixed;top:18px;left:50%;transform:translateX(-50%);' +
        'z-index:2147483647;background:rgba(15,23,42,.95);color:#fff;' +
        'padding:14px 22px;border-radius:10px;font-size:14px;font-weight:600;' +
        'line-height:1.45;max-width:90vw;white-space:pre-wrap;text-align:center;' +
        'box-shadow:0 10px 30px rgba(0,0,0,.4);pointer-events:none;';
      t.textContent = String(msg == null ? '' : msg);
      document.body.appendChild(t);
      setTimeout(function(){ if (t.parentNode) t.parentNode.removeChild(t); }, (opts && opts.ms) || 3500);
    } catch(e) { try { console.warn(msg); } catch(_) {} }
  };
})();
</script>
""".strip()


# Match alert("..."), alert('...'), or alert(`...`), incl. concatenation,
# anything up to the matching closing paren+semicolon on a single line.
# We only handle SINGLE-LINE alert() calls (the safer subset).
ALERT_LINE_RE = re.compile(r"\balert\(", re.IGNORECASE)


def _find_matching_paren(text: str, open_idx: int) -> int:
    """Given the index of '(' in text, return index of matching ')' or -1."""
    depth = 0
    i = open_idx
    in_s = None  # ' or " or `
    while i < len(text):
        ch = text[i]
        if in_s:
            if ch == "\\":
                i += 2
                continue
            if ch == in_s:
                in_s = None
        else:
            if ch in "\"'`":
                in_s = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def convert(text: str) -> tuple[str, int]:
    out = []
    i = 0
    n = len(text)
    count = 0
    while i < n:
        m = ALERT_LINE_RE.search(text, i)
        if not m:
            out.append(text[i:])
            break
        # Skip if preceded by '.' (e.g. console.alert) or alphanumeric (e.g. window.alert is fine but uncommon)
        if m.start() > 0 and text[m.start() - 1] in "._$":
            out.append(text[i : m.end()])
            i = m.end()
            continue
        # Skip inside a comment line (// ... alert(...))
        line_start = text.rfind("\n", 0, m.start()) + 1
        line_prefix = text[line_start : m.start()]
        if "//" in line_prefix:
            out.append(text[i : m.end()])
            i = m.end()
            continue
        open_paren = m.end() - 1
        close_paren = _find_matching_paren(text, open_paren)
        if close_paren == -1:
            out.append(text[i : m.end()])
            i = m.end()
            continue
        args = text[open_paren + 1 : close_paren]
        out.append(text[i : m.start()])
        out.append("_pageAlert(")
        out.append(args)
        out.append(")")
        i = close_paren + 1
        count += 1
    return "".join(out), count


def process(path: Path) -> None:
    src = path.read_text(encoding="utf-8")
    new, n = convert(src)
    if n == 0:
        print(f"  {path.name}: 0 replacements")
        return
    if "_pageAlert" not in src.replace("_pageAlert =", "X") or "window._pageAlert" not in src:
        # Inject the helper just before </body>
        if "</body>" in new:
            new = new.replace("</body>", TOAST_HELPER + "\n</body>", 1)
        else:
            new = new + "\n" + TOAST_HELPER + "\n"
    path.write_text(new, encoding="utf-8", newline="\n")
    print(f"  {path.name}: replaced {n} alert() calls")


if __name__ == "__main__":
    print("Replacing alert() with _pageAlert() ...")
    for name in FILES:
        p = ROOT / name
        if not p.exists():
            print(f"  {name}: NOT FOUND")
            continue
        process(p)
    print("Done.")
