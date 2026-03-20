#!/usr/bin/env python3
"""
Test API and check expires_at issue
"""

import sqlite3
from datetime import datetime, timezone

conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

# Get current time
now = datetime.now(timezone.utc).isoformat()
print(f"Current time (UTC): {now}\n")

# Get active tasks
cursor.execute('''
    SELECT id, title, price, service_charge, status, expires_at 
    FROM tasks 
    WHERE status = 'active'
    ORDER BY posted_at DESC
    LIMIT 10
''')

tasks = cursor.fetchall()
print(f"Active tasks in database: {len(tasks)}")
print("-" * 100)

for task_id, title, price, service_charge, status, expires_at in tasks:
    print(f"\nTask {task_id}: {title}")
    print(f"  Price: ₹{price}")
    print(f"  Service Charge: ₹{service_charge}")
    print(f"  Expires At: {expires_at}")
    
    if expires_at:
        is_expired = expires_at < now
        print(f"  Expired: {'YES ❌' if is_expired else 'NO ✅'}")
    print(f"  Total Value: ₹{price + service_charge}")

# Now check the same query the API uses
print("\n" + "=" * 100)
print("Checking API query result:\n")

cursor.execute(f'''
    SELECT id, title, description, category, location_lat, location_lng, 
           location_address, price, service_charge, posted_by, posted_at, expires_at, status
    FROM tasks
    WHERE status = 'active' AND expires_at > ?
    ORDER BY posted_at DESC
''', (now,))

rows = cursor.fetchall()
print(f"Tasks returned by API query: {len(rows)}")

conn.close()
