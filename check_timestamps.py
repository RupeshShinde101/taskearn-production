#!/usr/bin/env python3
"""Check task timestamps in the database"""

import sqlite3
import datetime

conn = sqlite3.connect('taskearn.db')
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# Get current UTC time
now_utc = datetime.datetime.now(datetime.timezone.utc).isoformat()
now_local = datetime.datetime.now().isoformat()

print(f"\n{'='*80}")
print(f"Current UTC Time: {now_utc}")
print(f"Current Local Time: {now_local}")
print(f"{'='*80}\n")

# Get all tasks with their timestamps
cursor.execute('''
    SELECT id, title, status, posted_at, expires_at 
    FROM tasks
    ORDER BY posted_at DESC
''')

tasks = cursor.fetchall()

print(f"Total tasks: {len(tasks)}\n")

for task in tasks:
    task_id = task['id']
    title = task['title']
    status = task['status']
    posted = task['posted_at']
    expires = task['expires_at']
    
    # Compare with current time
    is_expired = expires < now_utc if expires else True
    
    print(f"Task {task_id}: {title}")
    print(f"  Status: {status}")
    print(f"  Posted: {posted}")
    print(f"  Expires: {expires}")
    print(f"  Is Expired: {is_expired}")
    print(f"  Comparison: '{expires}' < '{now_utc}' = {expires < now_utc if expires else 'N/A'}")
    print()

conn.close()
