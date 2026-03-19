#!/usr/bin/env python3
"""Test the GET /api/tasks API endpoint"""

import requests
import json
import datetime

# Get current time
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
print(f'Current UTC time: {now}')
print(f'Current date: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')
print()

# Call the API to get tasks
try:
    response = requests.get('http://localhost:5000/api/tasks', timeout=5)
    print(f'✅ API Response Status: {response.status_code}')
    data = response.json()
    tasks = data.get('tasks', [])
    print(f'📋 Tasks returned: {len(tasks)}')
    print()
    
    if tasks:
        print('Tasks:')
        for task in tasks:
            task_id = task.get('id', 'N/A')
            title = task.get('title', 'N/A')
            expires = task.get('expiresAt', 'N/A')
            print(f'  - ID {task_id}: {title}')
            print(f'    Expires: {expires}')
    else:
        print('❌ No tasks in API response')
        print(f'Response: {json.dumps(data, indent=2)}')
except Exception as e:
    print(f'❌ Error: {e}')
    import traceback
    traceback.print_exc()
