#!/usr/bin/env python3
"""
Test the complete payment flow with NEW 10% commission model:
1. Register new test accounts
2. Create a task (posted by poster, accepted by helper)
3. Helper completes task -> Task status = 'completed'
4. Poster calls pay-helper endpoint -> Task status = 'paid'
5. Verify wallet balances with 10% commission split
"""

import requests
import json
import time
from datetime import datetime, timedelta

# Configuration - Use LOCAL backend for testing
BACKEND_URL = "http://localhost:5000/api"
TASK_AMOUNT = 100  # Test with Rs.100 task

TEST_ACCOUNTS = {
    "poster": {
        "email": f"poster_{int(time.time())}@test.com",
        "password": "Test@1234",
        "name": "Test Poster",
        "id": None,
        "token": None
    },
    "helper": {
        "email": f"helper_{int(time.time())}@test.com",
        "password": "Test@1234",
        "name": "Test Helper",
        "id": None,
        "token": None
    }
}

# Helper function to make API requests
def api_request(method, endpoint, data=None, token=None):
    """Make API request with proper headers"""
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
        
        print(f"[API] {method} {endpoint}")
        print(f"   Status: {response.status_code}")
        
        try:
            result = response.json()
            print(f"   Response: {json.dumps(result, indent=2)[:200]}...")
            return result
        except:
            print(f"   Response (text): {response.text[:200]}...")
            return None
    except Exception as e:
        print(f"[ERROR] Error: {e}")
        return None

# Step 1: Register and login both accounts
print("\n" + "="*70)
print("STEP 1: Register Test Accounts")
print("="*70)

for role, account in TEST_ACCOUNTS.items():
    print(f"\n[*] Registering {role}...")
    # First try to register
    result = api_request("POST", "/auth/register", {
        "email": account["email"],
        "password": account["password"],
        "name": account["name"],
        "phone": "9999999999",
        "dob": "1990-01-01"
    })
    
    if result and result.get("success"):
        account["token"] = result.get("token")
        account["id"] = result.get("user", {}).get("id")
        print(f"[OK] {role.upper()} registered successfully")
        print(f"   Token: {account['token'][:20]}...")
        print(f"   User ID: {account['id']}")
    else:
        print(f"[!] Failed to register {role}")
        print(f"   Error: {result.get('message') if result else 'No response'}")
        print(f"   Trying to login instead...")
        
        # Try login if registration fails
        result = api_request("POST", "/auth/login", {
            "email": account["email"],
            "password": account["password"]
        })
        
        if result and result.get("success"):
            account["token"] = result.get("token")
            account["id"] = result.get("user", {}).get("id")
            print(f"[OK] {role.upper()} logged in successfully")
        else:
            print(f"[!] Failed to login {role}")
            print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 2: Check initial wallet balances
print("\n" + "="*70)
print("STEP 2: Check Initial Wallet Balances")
print("="*70)

for role, account in TEST_ACCOUNTS.items():
    if not account["token"]:
        print(f"[SKIP]  Skipping {role} (not logged in)")
        continue
    
    print(f"\n Getting {role} wallet...")
    result = api_request("GET", "/wallet", token=account["token"])
    
    if result and result.get("success"):
        balance = result.get("balance", 0)
        print(f"[OK] {role.upper()} wallet balance: Rs.{balance}")
    else:
        print(f"[FAIL] Failed to get {role} wallet")

# Step 3: Create a test task (posted by poster, will be accepted by helper)
print("\n" + "="*70)
print("STEP 3: Create Test Task")
print("="*70)

task_data = {
    "title": "Payment Test Task - 10% Commission Model",
    "description": "Test task for new payment flow with 10% commission split between poster and helper",
    "category": "delivery",
    "price": TASK_AMOUNT,
    "location": {
        "address": "Test Location, City",
        "lat": 28.7041,
        "lng": 77.1025
    }
}

print(f"\n Creating task...")
result = api_request("POST", "/tasks", task_data, TEST_ACCOUNTS["poster"]["token"])

task_id = None
if result and result.get("success"):
    task_id = result.get("taskId") or result.get("task", {}).get("id")
    print(f"[OK] Task created: {task_id}")
else:
    print(f"[FAIL] Failed to create task")
    print(f"   Error: {result.get('message') if result else 'No response'}")

if not task_id:
    print("[FAIL] Cannot continue without task ID")
    exit(1)

# Step 4: Helper accepts the task
print("\n" + "="*70)
print("STEP 4: Helper Accepts Task")
print("="*70)

print(f"\n[OK] Helper accepting task {task_id}...")
result = api_request("POST", f"/tasks/{task_id}/accept", {}, TEST_ACCOUNTS["helper"]["token"])

if result and result.get("success"):
    print(f"[OK] Helper accepted task")
else:
    print(f"[FAIL] Failed to accept task")
    print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 5: Helper completes the task
print("\n" + "="*70)
print("STEP 5: Helper Completes Task (Triggers 'completed' status)")
print("="*70)

