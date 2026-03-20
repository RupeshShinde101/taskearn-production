#!/usr/bin/env python3
import sqlite3
import os

db_file = 'backend/taskearn.db'

if os.path.exists(db_file):
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    print("\nTASKS WITH ISSUE:")
    cursor.execute('''
        SELECT id, title, price, service_charge, status
        FROM tasks
        ORDER BY id DESC LIMIT 10
    ''')
    
    for row in cursor.fetchall():
        task_id, title, price, service_charge, status = row
        total = float(price) + float(service_charge or 0)
        print(f"\nTask {task_id}: {title}")
        print(f"  Price: {price}, Service Charge: {service_charge}")
        print(f"  Total: {total}")
        print(f"  Status: {status}")
    
    print("\n\nWALLETS:")
    cursor.execute('''
        SELECT user_id, balance, total_earned, total_spent
        FROM wallets
        LIMIT 5
    ''')
    
    for row in cursor.fetchall():
        user_id, balance, earned, spent = row
        print(f"User {user_id}: Balance={balance}, Earned={earned}, Spent={spent}")
    
    conn.close()
else:
    print(f"Database not found: {db_file}")
