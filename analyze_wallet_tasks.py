#!/usr/bin/env python3
import sqlite3
import os

db_file = 'backend/taskearn.db'

if os.path.exists(db_file):
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    print("\n" + "="*80)
    print("📊 WALLET & TASK VALUATION ANALYSIS")
    print("="*80)
    
    # Check wallets
    print("\n💰 WALLETS:")
    cursor.execute("SELECT id, user_id, balance, total_added, total_earned FROM wallets ORDER BY id")
    wallets = cursor.fetchall()
    for w in wallets:
        wallet_id, user_id, balance, total_added, total_earned = w
        print(f"\n  Wallet {wallet_id}: User {user_id}")
        print(f"    Current Balance: ₹{balance:.2f}")
        print(f"    Total Added (Topups): ₹{total_added:.2f}")
        print(f"    Total Earned: ₹{total_earned:.2f}")
        print(f"    Expected: {total_added:.2f} + {total_earned:.2f} = ₹{float(total_added) + float(total_earned):.2f}")
        
        if float(balance) != float(total_added) + float(total_earned):
            discrepancy = float(balance) - (float(total_added) + float(total_earned))
            print(f"    ⚠️  DISCREPANCY: ₹{discrepancy:.2f}")
    
    # Check tasks with pricing
    print("\n\n📋 TASKS & PRICING:")
    cursor.execute('''
        SELECT 
            id, title, price, posted_by, accepted_by, status, created_at 
        FROM tasks 
        ORDER BY created_at DESC
    ''')
    
    tasks = cursor.fetchall()
    for task in tasks:
        task_id, title, price, posted_by, accepted_by, status, created_at = task
        print(f"\n  Task {task_id}: {title}")
        print(f"    Posted by: {posted_by}")
        print(f"    Accepted by: {accepted_by}")
        print(f"    Status: {status}")
        print(f"    Price in DB: ₹{price}")
        print(f"    Created: {created_at}")
        
        # Check if there are any payments for this task
        cursor.execute("SELECT id, amount, status FROM payments WHERE task_id = ?", (task_id,))
        payments = cursor.fetchall()
        if payments:
            print(f"    💳 Payments:")
            for pay in payments:
                pay_id, pay_amount, pay_status = pay
                print(f"      Payment {pay_id}: ₹{pay_amount} ({pay_status})")
    
    # Check users
    print("\n\n👥 USERS:")
    cursor.execute('''
        SELECT id, name, email, total_earnings, is_suspended 
        FROM users 
        ORDER BY total_earnings DESC
    ''')
    
    users = cursor.fetchall()
    for user in users:
        user_id, name, email, total_earnings, is_suspended = user
        print(f"\n  {name} ({user_id})")
        print(f"    Email: {email}")
        print(f"    Total Earnings: ₹{total_earnings:.2f}")
        if is_suspended:
            print(f"    ⚠️  SUSPENDED")
    
    conn.close()
    print("\n" + "="*80)
else:
    print(f"❌ Database not found: {db_file}")
