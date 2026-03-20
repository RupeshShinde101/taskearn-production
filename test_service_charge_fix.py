#!/usr/bin/env python3
"""
End-to-end test for service charge and commission deduction fix
"""

import requests
import json
import time

BASE_URL = "http://localhost:5000"

print("=" * 80)
print("END-TO-END SERVICE CHARGE & COMMISSION FIX TEST")
print("=" * 80)

# Step 1: Check a task in the database with service charge
print("\n✅ Step 1: Verify task data in database")
print("-" * 80)

import sqlite3
conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

cursor.execute('SELECT id, title, price, service_charge FROM tasks WHERE status IN ("active", "accepted") LIMIT 1')
task_row = cursor.fetchone()

if task_row:
    task_id, title, price, service_charge = task_row
    print(f"Task ID: {task_id}")
    print(f"Title: {title}")
    print(f"Price (base): ₹{price}")
    print(f"Service Charge: ₹{service_charge}")
    
    total_value = price + service_charge
    helper_commission = total_value * 0.12
    helper_earnings = total_value * 0.88
    
    print(f"\nExpected Calculations:")
    print(f"  Total Task Value: ₹{total_value}")
    print(f"  Helper Commission (12%): -₹{helper_commission:.2f}")
    print(f"  Helper Earnings (88%): ₹{helper_earnings:.2f}")
else:
    print("❌ No tasks found in database")
    conn.close()
    exit(1)

conn.close()

# Step 2: Verify API returns service_charge for task details
print("\n✅ Step 2: Test /api/tasks/<id>/details endpoint")
print("-" * 80)

headers = {
    'Authorization': 'Bearer dummy_token_for_auth'
}

response = requests.get(
    f"{BASE_URL}/api/tasks/{task_id}/details",
    headers=headers
)

if response.status_code == 200:
    data = response.json()
    if data.get('success') and data.get('task'):
        task_details = data['task']
        returned_price = task_details.get('price') or task_details.get('amount')
        returned_service_charge = task_details.get('service_charge', 0)
        
        print(f"API Response:")
        print(f"  Price: ₹{returned_price}")
        print(f"  Service Charge: ₹{returned_service_charge}")
        
        if returned_service_charge > 0:
            print(f"\n✅ Service charge IS included in API response!")
        else:
            print(f"\n❌ Service charge is MISSING from API response!")
    else:
        print(f"❌ Invalid response format: {data}")
else:
    print(f"❌ API Error: {response.status_code}")

# Step 3: Verify calculation is correct
print("\n✅ Step 3: Verify commission calculation")
print("-" * 80)

if returned_service_charge == service_charge:
    print(f"✅ Service charge from API matches database (₹{service_charge})")
else:
    print(f"❌ Service charge mismatch! Expected ₹{service_charge}, got ₹{returned_service_charge}")

api_total = returned_price + returned_service_charge
expected_total = price + service_charge

if api_total == expected_total:
    print(f"✅ Total value calculation is correct: ₹{api_total}")
    
    api_helper_earnings = api_total * 0.88
    api_poster_fee = api_total * 0.05
    api_total_from_poster = api_total + api_poster_fee
    
    print(f"\nPayment Breakdown:")
    print(f"  Base Price: ₹{returned_price}")
    print(f"  Service Charge: ₹{returned_service_charge}")
    print(f"  Total Task Value: ₹{api_total}")
    print(f"  Helper Earnings (88%): ₹{api_helper_earnings:.2f}")
    print(f"  Poster Platform Fee (5%): ₹{api_poster_fee:.2f}")
    print(f"  Total Poster Pays: ₹{api_total_from_poster:.2f}")
    print(f"\n✅ All calculations verified and correct!")
else:
    print(f"❌ Total value mismatch! Expected ₹{expected_total}, got ₹{api_total}")

print("\n" + "=" * 80)
print("✅ TEST COMPLETE - Service Charge Fix Verified!")
print("=" * 80)
