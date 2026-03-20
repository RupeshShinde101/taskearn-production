#!/usr/bin/env python3
"""
Test the pay-helper endpoint - SIMPLIFIED VERSION
Only uses API responses, no database queries while backend is running
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
print("TESTING PAY-HELPER ENDPOINT - SIMPLIFIED TEST")
print("=" * 80)

# ONLY connect to database once at the start, before backend is fully active
print("\n1. Getting task info from database...")
conn = sqlite3.connect('backend/taskearn.db', timeout=10.0)
conn.execute("PRAGMA journal_mode=WAL")
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

print(f"   ✅ Task found: {title}")
print(f"   ID: {task_id}, Price: ₹{price}, Service: ₹{service_charge}, Total: ₹{total_value}")

# Get initial balances
cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (posted_by,))
poster_before = cursor.fetchone()
poster_before_balance = poster_before[0] if poster_before else 0

cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (accepted_by,))
helper_before = cursor.fetchone()
helper_before_balance = helper_before[0] if helper_before else 0

print(f"   Poster balance before: ₹{poster_before_balance}")
print(f"   Helper balance before: ₹{helper_before_balance}")

conn.close()  # Close database connection before making API calls
print(f"   ✅ Database closed")

# Generate JWT token
print(f"\n2. Generating JWT token for poster...")
token = generate_jwt_token(posted_by, poster_email)
print(f"   ✅ Token generated: {token[:30]}...")

# Call pay-helper endpoint
print(f"\n3. Calling POST /api/tasks/{task_id}/pay-helper...")
try:
    payload = {
        "taskAmount": price,
        "serviceCharge": service_charge,
        "totalTaskValue": total_value
    }
    
    headers = HEADERS.copy()
    headers["Authorization"] = f"Bearer {token}"
    
    print(f"   Base price: ₹{price}")
    print(f"   Service charge: ₹{service_charge}")
    print(f"   Total: ₹{total_value}")
    
    response = requests.post(
        f"{BASE_URL}/api/tasks/{task_id}/pay-helper",
        json=payload,
        headers=headers,
        timeout=15
    )
    
    print(f"\n   Status Code: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"   ✅ Payment processed successfully!\n")
        
        print(f"   📊 PAYMENT BREAKDOWN (from backend response):")
        print(f"      Base Amount: ₹{data.get('amount')}")
        print(f"      Service Charge: ₹{data.get('serviceCharge')}")
        print(f"      Total Task Value: ₹{data.get('totalTaskValue')}")
        print(f"      Helper Commission (12%): ₹{data.get('helperCommission')}")
        print(f"      Helper Earnings (88%): ₹{data.get('helperEarnings')}")
        print(f"      Poster Fee (5%): ₹{data.get('posterFee')}")
        print(f"      Platform Income: ₹{data.get('platformIncome')}")
        
        print(f"\n   💰 FINAL WALLETS (from backend):")
        print(f"      Helper wallet: ₹{helper_before_balance} → ₹{data.get('helperNewBalance')}")
        print(f"         Change: +₹{data.get('helperNewBalance') - helper_before_balance}")
        print(f"         Expected: +₹{total_value * 0.88}")
        
        print(f"      Poster wallet: ₹{poster_before_balance} → ₹{data.get('posterNewBalance')}")
        print(f"         Change: -₹{poster_before_balance - data.get('posterNewBalance')}")
        print(f"         Expected: -₹{(total_value * 1.05):.2f}")
        
        print(f"      Company wallet: ₹{data.get('companyNewBalance')}")
        print(f"         Income: ₹{data.get('platformIncome')}")
        
        # Verify the calculations
        print(f"\n   ✅ VERIFICATION:")
        helper_earnings = data.get('helperEarnings', 0)
        expected_helper_earnings = total_value * 0.88
        if abs(helper_earnings - expected_helper_earnings) < 0.01:
            print(f"      ✅ Helper earnings correct (₹{helper_earnings:.2f})")
        else:
            print(f"      ❌ Helper earnings incorrect: ₹{helper_earnings:.2f}, expected ₹{expected_helper_earnings:.2f}")
        
        commission = data.get('helperCommission', 0)
        expected_commission = total_value * 0.12
        if abs(commission - expected_commission) < 0.01:
            print(f"      ✅ Commission correct (₹{commission:.2f})")
        else:
            print(f"      ❌ Commission incorrect: ₹{commission:.2f}, expected ₹{expected_commission:.2f}")
        
        print(f"\n   Message: {data.get('message')}")
    else:
        print(f"   ❌ Error: {response.text}")
        
except Exception as e:
    print(f"   ❌ Exception: {str(e)}")
    import traceback
    traceback.print_exc()

print("\n" + "=" * 80)
print("Test complete. Check backend log for detailed transaction info.")
print("=" * 80)
