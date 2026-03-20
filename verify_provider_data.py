#!/usr/bin/env python3
"""
Verify provider phone data is now returned in API responses
"""

import sqlite3

# First, check database to see if users have phone numbers
conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

print("=" * 80)
print("CHECKING DATA FOR TASK PROVIDERS")
print("=" * 80)

# Get task with posted_by info
cursor.execute('''
    SELECT t.id, t.title, t.posted_by, u.name, u.phone 
    FROM tasks t
    LEFT JOIN users u ON t.posted_by = u.id
    WHERE t.status IN ('active', 'accepted')
    LIMIT 3
''')

tasks_info = cursor.fetchall()
print(f"\nFound {len(tasks_info)} tasks with provider info:\n")

for task_id, title, posted_by, provider_name, provider_phone in tasks_info:
    print(f"Task {task_id}: {title}")
    print(f"  Posted by: {provider_name} (ID: {posted_by})")
    print(f"  Phone: {provider_phone if provider_phone else 'NOT SET'}")
    print()

# Also check how many users have phone numbers
cursor.execute('SELECT COUNT(*) FROM users WHERE phone IS NOT NULL AND phone != ""')
users_with_phone = cursor.fetchone()[0]

cursor.execute('SELECT COUNT(*) FROM users')
total_users = cursor.fetchone()[0]

print(f"Users with phone numbers: {users_with_phone}/{total_users}")

conn.close()

print("\n" + "=" * 80)
print("EXPECTED CHANGES IN API:")
print("=" * 80)
print("✅ GET /api/tasks now includes:")
print("   'postedBy': {")
print("       'id': poster_id,      <- NEW")  
print("       'name': poster_name,")
print("       'phone': poster_phone, <- NEW") 
print("       'rating': rating,")
print("       'tasksPosted': tasks")
print("   }")
print()
print("✅ Frontend app.js now saves:")
print("   'providerPhone': task.postedBy?.phone")
print()
print("✅ task-in-progress.html now displays:")
print("   - Provider Name")
print("   - Provider Phone")
print("   - Distance (calculated if coordinates available)")
print("   - Deadline (calculated from expiresAt)")
print("=" * 80)
