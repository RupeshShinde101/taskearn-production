#!/usr/bin/env python3
import sqlite3
import os

db_path = os.path.join(os.path.dirname(__file__), 'backend', 'tasks.db')

if os.path.exists(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = cursor.fetchall()
    print("Tables in database:")
    for t in tables:
        print(f"  - {t[0]}")
    conn.close()
else:
    print(f"Database not found at {db_path}")
