#!/usr/bin/env python3
"""
Debug task pricing and helper earnings issues
"""

import sqlite3
import os

db_path = os.path.join(os.path.dirname(__file__), 'backend', 'tasks.db')
if not os.path.exists(db_path):
    print(f"❌ Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("\n" + "="*80)
print("📊 TASK PRICING & HELPER EARNINGS DEBUG")
print("="*80)

# Check all tasks and their prices
print("\n📋 Recent Tasks:")
cursor.execute('''
    SELECT id, title, price, posted_by, accepted_by, status, created_at
    FROM tasks
    ORDER BY created_at DESC
    LIMIT 10
''')

tasks = cursor.fetchall()
for task in tasks:
    task_id, title, price, posted_by, accepted_by, status, created_at = task
    print(f"\n   Task ID: {task_id}")
    print(f"   Title: {title}")
    print(f"   Price: ₹{price}")
    print(f"   Posted By: {posted_by}")
    print(f"   Accepted By: {accepted_by}")
    print(f"   Status: {status}")
    print(f"   Created: {created_at}")
    
    if status in ['completed', 'paid']:
        # Calculate commissions
        helper_commission = float(price) * 0.12  # 12%
        poster_fee = float(price) * 0.05  # 5%
        helper_net = float(price) - helper_commission
        
        print(f"   💼 Commission Breakdown:")
        print(f"      Helper Commission (12%): ₹{helper_commission:.2f}")
        print(f"      Poster Fee (5%): ₹{poster_fee:.2f}")
        print(f"      Helper Net Earnings: ₹{helper_net:.2f}")
        
        # Check wallet transactions for this task
        cursor.execute('''
            SELECT user_id, type, amount, balance_after, description
            FROM wallet_transactions
            WHERE task_id = ?
            ORDER BY created_at
        ''', (task_id,))
        
        transactions = cursor.fetchall()
        if transactions:
            print(f"   📝 Wallet Transactions:")
            for tx in transactions:
                tx_user, tx_type, tx_amount, tx_balance, tx_desc = tx
                print(f"      User {tx_user}: {tx_type:12} {tx_amount:+10.2f} → Balance: ₹{tx_balance:.2f}")
                print(f"                 {tx_desc}")
        else:
            print(f"   ⚠️  No wallet transactions found for task {task_id}")

# Check wallet transactions summary by task
print("\n\n💰 Wallet Transactions Summary by Task:")
cursor.execute('''
    SELECT task_id, type, SUM(amount) as total_amount, COUNT(*) as count
    FROM wallet_transactions
    WHERE task_id IS NOT NULL
    GROUP BY task_id, type
    ORDER BY task_id, type
''')

summary = cursor.fetchall()
for summary_row in summary:
    task_id, tx_type, total_amount, count = summary_row
    if task_id:
        print(f"\n   Task {task_id} - {tx_type}: {count} transactions, Total: ₹{total_amount:.2f}")

print("\n" + "="*80)
conn.close()
