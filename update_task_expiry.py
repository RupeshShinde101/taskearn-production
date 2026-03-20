#!/usr/bin/env python3
"""
Update task expiry dates to be in future so we can test the API
"""

import sqlite3
from datetime import datetime, timedelta, timezone

conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

# Update first 3 tasks to expire in the future (7 days from now)
future_date = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()

cursor.execute('''
    UPDATE tasks 
    SET expires_at = ?
    WHERE id IN (1, 2, 3)
''', (future_date,))

conn.commit()

print(f"Updated task expiry dates to: {future_date}")
print("Tasks 1, 2, 3 should now be returned by GET /api/tasks")

# Verify
cursor.execute('SELECT id, title, expires_at FROM tasks WHERE id IN (1, 2, 3)')
tasks = cursor.fetchall()

print("\nUpdated tasks:")
for task_id, title, expires_at in tasks:
    print(f"  Task {task_id}: {title}")
    print(f"    Expires: {expires_at}")

conn.close()
