#!/usr/bin/env python3
"""
Test the complete payment flow:
1. Test accounts created (from previous script)
2. Helper completes task -> Task status = 'completed'
3. Poster calls pay-helper endpoint -> Task status = 'paid'
4. Verify wallet balances
"""

import requests
import json
import time
from datetime import datetime, timedelta

# Configuration
BACKEND_URL = "https://taskearn-production-production.up.railway.app/api"
TEST_ACCOUNTS = {
    "poster": {
        "email": "test.poster@taskearn.com",
        "password": "Test@1234",
        "id": None,
        "token": None
    },
    "helper": {
        "email": "test.helper@taskearn.com",
        "password": "Test@1234",
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
        
        print(f"📡 {method} {endpoint}")
        print(f"   Status: {response.status_code}")
        
        try:
            result = response.json()
            print(f"   Response: {json.dumps(result, indent=2)[:200]}...")
            return result
        except:
            print(f"   Response (text): {response.text[:200]}...")
            return None
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

# Step 1: Login both accounts
print("\n" + "="*70)
print("STEP 1: Login Test Accounts")
print("="*70)

for role, account in TEST_ACCOUNTS.items():
    print(f"\n🔐 Logging in {role}...")
    result = api_request("POST", "/auth/login", {
        "email": account["email"],
        "password": account["password"]
    })
    
    if result and result.get("success"):
        account["token"] = result.get("token")
        account["id"] = result.get("user", {}).get("id")
        print(f"✅ {role.upper()} logged in successfully")
        print(f"   Token: {account['token'][:20]}...")
        print(f"   User ID: {account['id']}")
    else:
        print(f"❌ Failed to login {role}")
        print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 2: Check initial wallet balances
print("\n" + "="*70)
print("STEP 2: Check Initial Wallet Balances")
print("="*70)

for role, account in TEST_ACCOUNTS.items():
    if not account["token"]:
        print(f"⏭️  Skipping {role} (not logged in)")
        continue
    
    print(f"\n💰 Getting {role} wallet...")
    result = api_request("GET", "/wallet", token=account["token"])
    
    if result and result.get("success"):
        balance = result.get("balance", 0)
        print(f"✅ {role.upper()} wallet balance: ₹{balance}")
    else:
        print(f"❌ Failed to get {role} wallet")

# Step 3: Create a test task (posted by poster, will be accepted by helper)
print("\n" + "="*70)
print("STEP 3: Create Test Task")
print("="*70)

task_data = {
    "title": "Payment Test Task",
    "description": "This is a test task for payment flow validation",
    "category": "delivery",
    "price": 500,
    "location": {
        "address": "Test Location, City",
        "lat": 28.7041,
        "lng": 77.1025
    },
    "expiresAt": (datetime.now() + timedelta(hours=2)).isoformat()
}

print(f"\n📝 Creating task...")
result = api_request("POST", "/tasks", task_data, TEST_ACCOUNTS["poster"]["token"])

task_id = None
if result and result.get("success"):
    task_id = result.get("taskId") or result.get("task", {}).get("id")
    print(f"✅ Task created: {task_id}")
else:
    print(f"❌ Failed to create task")
    print(f"   Error: {result.get('message') if result else 'No response'}")

if not task_id:
    print("❌ Cannot continue without task ID")
    exit(1)

# Step 4: Helper accepts the task
print("\n" + "="*70)
print("STEP 4: Helper Accepts Task")
print("="*70)

print(f"\n✅ Helper accepting task {task_id}...")
result = api_request("POST", f"/tasks/{task_id}/accept", {}, TEST_ACCOUNTS["helper"]["token"])

if result and result.get("success"):
    print(f"✅ Helper accepted task")
else:
    print(f"❌ Failed to accept task")
    print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 5: Helper completes the task
print("\n" + "="*70)
print("STEP 5: Helper Completes Task (Triggers 'completed' status)")
print("="*70)

print(f"\n🏁 Helper completing task {task_id}...")
result = api_request("POST", f"/tasks/{task_id}/complete", {}, TEST_ACCOUNTS["helper"]["token"])

task_status = None
if result and result.get("success"):
    print(f"✅ Task completed")
    print(f"   Task Amount: ₹{result.get('taskAmount')}")
    print(f"   Commission (20%): ₹{result.get('commission')}")
    print(f"   Net Earnings: ₹{result.get('netEarnings')}")
    task_status = "completed"
else:
    print(f"❌ Failed to complete task")
    print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 6: Poster pays the helper
print("\n" + "="*70)
print("STEP 6: Poster Pays Helper (Via /api/tasks/<id>/pay-helper)")
print("="*70)

payment_data = {
    "razorpay_payment_id": f"pay_test_{int(time.time())}",
    "taskId": task_id
}

print(f"\n💳 Poster paying helper for task {task_id}...")
print(f"   Payment ID: {payment_data['razorpay_payment_id']}")
result = api_request("POST", f"/tasks/{task_id}/pay-helper", payment_data, TEST_ACCOUNTS["poster"]["token"])

if result and result.get("success"):
    print(f"✅ Payment processed successfully")
    print(f"   Task Amount: ₹{result.get('taskAmount')}")
    print(f"   Commission: ₹{result.get('commission')}")
    print(f"   Helper Earnings: ₹{result.get('helperEarnings')}")
    print(f"   Payment ID: {result.get('paymentId')}")
    print(f"   Is Suspended: {result.get('isSuspended')}")
    task_status = "paid"
else:
    print(f"❌ Payment failed")
    print(f"   Error: {result.get('message') if result else 'No response'}")

# Step 7: Verify final wallet balances
print("\n" + "="*70)
print("STEP 7: Verify Final Wallet Balances")
print("="*70)

expected_helper_amount = 500 - 100  # price - 20% commission
expected_poster_debit = -500

print(f"\n💰 Final Wallet Balances:")
print(f"   Expected Helper Balance Change: +₹{expected_helper_amount}")
print(f"   Expected Poster Balance Change: ₹{expected_poster_debit}")

for role, account in TEST_ACCOUNTS.items():
    if not account["token"]:
        print(f"⏭️  Skipping {role} (not logged in)")
        continue
    
    print(f"\n📊 Getting final {role} wallet...")
    result = api_request("GET", "/wallet", token=account["token"])
    
    if result and result.get("success"):
        balance = result.get("balance", 0)
        print(f"✅ {role.upper()} final balance: ₹{balance}")
    else:
        print(f"❌ Failed to get {role} wallet")

# Step 8: Get task details to verify status
print("\n" + "="*70)
print("STEP 8: Verify Task Status")
print("="*70)

print(f"\n📋 Getting task details for {task_id}...")
result = api_request("GET", f"/tasks/{task_id}", token=TEST_ACCOUNTS["poster"]["token"])

if result and result.get("success"):
    task = result.get("task", result.get("data", {}))
    print(f"✅ Task retrieved")
    print(f"   Status: {task.get('status')}")
    print(f"   Expected: 'paid'")
    if task.get("status") == "paid":
        print(f"✅ Status correct!")
    else:
        print(f"⚠️  Status mismatch")
else:
    print(f"❌ Failed to get task")

print("\n" + "="*70)
print("TEST COMPLETE")
print("="*70)
