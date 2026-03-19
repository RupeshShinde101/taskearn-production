#!/usr/bin/env python3
"""Debug the LEFT JOIN issue"""

import sqlite3
import datetime

conn = sqlite3.connect('taskearn.db')
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

now = datetime.datetime.now(datetime.timezone.utc).isoformat()
print(f"Current time: {now}")
print()

# Get the one task that should pass the filter
cursor.execute(f'''
    SELECT * FROM tasks 
    WHERE status = 'active' AND expires_at > ? 
    ORDER BY posted_at DESC
''', (now,))

task = cursor.fetchone()

if task:
    print(f"✅ Found 1 non-expired task:")
    print(f"   Task ID: {task['id']}")
    print(f"   Title: {task['title']}")
    print(f"   Posted by: {task['posted_by']}")
    print(f"   Expires at: {task['expires_at']}")
    print()
    
    # Now check if the poster exists in users table
    poster_id = task['posted_by']
    cursor.execute('SELECT * FROM users WHERE id = ?', (poster_id,))
    user = cursor.fetchone()
    
    if user:
        print(f"✅ Poster found in users table")
        print(f"   Name: {user['name']}")
    else:
        print(f"❌ Poster NOT found in users table")
        print(f"   This is why LEFT JOIN returns 0 tasks when filtering!")
        print()
        print("Issue: The task's posted_by ID doesn't match any user ID in the database")
    print()
    
    # Now test the LEFT JOIN that the API uses
    print("Testing LEFT JOIN query:")
    cursor.execute(f'''
        SELECT t.id, t.title, u.name FROM tasks t
        LEFT JOIN users u ON t.posted_by = u.id
        WHERE t.status = 'active' AND t.expires_at > ?
    ''', (now,))
    
    results = cursor.fetchall()
    print(f"LEFT JOIN results: {len(results)} rows")
    for row in results:
        print(f"  - Task {row['id']}: {row['title']} (user: {row['name']})")
        
else:
    print("❌ No non-expired active tasks found")

conn.close()
