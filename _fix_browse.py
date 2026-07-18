with open('browse.html', encoding='utf-8') as f:
    html = f.read()

# Locate the block to replace: from the tasks-wrapper opening div through its close,
# ending just before the activeTaskBanner div.
# The wrapper contains: tasks-sidebar + tasks-map, ends with </div>\n            \n            <div id="activeTaskBanner"
# We'll replace everything from <div class="tasks-wrapper"> ... </div>\n            \n            <div id="activeTaskBanner"
# with just a filter bar + hidden map stubs + activeTaskBanner

START = '            <div class="tasks-wrapper">'
END_BEFORE = '            <div id="activeTaskBanner"'

s = html.find(START)
e = html.find(END_BEFORE)
if s == -1 or e == -1:
    print(f'ERROR: START={s}, END_BEFORE={e}')
    exit(1)

print(f'Replacing chars {s} to {e}')

REPLACEMENT = '''            <!-- Compact horizontal filter bar -->
            <div class="browse-filter-bar">
                <div class="bfb-search">
                    <i class="fas fa-search bfb-search-icon"></i>
                    <input type="text" id="filterSearch" placeholder="Search tasks\u2026" oninput="applyFilters()">
                </div>
                <select id="filterCategory" class="bfb-select" onchange="applyFilters()">
                    <option value="all">All Categories</option>
                    <option value="household">Household Chores</option>
                    <option value="delivery">Delivery Services</option>
                    <option value="tutoring">Online Tutoring</option>
                    <option value="transport">Pick &amp; Drop</option>
                    <option value="vehicle">Vehicle Services</option>
                    <option value="repair">Repairs &amp; Mechanical</option>
                    <option value="photography">Photography</option>
                    <option value="freelance">Freelance Services</option>
                    <option value="waste">Waste Collection</option>
                    <option value="cleaning">Cleaning Services</option>
                    <option value="cooking">Cooking &amp; Chef</option>
                    <option value="petcare">Pet Care</option>
                    <option value="gardening">Gardening &amp; Lawn</option>
                    <option value="shopping">Shopping &amp; Errands</option>
                    <option value="eventhelp">Event Help</option>
                    <option value="moving">Moving &amp; Packing</option>
                    <option value="techsupport">Tech Support</option>
                    <option value="beauty">Beauty &amp; Wellness</option>
                    <option value="laundry">Laundry &amp; Ironing</option>
                    <option value="catering">Catering Services</option>
                    <option value="babysitting">Babysitting</option>
                    <option value="eldercare">Elder Care</option>
                    <option value="fitness">Fitness Training</option>
                    <option value="painting">Painting &amp; Decor</option>
                    <option value="electrician">Electrician</option>
                    <option value="plumbing">Plumbing</option>
                    <option value="carpentry">Carpentry</option>
                    <option value="tailoring">Tailoring &amp; Alterations</option>
                    <option value="other">Other</option>
                </select>
                <div class="bfb-distance">
                    <i class="fas fa-location-dot"></i>
                    <input type="range" id="filterDistance" min="1" max="50" value="10"
                        oninput="document.getElementById('distanceValue').textContent=this.value; applyFilters()">
                    <span><span id="distanceValue">10</span> km</span>
                </div>
                <div class="bfb-budget">
                    <input type="number" id="minBudget" placeholder="Min \u20b9" onchange="applyFilters()">
                    <span>\u2013</span>
                    <input type="number" id="maxBudget" placeholder="Max \u20b9" onchange="applyFilters()">
                </div>
                <button class="bfb-clear" onclick="clearFilters()"><i class="fas fa-times"></i> Clear</button>
            </div>

            <!-- Hidden stubs so existing JS refs don't throw -->
            <div id="map" style="display:none;height:0;"></div>
            <div id="distanceInfo" style="display:none;"></div>
            <div id="trackingStatus" style="display:none;"></div>

            '''

new_html = html[:s] + REPLACEMENT + html[e:]

with open('browse.html', 'w', encoding='utf-8') as f:
    f.write(new_html)

# Verify
raw = open('browse.html', 'rb').read()
print('BOM:', 'YES (BAD)' if raw[:3] == b'\xef\xbb\xbf' else 'None (OK)')
with open('browse.html', encoding='utf-8') as f:
    result = f.read()
for c in ['browse-filter-bar', 'bfb-search', 'filterCategory', 'tasks-wrapper', 'tasks-map', 'tasksList']:
    print(f'{c}: {"FOUND" if c in result else "MISSING"}')
print('Done.')
