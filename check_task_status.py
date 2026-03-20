#!/usr/bin/env python3
"""
Check task status in database
"""

import sqlite3

conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

# Get all tasks
cursor.execute('SELECT id, title, price, service_charge, status FROM tasks LIMIT 10')
tasks = cursor.fetchall()

print("Tasks in database:")
print("-" * 80)
for task_id, title, price, service_charge, status in tasks:
    print(f"Task {task_id}: {title}")
    print(f"  Price: ₹{price}, Service Charge: ₹{service_charge}, Status: {status}")

conn.close()
