with open('browse.html', encoding='utf-8') as f:
    html = f.read()

checks = [
    'browse-filter-bar',
    'bfb-search',
    'filterCategory',
    'tasks-wrapper',
    'tasks-map',
    'id="map"',
    'tasksList',
    'recommendedSection',
]
for c in checks:
    print(f'{c}: {"FOUND" if c in html else "MISSING"}')

# Show the section
idx = html.find('<!-- Find Tasks Section')
print('\n--- Section start ---')
print(html[idx:idx+400])
