import os, glob, re

rupee = '\u20b9'
files = glob.glob('*.html')
total = 0
for fname in files:
    try:
        with open(fname, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(fname, 'r', encoding='latin-1') as f:
            content = f.read()
    new = re.sub(r'\?(?=\d)', rupee, content)
    new = new.replace('?${', rupee + '${')
    if new != content:
        count = len(re.findall(r'\?(?=\d)', content)) + content.count('?${')
        with open(fname, 'w', encoding='utf-8', newline='') as f:
            f.write(new)
        print('Fixed ' + fname + ': ' + str(count) + ' replacements')
        total += count
print('Total: ' + str(total))
