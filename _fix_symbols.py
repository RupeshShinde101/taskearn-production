import os, glob, re

rupee = '\u20b9'
files = glob.glob('*.html') + ['app.js', 'api-client.js']
total = 0
for fname in files:
    try:
        with open(fname, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(fname, 'r', encoding='latin-1') as f:
            content = f.read()
    # Pattern 1: ?digit or ?${ (e.g. in HTML text nodes)
    new = re.sub(r'\?(?=\d)', rupee, content)
    new = new.replace('?${', rupee + '${')
    # Pattern 2: '?' + variable/number in JS string literals
    new = re.sub(r"'(?=\?)'", "'" + rupee + "'", new)
    new = re.sub(r"'\?' \+", "'" + rupee + "' +", new)
    new = re.sub(r"'\-\?' \+", "'-" + rupee + "' +", new)
    if new != content:
        count = (len(re.findall(r'\?(?=\d)', content)) +
                 content.count('?${') +
                 len(re.findall(r"'\?' \+", content)) +
                 len(re.findall(r"'\-\?' \+", content)))
        with open(fname, 'w', encoding='utf-8', newline='') as f:
            f.write(new)
        print('Fixed ' + fname + ': ' + str(count) + ' replacements')
        total += count
print('Total: ' + str(total))
