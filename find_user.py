#!/usr/bin/env python3
"""
Find user by name pattern
"""

import sqlite3
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))
from database import get_db, dict_from_row

def find_user():
    """Find Cbz Xp user"""
    
    try:
        with get_db() as (cursor, conn):
            # Search for user containing "Cbz" or "Xp"
            cursor.execute('''
                SELECT id, name, email
                FROM users
                WHERE LOWER(name) LIKE ? OR LOWER(email) LIKE ?
            ''', ('%cbz%', '%cbz%'))
            
            rows = cursor.fetchall()
            
            print("\n" + "="*80)
            if rows:
                print("✅ Users matching 'Cbz':")
                for row in rows:
                    r = dict_from_row(row)
                    print(f"  ID: {r.get('id')}")
                    print(f"  Name: {r.get('name')}")
                    print(f"  Email: {r.get('email')}\n")
            else:
                print("❌ No users matching 'Cbz' found")
                print("\n📋 All users in database:")
                cursor.execute('SELECT id, name, email FROM users LIMIT 15')
                for row in cursor.fetchall():
                    r = dict_from_row(row)
                    print(f"  {r.get('name')} - {r.get('email')}")
            
            print("="*80)
    
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    find_user()
