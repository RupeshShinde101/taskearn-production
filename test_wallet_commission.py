#!/usr/bin/env python3
"""
Test wallet commission deduction by checking database state
"""

import sqlite3

conn = sqlite3.connect('backend/taskearn.db')
cursor = conn.cursor()

print("=" * 80)
print("WALLET COMMISSION DEDUCTION TEST")
print("=" * 80)

# Check if completed tasks exist
print("\n1. Checking completed tasks:")
cursor.execute('SELECT id, title, price, service_charge, status, posted_by, accepted_by FROM tasks WHERE status = "completed"')
completed_tasks = cursor.fetchall()

if not completed_tasks:
    print("   No completed tasks found. Need to test payment flow.")
else:
    print(f"   Found {len(completed_tasks)} completed task(s)")
    for task_id, title, price, service_charge, status, poster_id, helper_id in completed_tasks:
        total = price + (service_charge or 0)
        print(f"\n   Task {task_id}: {title}")
        print(f"     Price: ₹{price} + Service: ₹{service_charge or 0} = ₹{total}")
        print(f"     Posted by: {poster_id}")
        print(f"     Accepted by: {helper_id}")

# Check wallet balances
print("\n\n2. Checking wallet balances:")
cursor.execute('''
    SELECT id, user_id, balance, total_earned, total_spent, created_at 
    FROM wallets 
    ORDER BY user_id
''')
wallets = cursor.fetchall()

if wallets:
    print(f"   Found {len(wallets)} wallets:")
    for wallet_id, user_id, balance, total_earned, total_spent, created_at in wallets:
        print(f"\n   Wallet ID: {wallet_id}")
        print(f"     User: {user_id}")
        print(f"     Balance: ₹{balance}")
        print(f"     Total Earned: ₹{total_earned}")
        print(f"     Total Spent: ₹{total_spent}")
else:
    print("   No wallets found!")

# Check wallet transactions
print("\n\n3. Checking wallet transactions (last 10):")
cursor.execute('''
    SELECT id, user_id, type, amount, balance_after, description 
    FROM wallet_transactions 
    ORDER BY created_at DESC 
    LIMIT 10
''')
transactions = cursor.fetchall()

if transactions:
    print(f"   Found {len(transactions)} recent transactions:")
    for txn_id, user_id, txn_type, amount, balance_after, description in transactions:
        print(f"\n   Transaction {txn_id}:")
        print(f"     User: {user_id}")
        print(f"     Type: {txn_type}")
        print(f"     Amount: ₹{amount}")
        print(f"     Balance After: ₹{balance_after}")
        print(f"     Description: {description}")
else:
    print("   No transactions found!")

# Check task status - look for paid tasks
print("\n\n4. Checking task payment status:")
cursor.execute('SELECT COUNT(*) FROM tasks WHERE status = "paid"')
paid_count = cursor.fetchone()[0]

cursor.execute('SELECT COUNT(*) FROM tasks WHERE status = "completed"')
completed_count = cursor.fetchone()[0]

print(f"   Tasks with status 'paid': {paid_count}")
print(f"   Tasks with status 'completed': {completed_count}")

if paid_count > 0:
    cursor.execute('SELECT id, title, paid_at FROM tasks WHERE status = "paid" LIMIT 3')
    paid_tasks = cursor.fetchall()
    print(f"\n   Recent paid tasks:")
    for task_id, title, paid_at in paid_tasks:
        print(f"     Task {task_id}: {title}")
        print(f"       Paid at: {paid_at}")

conn.close()

print("\n" + "=" * 80)
print("SUMMARY")
print("=" * 80)
if paid_count == 0 and completed_count > 0:
    print("⚠️  ISSUE: Tasks are completed but NOT paid!")
    print("   Commission deduction likely hasn't happened yet")
    print("   (This is normal - poster needs to initiate payment)")
elif paid_count > 0:
    print("✅ Tasks have been paid")
    print("   Check if commission was deducted from helper wallets")
else:
    print("ℹ️  No tasks to test payment flow")
