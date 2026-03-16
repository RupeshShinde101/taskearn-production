#!/usr/bin/env python
"""Direct test of registration without loading full app"""

import sys
import os

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

# Import just the database functions
from database import get_db, init_db
from werkzeug.security import generate_password_hash
import datetime
import secrets

print("🧪 Direct Registration Test (without API server)")
print()

# Initialize database
print("1️⃣  Initializing database...")
init_db()
print("   ✅ Done")
print()

# Create multiple test users
for i in range(3):
    test_id = f'USER_{secrets.token_hex(4)}'
    test_email = f"testuser{i}_{secrets.token_hex(3)}@example.com"
    
    print(f"2️⃣  Creating test user #{i+1}...")
    print(f"    Email: {test_email}")
    
    try:
        with get_db() as (cursor, conn):
            cursor.execute(f'''
                INSERT INTO users (id, name, email, password_hash, phone, dob, joined_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                test_id,
                f'Test User {i+1}',
                test_email,
                generate_password_hash(f'Test{i+1}123!@'),
                f'9876543{i:03d}',
                '2000-01-01',
                datetime.datetime.now().isoformat()
            ))
        print("    ✅ Inserted")
        
        # Verify
        with get_db() as (cursor, conn):
            cursor.execute('SELECT * FROM users WHERE email = ?', (test_email,))
            result = cursor.fetchone()
            if result:
                print(f"    ✅ Verified in database!")
                print(f"       ID: {result['id']}")
                print(f"       Name: {result['name']}")
            else:
                print("    ❌ Not found after insert!")
                sys.exit(1)
    except Exception as e:
        print(f"    ❌ Error: {e}")
        sys.exit(1)
    print()

print("✅ ALL TESTS PASSED!")
print()
print("Summary:")
print("✓ Database initialized")
print("✓ Multiple users created")
print("✓ Data persisted correctly")
print("✓ Transaction commits working")
