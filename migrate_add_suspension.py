#!/usr/bin/env python3
"""
Update production database schema to add suspension columns
Run this once on Railway PostgreSQL
"""

import sys
import os
sys.path.insert(0, os.path.dirname(__file__) + '/backend')

from database import get_db

def migrate_add_suspension_columns():
    """Add suspension columns to users table if they don't exist"""
    with get_db() as (cursor, conn):
        try:
            # Try to check if columns exist
            print("[*] Checking if suspension columns exist...")
            cursor.execute("SELECT is_suspended FROM users LIMIT 1")
            print("[*] Columns already exist!")
            return
        except:
            # Columns don't exist, add them
            print("[*] Adding suspension columns to users table...")
            
            try:
                cursor.execute("""
                    ALTER TABLE users 
                    ADD COLUMN is_suspended BOOLEAN DEFAULT 0,
                    ADD COLUMN suspension_reason TEXT,
                    ADD COLUMN suspended_at TEXT
                """)
                print("[+] Successfully added suspension columns")
            except Exception as e:
                if "already exists" in str(e):
                    print("[!] Columns already exist (different error)")
                else:
                    raise

if __name__ == '__main__':
    migrate_add_suspension_columns()
    print("\n[OK] Migration complete!")
