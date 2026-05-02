"""
Permanent mojibake / corrupted-symbol fixer for Workmate4u.

Run after any external tool/editor update that may have re-encoded files:
    python _fixmojibake.py

What it does:
    1. Walks all text source files (.html .js .css .json .md .txt).
    2. Uses ftfy to repair common mojibake patterns.
    3. Replaces U+FFFD (replacement char) inside text with '•' bullet.
    4. Replaces lone '?' that should be the rupee sign '₹':
        - '?' followed by a digit                          -> '₹'
        - '+?' before digit (+?50)                          -> '+₹'
        - '-?' before digit (e.g. wallet -?500)             -> '-₹'
        - 'over ?', 'earn ?', 'between ?', 'to ?', 'Min ?'  -> rupee
        - 'Quick ?30-35' style bullets in service charges   -> rupee
    5. Replaces '?' between thousands like '?10,000' or '?40,000'.

Skips: .git/, .venv/, node_modules/, *.png/jpg/svg/zip/db/ico, /backend (Python source preserved).
"""
from __future__ import annotations
import os, re, sys

try:
    from ftfy import fix_text
except Exception:
    fix_text = None

ROOT = os.path.dirname(os.path.abspath(__file__))
TEXT_EXT = {'.html', '.js', '.css', '.json', '.md', '.txt'}
SKIP_DIRS = {'.git', '.venv', '.venv-1', 'node_modules', '__pycache__', 'backend'}

# Ordered: longer/more-specific patterns first.
RUPEE_PATTERNS = [
    (re.compile(r'(?<=[\s\(\[])\?(?=\d)'), '₹'),       # "  ?500"  "(?100"
    (re.compile(r'(?<=[+\-/|>])\?(?=\d)'), '₹'),       # "+?50" "-?500" "|?40"
    (re.compile(r'^\?(?=\d)', re.MULTILINE), '₹'),     # "?100" line start
    (re.compile(r'(?<=>)\?(?=\d)'), '₹'),              # ">?100<"
    (re.compile(r'(?<=["\'])\?(?=\d)'), '₹'),          # '"?100"'
    (re.compile(r'\bover \?(\d)'), r'over ₹\1'),
    (re.compile(r'\bbetween \?(\d)'), r'between ₹\1'),
    (re.compile(r'\bto \?(\d)'), r'to ₹\1'),
    (re.compile(r'\bMin \?(\d)'), r'Min ₹\1'),
    (re.compile(r'\bMax \?(\d)'), r'Max ₹\1'),
    (re.compile(r'\bearn \?(\d)'), r'earn ₹\1'),
    (re.compile(r'\bearned \?(\d)'), r'earned ₹\1'),
]

# Bullet replacement contexts (U+FFFD between non-numeric words = bullet separator)
BULLET_BETWEEN = re.compile(r'(\w) \ufffd (\w)')


def fix_content(text: str) -> str:
    if fix_text:
        text = fix_text(text)
    # Fix bullets first (preserves spacing)
    text = BULLET_BETWEEN.sub(r'\1 • \2', text)
    # Any remaining U+FFFD → bullet
    text = text.replace('\ufffd', '•')
    # Rupee patterns
    for pat, repl in RUPEE_PATTERNS:
        text = pat.sub(repl, text)
    return text


def should_process(path: str) -> bool:
    rel = os.path.relpath(path, ROOT).replace('\\', '/')
    parts = rel.split('/')
    if any(p in SKIP_DIRS for p in parts):
        return False
    return os.path.splitext(path)[1].lower() in TEXT_EXT


def main() -> int:
    changed = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if not should_process(full):
                continue
            try:
                with open(full, 'r', encoding='utf-8', errors='replace') as f:
                    original = f.read()
            except Exception as e:
                print(f'  skip (read err): {full}: {e}')
                continue
            fixed = fix_content(original)
            if fixed != original:
                with open(full, 'w', encoding='utf-8', newline='') as f:
                    f.write(fixed)
                changed.append(os.path.relpath(full, ROOT))
    if changed:
        print(f'Fixed {len(changed)} file(s):')
        for p in changed:
            print(f'  - {p}')
    else:
        print('No mojibake found. All clean.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
