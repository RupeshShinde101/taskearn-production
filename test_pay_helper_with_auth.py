#!/usr/bin/env python3
"""
Test the pay-helper endpoint with JWT authentication
"""

import requests
import json
from datetime import datetime, timezone, timedelta
import sqlite3
import sys
import os
import jwt

# Add backend to path to import config
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

try:
    import config as config_module
    cfg = config_module.Config
except ImportError:
    print("❌ Could not import config from backend")
    exit(1)

BASE_URL = "http://localhost:5000"
HEADERS = {"Content-Type": "application/json"}

# Helper function to generate JWT token
def generate_jwt_token(user_id, email):
    """Generate JWT authentication token"""
    payload = {
        'user_id': user_id,
        'email': email,
        'exp': datetime.now(timezone.utc) + timedelta(hours=cfg.JWT_EXPIRATION_HOURS),
        'iat': datetime.now(timezone.utc)
    }
    return jwt.encode(payload, cfg.SECRET_KEY, algorithm='HS256')

print("=" * 80)
print("TESTING PAY-HELPER ENDPOINT WITH JWT AUTHENTICATION")
print("=" * 80)

# Get completed task and user info
conn = sqlite3.connect('backend/taskearn.db', timeout=5.0)  # Add timeout for lock
conn.execute("PRAGMA journal_mode=WAL")  # Enable WAL mode
cursor = conn.cursor()

cursor.execute('''
    SELECT t.id, t.title, t.price, t.service_charge, t.posted_by, t.accepted_by, t.status,
           u.email
    FROM tasks t
    JOIN users u ON t.posted_by = u.id
    WHERE t.status = 'completed' 
    LIMIT 1
''')

result = cursor.fetchone()
if not result:
    print("❌ No completed task found!")
    conn.close()
    exit(1)

task_id, title, price, service_charge, posted_by, accepted_by, status, poster_email = result
service_charge = service_charge or 0
total_value = price + service_charge

print(f"\n1. Task Details:")
print(f"   ID: {task_id}")
print(f"   Title: {title}")
print(f"   Base Price: ₹{price}")
print(f"   Service Charge: ₹{service_charge}")
print(f"   Total Value: ₹{total_value}")
print(f"   Poster ID: {posted_by}")
print(f"   Poster Email: {poster_email}")

# Generate JWT token for poster
print(f"\n2. Generating JWT token for poster...")
token = generate_jwt_token(posted_by, poster_email)
print(f"   Token: {token[:50]}...")

# Show balances BEFORE
print(f"\n3. Balances BEFORE Payment:")
cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (posted_by,))
poster_before = cursor.fetchone()
poster_before_balance = poster_before[0] if poster_before else 0

cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (accepted_by,))
helper_before = cursor.fetchone()
helper_before_balance = helper_before[0] if helper_before else 0

print(f"   Poster wallet: ₹{poster_before_balance}")
print(f"   Helper wallet: ₹{helper_before_balance}")

# Call pay-helper endpoint with JWT
print(f"\n4. Calling POST /api/tasks/{task_id}/pay-helper with JWT...")
try:
    payload = {
        "taskAmount": price,
        "serviceCharge": service_charge,
        "totalTaskValue": total_value
    }
    
    headers = HEADERS.copy()
    headers["Authorization"] = f"Bearer {token}"
    
    print(f"   Payload: {json.dumps(payload, indent=6)}")
    print(f"   Auth header: Bearer {token[:30]}...")
    
    response = requests.post(
        f"{BASE_URL}/api/tasks/{task_id}/pay-helper",
        json=payload,
        headers=headers,
        timeout=10
    )
    
    print(f"\n   Status Code: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"   ✅ Payment processed successfully!")
        print(f"\n   Backend Response Details:")
        print(f"      amount: ₹{data.get('amount')}")
        print(f"      serviceCharge: ₹{data.get('serviceCharge')}")
        print(f"      totalTaskValue: ₹{data.get('totalTaskValue')}")
        print(f"      helperEarnings: ₹{data.get('helperEarnings')}")
        print(f"      helperCommission: ₹{data.get('helperCommission')}")
        print(f"      posterFee: ₹{data.get('posterFee')}")
        print(f"      message: {data.get('message')}")
    else:
        print(f"   ❌ Error: {response.text}")
        
except Exception as e:
    print(f"   ❌ Exception: {str(e)}")
    import traceback
    traceback.print_exc()

# Show balances AFTER
print(f"\n5. Balances AFTER Payment (Waiting for database lock to clear)...")
import time
max_retries = 5
for attempt in range(max_retries):
    try:
        cursor.close()
        conn.close()
        time.sleep(1)  # Wait before reopening
        
        conn = sqlite3.connect('backend/taskearn.db', timeout=10.0)
        conn.execute("PRAGMA journal_mode=WAL")
        cursor = conn.cursor()
        
        cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (posted_by,))
        poster_after = cursor.fetchone()
        poster_after_balance = poster_after[0] if poster_after else 0

        cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (accepted_by,))
        helper_after = cursor.fetchone()
        helper_after_balance = helper_after[0] if helper_after else 0
        
        break
    except Exception as e:
        if attempt < max_retries - 1:
            print(f"   Retry {attempt + 1}/{max_retries}: {str(e)}")
            time.sleep(2)
        else:
            raise

print(f"   Poster wallet: ₹{poster_after_balance}")
print(f"      Change: ₹{poster_after_balance - poster_before_balance}")
print(f"      Expected: -₹{total_value * 1.05:.2f}")

print(f"   Helper wallet: ₹{helper_after_balance}")
print(f"      Change: ₹{helper_after_balance - helper_before_balance}")
print(f"      Expected: +₹{total_value * 0.88:.2f}")

# Verify calculations
print(f"\n6. Verification:")
commission = total_value * 0.12
helper_should_earn = total_value * 0.88
poster_should_pay = total_value * 1.05

poster_diff = abs((poster_after_balance - poster_before_balance) - (-poster_should_pay))
helper_diff = abs((helper_after_balance - helper_before_balance) - helper_should_earn)

if poster_diff < 0.01:
    print(f"   ✅ Poster wallet correctly deducted")
else:
    print(f"   ❌ Poster wallet incorrect (diff: ₹{poster_diff})")

if helper_diff < 0.01:
    print(f"   ✅ Helper wallet correctly credited")
else:
    print(f"   ❌ Helper wallet incorrect (diff: ₹{helper_diff})")

# Check task status
cursor.execute('SELECT status FROM tasks WHERE id = ?', (task_id,))
new_status = cursor.fetchone()[0]
print(f"   Task status: {new_status}")
if new_status == 'paid':
    print(f"   ✅ Task marked as 'paid'")
else:
    print(f"   ⚠️  Task status is '{new_status}', expected 'paid'")

conn.close()
print("\n" + "=" * 80)
