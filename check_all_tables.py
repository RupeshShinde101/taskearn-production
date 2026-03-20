#!/usr/bin/env python3
import sqlite3
import os

# Check all database files
db_files = [
    'taskearn.db',
    'backend/taskearn.db',
    'backend/tasks.db'
]

for db_file in db_files:
    if os.path.exists(db_file):
        print(f"\n{'='*60}")
        print(f"📁 Database: {db_file}")
        print(f"{'='*60}")
        
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
        
        # Get all tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = cursor.fetchall()
        
        if not tables:
            print("  (No tables found - empty database)")
        else:
            print("Tables:")
            for t in tables:
                table_name = t[0]
                cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
                count = cursor.fetchone()[0]
                print(f"  ✓ {table_name:30} ({count:,} rows)")
        
        conn.close()
    else:
        print(f"\n❌ Not found: {db_file}")
