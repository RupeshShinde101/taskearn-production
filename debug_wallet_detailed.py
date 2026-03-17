#!/usr/bin/env python3
"""
Comprehensive wallet debug script to identify balance issues
"""

import os
import sys
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse

load_dotenv()

def debug_wallet():
    """Debug wallet balance issue"""
    
    # Get database URL
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        print("❌ DATABASE_URL not found in .env!")
        sys.exit(1)
    
    # Parse URL
    parsed_url = urlparse(database_url)
    db_config = {
        'host': parsed_url.hostname,
        'port': parsed_url.port or 5432,
        'database': parsed_url.path.lstrip('/'),
        'user': parsed_url.username,
        'password': parsed_url.password
    }
    
    print("🔗 Connecting to database...")
    
    try:
        conn = psycopg2.connect(**db_config)
        cursor = conn.cursor()
        print("✅ Connected!\n")
        
        # Step 1: Show all users
        print("=" * 70)
        print("STEP 1: ALL USERS IN SYSTEM")
        print("=" * 70)
        cursor.execute("SELECT id, email, name FROM users LIMIT 10")
        users = cursor.fetchall()
        if users:
            for user in users:
                print(f"  User ID: {user[0]}")
                print(f"    Email: {user[1]}")
                print(f"    Name: {user[2]}")
                print()
        
        # Step 2: Show all wallets
        print("=" * 70)
        print("STEP 2: ALL WALLETS IN DATABASE")
        print("=" * 70)
        cursor.execute("""
            SELECT id, user_id, balance, total_added, total_earned, total_spent, created_at
            FROM wallets
            ORDER BY created_at DESC
        """)
        wallets = cursor.fetchall()
        if wallets:
            for wallet in wallets:
                print(f"  Wallet ID: {wallet[0]}")
                print(f"    User ID: {wallet[1]}")
                print(f"    Balance: ₹{wallet[2]}")
                print(f"    Total Added (Razorpay): ₹{wallet[3]}")
                print(f"    Total Earned: ₹{wallet[4]}")
                print(f"    Total Spent: ₹{wallet[5]}")
                print(f"    Created: {wallet[6]}")
                print()
        else:
            print("  ❌ No wallets found!")
        
        # Step 3: Show all wallet transactions
        print("=" * 70)
        print("STEP 3: ALL WALLET TRANSACTIONS (LAST 20)")
        print("=" * 70)
        cursor.execute("""
            SELECT wallet_id, user_id, type, amount, balance_after, description, created_at
            FROM wallet_transactions
            ORDER BY created_at DESC
            LIMIT 20
        """)
        transactions = cursor.fetchall()
        if transactions:
            for txn in transactions:
                print(f"  Type: {txn[2].upper():15} | Amount: ₹{txn[3]:10} | After: ₹{txn[4]}")
                print(f"    Wallet ID: {txn[0]} | User ID: {txn[1]}")
                print(f"    Desc: {txn[5]}")
                print(f"    Time: {txn[6]}")
                print()
        else:
            print("  ❌ No transactions found!")
        
        # Step 4: Find the most recent added balance
        print("=" * 70)
        print("STEP 4: RECENT RAZORPAY TOP-UPS (LAST 5)")
        print("=" * 70)
        cursor.execute("""
            SELECT wt.wallet_id, wt.user_id, wt.type, wt.amount, wt.balance_after, wt.created_at,
                   w.balance as current_balance
            FROM wallet_transactions wt
            JOIN wallets w ON w.id = wt.wallet_id
            WHERE wt.type IN ('topup', 'credit')
            ORDER BY wt.created_at DESC
            LIMIT 5
        """)
        topups = cursor.fetchall()
        if topups:
            for topup in topups:
                print(f"  Amount Added: ₹{topup[3]}")
                print(f"    User ID: {topup[1]}")
                print(f"    Balance After Transaction: ₹{topup[4]}")
                print(f"    Current Wallet Balance: ₹{topup[6]}")
                print(f"    Time: {topup[5]}")
                if float(topup[4]) != float(topup[6]):
                    print(f"    ⚠️  MISMATCH! Transaction says ₹{topup[4]} but wallet shows ₹{topup[6]}")
                print()
        else:
            print("  ❌ No Razorpay top-ups found!")
        
        # Step 5: Check for payment records
        print("=" * 70)
        print("STEP 5: RAZORPAY PAYMENT RECORDS (LAST 10)")
        print("=" * 70)
        try:
            cursor.execute("""
                SELECT id, task_id, amount, status, razorpay_payment_id, created_at
                FROM payments
                ORDER BY created_at DESC
                LIMIT 10
            """)
            payments = cursor.fetchall()
            if payments:
                for payment in payments:
                    print(f"  Payment: ₹{payment[2]} | Status: {payment[3]}")
                    print(f"    Task ID: {payment[1]}")
                    print(f"    Razorpay ID: {payment[4]}")
                    print(f"    Time: {payment[5]}")
                    print()
            else:
                print("  (No payment records yet - Razorpay payments haven't been created)")
        except Exception as e:
            print(f"  (Payments table has different schema: {e})")
        
        # Step 6: Identify the logged-in user
        print("=" * 70)
        print("STEP 6: MOST RECENT USER (YOUR CURRENT SESSION)")
        print("=" * 70)
        cursor.execute("""
            SELECT id, email, name
            FROM users
            LIMIT 1
        """)
        current_user = cursor.fetchone()
        if current_user:
            user_id = current_user[0]
            print(f"  Your User ID: {user_id}")
            print(f"  Email: {current_user[1]}")
            print(f"  Name: {current_user[2]}")
            print()
            
            # Get this user's wallet
            print("=" * 70)
            print(f"STEP 7: YOUR WALLET (User {user_id})")
            print("=" * 70)
            cursor.execute(f"""
                SELECT id, balance, total_added, total_earned, total_spent
                FROM wallets
                WHERE user_id = %s
            """, (user_id,))
            wallet = cursor.fetchone()
            if wallet:
                print(f"  Wallet ID: {wallet[0]}")
                print(f"  Balance: ₹{wallet[1]}")
                print(f"  Total Added (Razorpay): ₹{wallet[2]}")
                print(f"  Total Earned: ₹{wallet[3]}")
                print(f"  Total Spent: ₹{wallet[4]}")
                print()
                
                # Get YOUR transactions
                print("=" * 70)
                print(f"STEP 8: YOUR TRANSACTIONS (ALL)")
                print("=" * 70)
                cursor.execute("""
                    SELECT type, amount, balance_after, description, created_at
                    FROM wallet_transactions
                    WHERE user_id = %s
                    ORDER BY created_at DESC
                """, (user_id,))
                your_txns = cursor.fetchall()
                if your_txns:
                    for txn in your_txns:
                        print(f"  {txn[0].upper():10} | ₹{txn[1]:10} | After: ₹{txn[2]} | {txn[3]}")
                        print(f"    Time: {txn[4]}")
                        print()
                else:
                    print("  (No transactions for this user)")
            else:
                print(f"  ❌ NO WALLET FOUND for user {user_id}!")
        
        # Step 9: Recommendation
        print("=" * 70)
        print("DIAGNOSIS")
        print("=" * 70)
        if wallets:
            total_balance = sum(float(w[2]) for w in wallets)
            if total_balance > 0:
                print(f"✅ System has ₹{total_balance} total across all wallets")
                print(f"✅ Razorpay payments ARE being saved to database")
                print(f"\n🔍 Possible issues:")
                print(f"  1. You're logged in as a DIFFERENT user account")
                print(f"  2. Balance was added to someone else's wallet")
                print(f"  3. Balance is there but not showing in UI")
                print(f"\nSOLUTION:")
                print(f"  - Make sure you're logged in with the same email")
                print(f"  - Check browser console (F12) for any errors")
                print(f"  - Try adding money AGAIN and watch the logs above")
            else:
                print(f"❌ No balance in any wallet - Razorpay payments not being recorded")
                print(f"\nSOLUTION:")
                print(f"  - Razorpay credentials might not be set on Railway")
                print(f"  - Payment verification endpoint might be failing")
                print(f"  - Check Railway logs for [WALLET] errors")
        else:
            print(f"❌ No wallets in system at all!")
            print(f"\nSOLUTION:")
            print(f"  - Create account and try to add money")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    debug_wallet()
