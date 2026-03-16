#!/usr/bin/env python
"""Test user registration with fixed database"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

from database import get_db, init_db
import datetime
from werkzeug.security import generate_password_hash
import secrets

print("🧪 Testing user registration...")
print()

# Initialize database
print("1️⃣  Initializing database...")
init_db()
print("   ✅ Database initialized")
print()

# Test insert
print("2️⃣  Creating test user...")
test_id = 'TEST_' + secrets.token_hex(4)
test_email = f"test_{secrets.token_hex(2)}@example.com"

try:
    with get_db() as (cursor, conn):
        cursor.execute(f'''
            INSERT INTO users (id, name, email, password_hash, phone, dob, joined_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (test_id, 'Test User', test_email, generate_password_hash('Test123!'), '1234567890', '2000-01-01', datetime.datetime.now().isoformat()))
    print("   ✅ User inserted")
except Exception as e:
    print(f"   ❌ Error inserting user: {e}")
    sys.exit(1)

print()

# Verify insert
print("3️⃣  Verifying user was saved...")
try:
    with get_db() as (cursor, conn):
        cursor.execute('SELECT * FROM users WHERE email = ?', (test_email,))
        result = cursor.fetchone()
        if result:
            print("   ✅ User found in database!")
            print(f"      ID: {result['id']}")
            print(f"      Name: {result['name']}")
            print(f"      Email: {result['email']}")
        else:
            print(f"   ❌ User NOT found after insert")
            sys.exit(1)
except Exception as e:
    print(f"   ❌ Error verifying user: {e}")
    sys.exit(1)

print()
print("✅ SUCCESS! User registration is now working correctly!")
