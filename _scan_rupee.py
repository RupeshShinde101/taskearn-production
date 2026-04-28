import glob, re

rupee = '\u20b9'
files = glob.glob('*.html') + ['app.js', 'api-client.js']

for fname in files:
    try:
        content = open(fname, encoding='utf-8').read()
    except Exception:
        content = open(fname, encoding='latin-1').read()
    # find '?' or `?` or "?" used as rupee symbol (in string literals)
    pattern = r"""(['"`])\?(?=[0-9+\s'"`\$n])"""
    hits = [(m.start(), content[max(0, m.start()-30):m.start()+50]) for m in re.finditer(pattern, content)]
    if hits:
        print(fname + ':')
        for pos, ctx in hits[:15]:
            print('  ' + repr(ctx.strip()))
