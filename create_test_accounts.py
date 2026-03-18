#!/usr/bin/env python
"""Create test accounts for commission system testing"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__) + '/backend')

from database import get_db, get_placeholder
from werkzeug.security import generate_password_hash
import datetime
import uuid

PH = get_placeholder()

def create_test_accounts():
    """Create 2 test accounts"""
    
    with get_db() as (cursor, conn):
        # Test Account A (Task Poster)
        user_id_a = str(uuid.uuid4())[:20].upper()
        email_a = 'test.poster@taskearn.com'
        password_a = generate_password_hash('Test@1234')
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        
        cursor.execute(f'''
            INSERT INTO users (id, name, email, password_hash, phone, dob, joined_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (
            user_id_a,
            'Account A (Poster)',
            email_a,
            password_a,
            '9876543210',
            '1990-01-15',
            now
        ))
        
        # Test Account B (Task Helper/Earner)
        user_id_b = str(uuid.uuid4())[:20].upper()
        email_b = 'test.helper@taskearn.com'
        password_b = generate_password_hash('Test@1234')
        
        cursor.execute(f'''
            INSERT INTO users (id, name, email, password_hash, phone, dob, joined_at)
            VALUES ({PH}, {PH}, {PH}, {PH}, {PH}, {PH}, {PH})
        ''', (
            user_id_b,
            'Account B (Helper)',
            email_b,
            password_b,
            '9876543211',
            '1992-05-20',
            now
        ))
        
    print("✅ Test accounts created!")
    print("\n📋 Test Account Details:")
    print("─" * 50)
    print("\n🔐 Account A (Task Poster):")
    print(f"   Email: {email_a}")
    print(f"   Password: Test@1234")
    print(f"   Role: Posts tasks")
    
    print("\n🔐 Account B (Task Helper):")
    print(f"   Email: {email_b}")
    print(f"   Password: Test@1234")
    print(f"   Role: Accepts & earns from tasks")
    
    print("\n─" * 50)
    print("✅ Use these accounts to test the commission system!")

if __name__ == '__main__':
    create_test_accounts()