print(f"\n Helper completing task {task_id}...")
result = api_request("POST", f"/tasks/{task_id}/complete", {}, TEST_ACCOUNTS["helper"]["token"])

task_status = None
if result and result.get("success"):
    print(f"[OK] Task completed")
    print(f"   Task Amount: Rs.{result.get('taskAmount')}")
    print(f"   Commission (10% each): Rs.{result.get('commission')}")
    print(f"   Helper receives: Rs.{result.get('netEarnings')}")
    task_status = "completed"
else:
    print(f"[FAIL] Failed to complete task")
    print(f"   Error: {result.get('message') if result else 'No response'}")

# STEP 5.5: Add funds to poster wallet (simulate wallet top-up) 
print("\n" + "="*70)
print("STEP 5.5: Add Funds to Poster Wallet")
print("="*70)

print("\n[*] Adding Rs.200 to poster wallet for testing...")
# Note: In production, this would be done via wallet top-up endpoint
# For testing, we add funds via direct endpoint call if available
result = api_request("POST", "/wallet/add-funds", {
    "amount": 200
}, TEST_ACCOUNTS["poster"]["token"])

if result and result.get("success"):
    print("[OK] Funds added successfully")
    print(f"   New balance: Rs.{result.get('balance', 'unknown')}")
else:
    print("[NOTE] Wallet top-up endpoint not available - using direct SQL")
    # As fallback, try to update wallet directly (development only)
    print("[SKIP] Direct DB update skipped - would require admin access")

# Step 6: Poster pays the helper
print("\n" + "="*70)
print("STEP 6: Poster Pays Helper (Via /api/tasks/<id>/pay-helper)")
print("="*70)

# Calculate expected amounts for 10% commission model
commission_rate = 0.10
poster_commission = TASK_AMOUNT * commission_rate
helper_commission = TASK_AMOUNT *commission_rate
helper_receives = TASK_AMOUNT - helper_commission
total_cost = TASK_AMOUNT + poster_commission

print(f"\n Expected Payment Breakdown (10% Commission Model):")
print(f"   Task Amount: Rs.{TASK_AMOUNT}")
print(f"   Poster Commission (10%): Rs.{poster_commission:.2f}")
print(f"   Helper Commission (10%): Rs.{helper_commission:.2f}")
print(f"   Helper receives: Rs.{helper_receives:.2f}")
print(f"   Poster pays total: Rs.{total_cost:.2f}")

print(f"\n Poster paying helper for task {task_id}...")
result = api_request("POST", f"/tasks/{task_id}/pay-helper", {}, TEST_ACCOUNTS["poster"]["token"])

if result and result.get("success"):
    print(f"[OK] Payment processed successfully")
    print(f"   Task Amount: Rs.{result.get('amount')}")
    print(f"   Helper receives: Rs.{result.get('helperReceives'):.2f}")
    print(f"   Poster Commission: Rs.{result.get('posterCommission'):.2f}")
    print(f"   Helper Commission: Rs.{result.get('helperCommission'):.2f}")
    print(f"   Poster New Balance: Rs.{result.get('posterNewBalance'):.2f}")
    print(f"   Helper New Balance: Rs.{result.get('helperNewBalance'):.2f}")
    task_status = "paid"
else:
    print(f"[FAIL] Payment failed")
    print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 7: Verify final wallet balances
print("\n" + "="*70)
print("STEP 7: Verify Final Wallet Balances")
print("="*70)

expected_helper_amount = TASK_AMOUNT - (TASK_AMOUNT * 0.10)  # Task - 10% commission
expected_poster_debit = TASK_AMOUNT + (TASK_AMOUNT * 0.10)  # Task + 10% commission

print(f"\n Final Wallet Balances:")
print(f"   Expected Helper Balance Change: +Rs.{expected_helper_amount:.2f}")
print(f"   Expected Poster Balance Change: -Rs.{expected_poster_debit:.2f}")

for role, account in TEST_ACCOUNTS.items():
    if not account["token"]:
        print(f"[SKIP]  Skipping {role} (not logged in)")
        continue
    
    print(f"\n Getting final {role} wallet...")
    result = api_request("GET", "/wallet", token=account["token"])
    
    if result and result.get("success"):
        balance = result.get("balance", 0)
        print(f"[OK] {role.upper()} final balance: Rs.{balance}")
    else:
        print(f"[FAIL] Failed to get {role} wallet")

# Step 8: Get task details to verify status
print("\n" + "="*70)
print("STEP 8: Verify Task Status")
print("="*70)

print(f"\n Getting task details for {task_id}...")
result = api_request("GET", f"/tasks/{task_id}", token=TEST_ACCOUNTS["poster"]["token"])

if result and result.get("success"):
    task = result.get("task", result.get("data", {}))
    print(f"[OK] Task retrieved")
    print(f"   Status: {task.get('status')}")
    print(f"   Expected: 'paid'")
    if task.get("status") == "paid":
        print(f"[OK] Status correct!")
    else:
        print(f"  Status mismatch")
else:
    print(f"[FAIL] Failed to get task")

print("\n" + "="*70)
print("TEST COMPLETE")
print("="*70)
