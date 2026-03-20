#!/usr/bin/env python3
"""
Debug wallet topup issues - Check for mismatches between notification amount and actual wallet balance
"""

import sqlite3
import os

# Check if database exists
db_path = os.path.join(os.path.dirname(__file__), 'backend', 'tasks.db')
if not os.path.exists(db_path):
    print(f"❌ Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("\n" + "="*70)
print("💰 WALLET TOPUP ISSUES DEBUG")
print("="*70)

# Check all wallet transactions of type 'razorpay_topup'
print("\n📋 Recent Razorpay Topup Transactions:")
cursor.execute('''
    SELECT w.user_id, wt.id, wt.type, wt.amount, wt.balance_after, wt.created_at, w.balance
    FROM wallet_transactions wt
    JOIN wallets w ON wt.wallet_id = w.id
    WHERE wt.type = 'razorpay_topup'
    ORDER BY wt.created_at DESC
    LIMIT 10
''')

topups = cursor.fetchall()
if topups:
    for topup in topups:
        user_id, tx_id, tx_type, amount, balance_after, created_at, current_balance = topup
        print(f"\n   User ID: {user_id}")
        print(f"   Transaction ID: {tx_id}")
        print(f"   Amount Topup: ₹{amount}")
        print(f"   Balance After TX: ₹{balance_after}")
        print(f"   Current Wallet Balance: ₹{current_balance}")
        print(f"   Date: {created_at}")
        
        if float(balance_after) != float(current_balance):
            print(f"   ⚠️  MISMATCH! Transaction says ₹{balance_after} but wallet shows ₹{current_balance}")
            print(f"   Difference: ₹{float(current_balance) - float(balance_after)}")
else:
    print("   No topup transactions found")

# Check all wallets
print("\n\n👥 All User Wallets:")
cursor.execute('''
    SELECT id, user_id, balance, total_added, total_earned
    FROM wallets
    ORDER BY user_id
''')

wallets = cursor.fetchall()
for wallet in wallets:
    wallet_id, user_id, balance, total_added, total_earned = wallet
    print(f"\n   User: {user_id}")
    print(f"   Current Balance: ₹{balance}")
    print(f"   Total Added (Topups): ₹{total_added}")
    print(f"   Total Earned (Tasks): ₹{total_earned}")
    print(f"   Expected Balance: ₹{float(total_added) + float(total_earned)}")
    
    expected = float(total_added) + float(total_earned)
    actual = float(balance)
    if abs(actual - expected) > 0.01:
        print(f"   ❌ BALANCE MISMATCH: ₹{actual} vs ₹{expected} (diff: ₹{actual - expected})")

print("\n" + "="*70)
conn.close()
