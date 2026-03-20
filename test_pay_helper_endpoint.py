#!/usr/bin/env python3
"""
Test the pay-helper endpoint directly
"""

import requests
import json
from datetime import datetime, timezone
import sqlite3

BASE_URL = "http://localhost:5000"
HEADERS = {"Content-Type": "application/json"}

print("=" * 80)
print("TESTING PAY-HELPER ENDPOINT")
print("=" * 80)

# Get completed task
conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

cursor.execute('''
    SELECT id, title, price, service_charge, posted_by, accepted_by, status
    FROM tasks 
    WHERE status = 'completed' 
    LIMIT 1
''')

result = cursor.fetchone()
if not result:
    print("❌ No completed task found!")
    conn.close()
    exit(1)

task_id, title, price, service_charge, posted_by, accepted_by, status = result
service_charge = service_charge or 0
total_value = price + service_charge

print(f"\n1. Task Details:")
print(f"   ID: {task_id}")
print(f"   Title: {title}")
print(f"   Base Price: ₹{price}")
print(f"   Service Charge: ₹{service_charge}")
print(f"   Total Value: ₹{total_value}")
print(f"   Status: {status}")

# Show balances BEFORE
print(f"\n2. Balances BEFORE Payment:")
cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (posted_by,))
poster_before = cursor.fetchone()
poster_before_balance = poster_before[0] if poster_before else 0

cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (accepted_by,))
helper_before = cursor.fetchone()
helper_before_balance = helper_before[0] if helper_before else 0

print(f"   Poster wallet: ₹{poster_before_balance}")
print(f"   Helper wallet: ₹{helper_before_balance}")

# Call pay-helper endpoint
print(f"\n3. Calling POST /api/tasks/{task_id}/pay-helper...")
try:
    payload = {
        "taskAmount": price,
        "serviceCharge": service_charge,
        "totalTaskValue": total_value
    }
    print(f"   Payload: {json.dumps(payload, indent=6)}")
    
    response = requests.post(
        f"{BASE_URL}/api/tasks/{task_id}/pay-helper",
        json=payload,
        headers=HEADERS,
        timeout=10
    )
    
    print(f"\n   Status Code: {response.status_code}")
    print(f"   Response:")
    
    if response.status_code == 200:
        data = response.json()
        print(f"   ✅ Payment processed successfully!")
        print(f"\n   Backend Response Details:")
        print(f"      amount: ₹{data.get('amount')}")
        print(f"      serviceCharge: ₹{data.get('serviceCharge', 'MISSING')}")
        print(f"      totalTaskValue: ₹{data.get('totalTaskValue', 'MISSING')}")
        print(f"      helperEarnings: ₹{data.get('helperEarnings', 'MISSING')}")
        print(f"      helperCommission: ₹{data.get('helperCommission', 'MISSING')}")
        print(f"      posterFee: ₹{data.get('posterFee', 'MISSING')}")
        print(f"      message: {data.get('message')}")
    else:
        print(f"   ❌ Error: {response.text}")
        
except Exception as e:
    print(f"   ❌ Exception: {str(e)}")

# Show balances AFTER
print(f"\n4. Balances AFTER Payment:")
cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (posted_by,))
poster_after = cursor.fetchone()
poster_after_balance = poster_after[0] if poster_after else 0

cursor.execute('SELECT balance FROM wallets WHERE user_id = ?', (accepted_by,))
helper_after = cursor.fetchone()
helper_after_balance = helper_after[0] if helper_after else 0

print(f"   Poster wallet: ₹{poster_after_balance}")
print(f"      Change: ₹{poster_after_balance - poster_before_balance}")
print(f"      Expected: -₹{total_value * 1.05:.2f}")

print(f"   Helper wallet: ₹{helper_after_balance}")
print(f"      Change: ₹{helper_after_balance - helper_before_balance}")
print(f"      Expected: +₹{total_value * 0.88:.2f}")

# Verify calculations
print(f"\n5. Verification:")
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
print(f"   Task status changed to: {new_status}")
if new_status == 'paid':
    print(f"   ✅ Task marked as 'paid'")
else:
    print(f"   ⚠️  Task status is '{new_status}', should be 'paid'")

conn.close()
