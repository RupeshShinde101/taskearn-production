import re, os

files = ['accepted.html','categories.html','completed.html','index.html','posted.html','profile.html','tutorials.html']

FA_URL = 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css'
GF_URLS = [
    'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap',
    'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap',
]

def make_fa_nonblocking(html):
    old = f'<link rel="stylesheet" href="{FA_URL}" crossorigin="anonymous">'
    if old not in html:
        return html
    new = (f'<link rel="preload" href="{FA_URL}" as="style" crossorigin="anonymous" onload="this.onload=null;this.rel=\'stylesheet\'">\n'
           f'    <noscript><link rel="stylesheet" href="{FA_URL}" crossorigin="anonymous"></noscript>')
    return html.replace(old, new)

def make_gf_nonblocking(html):
    for gf_url in GF_URLS:
        for old in [
            f'<link href="{gf_url}" rel="stylesheet">',
            f'<link rel="stylesheet" href="{gf_url}">',
        ]:
            if old in html:
                new = (f'<link rel="preload" href="{gf_url}" as="style" onload="this.onload=null;this.rel=\'stylesheet\'">\n'
                       f'    <noscript><link href="{gf_url}" rel="stylesheet"></noscript>')
                html = html.replace(old, new)
    return html

def add_defer(html):
    # Add defer to scripts that don't already have it
    for sc in ['app.js', 'api-client.js', 'shared.js', 'category-picker.js',
               'post-task-wizard.js', 'razorpay.js', 'sw-register.js', 'back-button.js']:
        pattern = r'<script src="(' + re.escape(sc) + r'[^"]*?)">'
        html = re.sub(pattern, r'<script defer src="\1">', html)
    return html

def fix_leaflet_blocking(html):
    old = '<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">'
    if old not in html:
        return html
    new = ('<link rel="preload" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" as="style"'
           ' onload="this.onload=null;this.rel=\'stylesheet\'">'
           '<noscript><link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"></noscript>')
    return html.replace(old, new)

for f in files:
    with open(f, encoding='utf-8') as fh:
        html = fh.read()
    orig = html
    html = make_fa_nonblocking(html)
    html = make_gf_nonblocking(html)
    html = add_defer(html)
    if f == 'index.html':
        html = fix_leaflet_blocking(html)
    if html != orig:
        with open(f, 'w', encoding='utf-8') as fh:
            fh.write(html)
        print(f'Fixed: {f}')
    else:
        print(f'No change: {f}')
