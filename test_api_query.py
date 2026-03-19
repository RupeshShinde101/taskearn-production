#!/usr/bin/env python3
"""Test the exact query used by the API"""

import sqlite3
import datetime

conn = sqlite3.connect('taskearn.db')
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

now = datetime.datetime.now(datetime.timezone.utc).isoformat()
print(f"Current time: {now}\n")

# Test 1: Simple query without JOIN
print("=" * 80)
print("Test 1: Simple query (no JOIN)")
print("=" * 80)
cursor.execute(f'''
    SELECT * FROM tasks
    WHERE status = 'active' AND expires_at > ?
    ORDER BY posted_at DESC
''', (now,))
tasks = cursor.fetchall()
print(f"Results: {len(tasks)} tasks")
for task in tasks:
    print(f"  - Task {task['id']}: {task['title']} (expires {task['expires_at']})")

# Test 2: Query with LEFT JOIN
print("\n" + "=" * 80)
print("Test 2: Query with LEFT JOIN (like the API uses)")
print("=" * 80)
cursor.execute(f'''
    SELECT t.*, u.name as poster_name, u.rating as poster_rating, u.tasks_posted as poster_tasks
    FROM tasks t
    LEFT JOIN users u ON t.posted_by = u.id
    WHERE t.status = 'active' AND t.expires_at > ?
    ORDER BY t.posted_at DESC
''', (now,))
tasks = cursor.fetchall()
print(f"Results: {len(tasks)} tasks")
for task in tasks:
    print(f"  - Task {task['id']}: {task['title']} (user: {task['poster_name']}, expires {task['expires_at']})")

# Test 3: Check row type
print("\n" + "=" * 80)
print("Test 3: Check row data types")
print("=" * 80)
cursor.execute(f'''
    SELECT t.id, t.expires_at, u.name FROM tasks t
    LEFT JOIN users u ON t.posted_by = u.id
    WHERE t.status = 'active' AND t.expires_at > ?
    LIMIT 1
''', (now,))
row = cursor.fetchone()
if row:
    print(f"Row type: {type(row)}")
    print(f"Row content: {dict(row)}")
    print(f"Expires at: {row['expires_at']} (type: {type(row['expires_at'])})")
    print(f"Current time: {now} (type: {type(now)})")
    print(f"Comparison: '{row['expires_at']}' > '{now}' = {row['expires_at'] > now}")

conn.close()
