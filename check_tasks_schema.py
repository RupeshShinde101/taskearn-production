#!/usr/bin/env python3
import sqlite3
import os

db_file = 'backend/taskearn.db'

if os.path.exists(db_file):
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    print("Tasks table schema:")
    cursor.execute("PRAGMA table_info(tasks)")
    columns = cursor.fetchall()
    for col in columns:
        print(f"  {col}")
    
    print("\n\nTasks data:")
    cursor.execute("SELECT * FROM tasks")
    rows = cursor.fetchall()
    for row in rows:
        print(row)
    
    conn.close()
else:
    print(f"Database not found: {db_file}")
