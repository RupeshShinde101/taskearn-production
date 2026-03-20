"""
Debug script to check wallet deduction after task completion
"""
import requests
import json

API_BASE = "http://localhost:8000"  # Change to your API URL

def test_wallet_deduction():
    print("=" * 70)
    print("DEBUGGING WALLET DEDUCTION ISSUE")
    print("=" * 70)
    
    # First, get auth tokens for testing
    print("\n1️⃣ Testing Wallet Status Before Task Completion...")
    
    # You need to provide actual user IDs and tokens
    helper_id = input("Enter Helper User ID: ")
    poster_id = input("Enter Poster User ID: ")
    task_id = input("Enter Task ID: ")
    helper_token = input("Enter Helper Auth Token: ")
    poster_token = input("Enter Poster Auth Token: ")
    
    # Check helper wallet
    print(f"\n📊 Checking Helper Wallet (ID: {helper_id})...")
    try:
        response = requests.get(
            f"{API_BASE}/wallet",
            headers={'Authorization': f'Bearer {helper_token}'}
        )
        helper_wallet = response.json()
        print(f"✅ Helper Wallet: {json.dumps(helper_wallet, indent=2)}")
    except Exception as e:
        print(f"❌ Error getting helper wallet: {e}")
    
    # Check poster wallet
    print(f"\n📊 Checking Poster Wallet (ID: {poster_id})...")
    try:
        response = requests.get(
            f"{API_BASE}/wallet",
            headers={'Authorization': f'Bearer {poster_token}'}
        )
        poster_wallet = response.json()
        print(f"✅ Poster Wallet: {json.dumps(poster_wallet, indent=2)}")
        poster_balance = poster_wallet.get('balance', 0)
    except Exception as e:
        print(f"❌ Error getting poster wallet: {e}")
        poster_balance = 0
    
    # Get task details
    print(f"\n📋 Getting Task Details (ID: {task_id})...")
    try:
        response = requests.get(
            f"{API_BASE}/tasks/{task_id}",
            headers={'Authorization': f'Bearer {helper_token}'}
        )
        task = response.json().get('data', {})
        task_price = task.get('price', 0)
        service_charge = task.get('service_charge', 0)
        total_task_value = task_price + service_charge
        
        poster_fee = total_task_value * 0.05
        total_poster_cost = total_task_value + poster_fee
        
        print(f"✅ Task Details:")
        print(f"   - Price: ₹{task_price}")
        print(f"   - Service Charge: ₹{service_charge}")
        print(f"   - Total Value: ₹{total_task_value}")
        print(f"   - Poster Fee (5%): ₹{poster_fee:.2f}")
        print(f"   - Total Poster Cost: ₹{total_poster_cost:.2f}")
        
        # Check balance
        print(f"\n💰 Balance Check:")
        print(f"   - Poster Current Balance: ₹{poster_balance}")
        print(f"   - Amount Needed: ₹{total_poster_cost:.2f}")
        
        if poster_balance < total_poster_cost:
            print(f"   ⚠️ INSUFFICIENT BALANCE!")
            print(f"   - Shortfall: ₹{(total_poster_cost - poster_balance):.2f}")
            print(f"\n❌ This is why the wallet deduction is failing!")
            print(f"   The poster needs ₹{total_poster_cost:.2f} to pay for this task")
            print(f"   but only has ₹{poster_balance}")
            return
        
        print(f"   ✅ Sufficient balance to complete task")
        
    except Exception as e:
        print(f"❌ Error getting task details: {e}")
        return
    
    # Try to complete the task
    print(f"\n2️⃣ Attempting to Mark Task as Complete...")
    try:
        response = requests.post(
            f"{API_BASE}/tasks/{task_id}/complete",
            headers={'Authorization': f'Bearer {helper_token}'}
        )
        result = response.json()
        
        if response.status_code == 200:
            print(f"✅ Task completion successful!")
            print(f"   Response: {json.dumps(result, indent=2)}")
        else:
            print(f"❌ Error completing task (Status: {response.status_code})")
            print(f"   Error: {json.dumps(result, indent=2)}")
            
    except Exception as e:
        print(f"❌ Error calling API: {e}")
        return
    
    # Check wallets after completion
    print(f"\n3️⃣ Checking Wallet Status After Task Completion...")
    try:
        response = requests.get(
            f"{API_BASE}/wallet",
            headers={'Authorization': f'Bearer {helper_token}'}
        )
        helper_wallet_after = response.json()
        print(f"✅ Helper Wallet After: {json.dumps(helper_wallet_after, indent=2)}")
        
        response = requests.get(
            f"{API_BASE}/wallet",
            headers={'Authorization': f'Bearer {poster_token}'}
        )
        poster_wallet_after = response.json()
        print(f"✅ Poster Wallet After: {json.dumps(poster_wallet_after, indent=2)}")
        
        print(f"\n📊 Summary:")
        print(f"   Helper Balance Change: {helper_wallet_after.get('balance', 0)}")
        print(f"   Poster Balance Change: {poster_wallet_after.get('balance', 0)}")
        
    except Exception as e:
        print(f"❌ Error getting wallet after: {e}")

if __name__ == "__main__":
    test_wallet_deduction()
