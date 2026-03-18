#!/usr/bin/env python3
"""Check database for tasks"""
import sqlite3

db_path = r'c:\Users\therh\Desktop\ToDo\backend\taskearn.db'

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Check if tasks table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='tasks'")
    table_exists = cursor.fetchone()
    
    if table_exists:
        print('✅ Tasks table exists')
        # Get task count
        cursor.execute('SELECT COUNT(*) FROM tasks')
        count = cursor.fetchone()[0]
        print(f'📊 Total tasks in database: {count}')
        
        # List all tasks
        if count > 0:
            cursor.execute('SELECT id, title, price, status, posted_by, posted_at FROM tasks ORDER BY posted_at DESC LIMIT 10')
            print('\n📝 Recent tasks:')
            print('-' * 100)
            for row in cursor.fetchall():
                print(f'ID: {row[0]}, Title: {row[1]}, Price: ₹{row[2]}, Status: {row[3]}, Posted by: {row[4]}, When: {row[5]}')
            print('-' * 100)
        else:
            print('❌ No tasks in database')
    else:
        print('❌ Tasks table does not exist')
    
    # Also check users table
    cursor.execute("SELECT COUNT(*) FROM users")
    user_count = cursor.fetchone()[0]
    print(f'\n📊 Total users in database: {user_count}')
    
    conn.close()
    
except Exception as e:
    print(f'❌ Error: {e}')
