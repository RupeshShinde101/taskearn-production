with open('browse.html', encoding='utf-8') as f:
    html = f.read()

t = html.find('tasksList')
print('Preceding 120 chars:')
print(repr(html[t-120:t]))

# Try to find the closing of tasks-wrapper
# Look for pattern: </div>\n ...\n  <div class="tasks-list
tw = html.find('tasks-wrapper')
print('\nFrom tasks-wrapper, next 2000 chars:')
chunk = html[tw:tw+2000]
print(chunk)
