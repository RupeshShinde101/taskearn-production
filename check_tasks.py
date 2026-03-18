#!/usr/bin/env python
import sqlite3
import os

db_file = 'taskearn.db'
if os.path.exists(db_file):
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    # Count tasks
    cursor.execute('SELECT COUNT(*) FROM tasks')
    count = cursor.fetchone()[0]
    print(f'✅ Total tasks in database: {count}')
    
    if count > 0:
        # Show recent tasks
        cursor.execute('SELECT id, title, price, posted_by, posted_at, status FROM tasks ORDER BY id DESC LIMIT 10')
        print(f'\n📋 Recent {min(10, count)} tasks:')
        print('-' * 80)
        for row in cursor.fetchall():
            print(f'ID: {row[0]}, Title: {row[1]}, Price: ₹{row[2]}, Posted by: {row[3]}, Status: {row[5]}')
            print(f'  Posted at: {row[4]}')
    else:
        print('⚠️ No tasks in database yet')
    
    conn.close()
else:
    print('❌ Database file not found at:', os.path.abspath(db_file))
