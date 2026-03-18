#!/usr/bin/env python3
import requests
import json
import time
from datetime import datetime, timedelta
import random
import string

BACKEND_URL = "https://taskearn-production-production.up.railway.app/api"

suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
TEST_ACCOUNTS = {
    "poster": {
        "name": f"Test Poster {suffix}",
        "email": f"poster-{suffix}@test.taskearn.com",
        "password": "Test@1234",
        "phone": "9999999991",
        "dob": "1990-01-15",
        "id": None,
        "token": None
    },
    "helper": {
        "name": f"Test Helper {suffix}",
        "email": f"helper-{suffix}@test.taskearn.com",
        "password": "Test@1234",
        "phone": "9999999992",
        "dob": "1992-05-20",
        "id": None,
        "token": None
    }
}

def api_request(method, endpoint, data=None, token=None):
    url = f"{BACKEND_URL}{endpoint}"
    headers = {
        "Content-Type": "application/json",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, timeout=10)
        elif method == "POST":
            response = requests.post(url, headers=headers, json=data, timeout=10)
        else:
            response = requests.put(url, headers=headers, json=data, timeout=10)
        
        print(f"[{method}] {endpoint} -> {response.status_code}")
        
        try:
            result = response.json()
            return result
        except:
            return None
    except Exception as e:
        print(f"Error: {e}")
        return None

print("\n" + "="*70)
print("PAYMENT SYSTEM TEST - FULL FLOW WITH WALLET VERIFICATION")
print("="*70)

print("\nSTEP 1: Register Test Accounts")
print("-" * 70)

for role, account in TEST_ACCOUNTS.items():
    print(f"\nRegistering {role}...")
    result = api_request("POST", "/auth/register", {
        "name": account["name"],
        "email": account["email"],
        "password": account["password"],
        "phone": account["phone"],
        "dob": account["dob"]
    })
    
    if result and result.get("success"):
        account["token"] = result.get("token")
        account["id"] = result.get("user", {}).get("id")
        print(f"[OK] {role} registered - ID: {account['id']}")
    else:
        print(f"[FAIL] {result.get('message') if result else 'No response'}")
        exit(1)

print("\nSTEP 2: Check Initial Wallet Balances")
print("-" * 70)

initial_balances = {}
for role, account in TEST_ACCOUNTS.items():
    result = api_request("GET", "/wallet", token=account["token"])
    
    if result and result.get("success"):
        balance = result.get("balance", 0)
        initial_balances[role] = balance
        print(f"\n[{role.upper()}] Initial balance: {balance}")
    else:
        print(f"[ERROR] Failed to get {role} wallet")

print("\nSTEP 3: Create Task (500 INR)")
print("-" * 70)

task_data = {
    "title": "Payment Test Task",
    "description": "Test for payment flow validation",
    "category": "delivery",
    "price": 500,
    "location": {
        "address": "Test Location, Delhi",
        "lat": 28.7041,
        "lng": 77.1025
    },
    "expiresAt": (datetime.now() + timedelta(hours=2)).isoformat()
}

result = api_request("POST", "/tasks", task_data, TEST_ACCOUNTS["poster"]["token"])
task_id = None

if result and result.get("success"):
    task_id = result.get("taskId") or result.get("task", {}).get("id")
    print(f"[OK] Task created -> ID {task_id}")
else:
    print(f"[FAIL] {result.get('message') if result else 'No response'}")
    exit(1)

if not task_id:
    print("[FAIL] No task ID returned")
    exit(1)

print("\nSTEP 4: Helper Accepts Task")
print("-" * 70)

result = api_request("POST", f"/tasks/{task_id}/accept", {}, TEST_ACCOUNTS["helper"]["token"])

if result and result.get("success"):
    print(f"[OK] Helper accepted task {task_id}")
else:
    print(f"[FAIL] {result.get('message') if result else 'No response'}")
    exit(1)

print("\nSTEP 5: Helper Completes Task")
print("-" * 70)

result = api_request("POST", f"/tasks/{task_id}/complete", {}, TEST_ACCOUNTS["helper"]["token"])

if result and result.get("success"):
    print(f"[OK] Task completed")
    print(f"    Task Amount: {result.get('taskAmount')}")
    print(f"    Commission (20%): {result.get('commission')}")
    print(f"    Helper Earnings: {result.get('netEarnings')}")
else:
    print(f"[FAIL] {result.get('message') if result else 'No response'}")
    exit(1)

print("\nSTEP 6: Poster Pays Helper (via /api/tasks/<id>/pay-helper)")
print("-" * 70)

payment_data = {
    "razorpay_payment_id": f"pay_test_{int(time.time())}",
    "taskId": task_id
}

result = api_request("POST", f"/tasks/{task_id}/pay-helper", payment_data, TEST_ACCOUNTS["poster"]["token"])

if result and result.get("success"):
    print(f"[OK] Payment processed successfully!")
    print(f"    Task Amount: {result.get('taskAmount')}")
    print(f"    Helper Earnings: {result.get('helperEarnings')}")
    print(f"    Commission: {result.get('commission')}")
    print(f"    Payment ID: {result.get('paymentId')}")
else:
    print(f"[FAIL] {result.get('message') if result else 'No response'}")
    exit(1)

print("\nSTEP 7: Verify Final Wallet Balances")
print("-" * 70)

final_balances = {}
for role, account in TEST_ACCOUNTS.items():
    result = api_request("GET", "/wallet", token=account["token"])
    
    if result and result.get("success"):
        balance = result.get("balance", 0)
        final_balances[role] = balance
        initial = initial_balances.get(role, 0)
        change = balance - initial
        
        print(f"\n[{role.upper()}]")
        print(f"  Initial: {initial}")
        print(f"  Final: {balance}")
        print(f"  Change: {change:+.1f}")
    else:
        print(f"[ERROR] Failed to get {role} wallet")

print("\nSTEP 8: Validation")
print("-" * 70)

# Expected: Helper +400, Poster -500
helper_balance = final_balances.get("helper", 0)
poster_balance = final_balances.get("poster", 0)
expected_helper = 400.0
expected_poster = -500.0

print(f"\nHelper balance: {helper_balance} (expected: {expected_helper})")
if helper_balance == expected_helper:
    print("[PASS] Helper balance correct!")
else:
    print(f"[FAIL] Helper balance mismatch!")

print(f"\nPoster balance: {poster_balance} (expected: {expected_poster})")
if poster_balance == expected_poster:
    print("[PASS] Poster balance correct!")
else:
    print(f"[FAIL] Poster balance mismatch!")

print("\n" + "="*70)
if helper_balance == expected_helper and poster_balance == expected_poster:
    print("SUCCESS: PAYMENT SYSTEM WORKING CORRECTLY!")
else:
    print("WARNING: Balances don't match expectations")
print("="*70)
