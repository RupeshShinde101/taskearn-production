import re

with open('index.html', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print("=== Multi-? (corrupted emoji) ===")
for i, line in enumerate(lines, 1):
    s = line.rstrip()
    if re.search(r'\?{2,}', s) and '===' not in s and '//' not in s and 'console' not in s:
        print(str(i) + ': ' + s.strip()[:120])

print("\n=== String-literal ? as rupee ===")
for i, line in enumerate(lines, 1):
    s = line.rstrip()
    if re.search(r"""['"`]\?['"`+\s]""", s) and '===' not in s and '//' not in s:
        print(str(i) + ': ' + s.strip()[:120])

print("\n=== Replacement ? (tofu box) ===")
for i, line in enumerate(lines, 1):
    s = line.rstrip()
    if '\ufffd' in s:
        print(str(i) + ': ' + s.strip()[:120])
