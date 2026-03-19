#!/usr/bin/env python3
"""
Script to fix wallet balance for 100 rupees deposit showing as 1 rupee
This corrects the database records from the previous payment issue
"""

import sqlite3
import sys
import os
from datetime import datetime, timezone

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))

from database import get_db, dict_from_row

def fix_wallet_100_rupees():
    """Find and fix the 100 rupees deposit that was showing as 1 rupee"""
    
    print("\n" + "="*70)
    print("WALLET FIX: 100 Rupees Deposit Correction")
    print("="*70)
    
    try:
        with get_db() as (cursor, conn):
            # Find all razorpay_topup transactions with 1 rupee (the incorrect amount)
            print("\n[STEP 1] Searching for incorrect transactions (1 rupee deposits)...")
            cursor.execute('''
                SELECT wt.id, wt.user_id, wt.amount, wt.balance_after, 
                       wt.description, wt.created_at, w.balance
                FROM wallet_transactions wt
                JOIN wallets w ON w.id = wt.wallet_id
                WHERE wt.type = 'razorpay_topup' AND wt.amount = 1.0
                ORDER BY wt.created_at DESC
                LIMIT 10
            ''')
            
            incorrect_txns = [dict_from_row(row) for row in cursor.fetchall()]
            
            if not incorrect_txns:
                print("❌ No incorrect 1 rupee transactions found")
                return False
            
            print(f"✅ Found {len(incorrect_txns)} incorrect transaction(s):")
            for i, txn in enumerate(incorrect_txns, 1):
                print(f"\n  {i}. Transaction ID: {txn.get('id')}")
                print(f"     User ID: {txn.get('user_id')}")
                print(f"     Current Amount: ₹{txn.get('amount')}")
                print(f"     Should be: ₹100.00")
                print(f"     Created: {txn.get('created_at')}")
            
            # Ask user which one to fix
            if len(incorrect_txns) > 1:
                choice = input("\n📝 Enter transaction number to fix (1-{}): ".format(len(incorrect_txns)))
                try:
                    choice = int(choice) - 1
                    if choice < 0 or choice >= len(incorrect_txns):
                        print("❌ Invalid choice")
                        return False
                except ValueError:
                    print("❌ Invalid input")
                    return False
            else:
                choice = 0
            
            txn = incorrect_txns[choice]
            user_id = txn.get('user_id')
            wallet_id = None
            
            # Get wallet ID
            cursor.execute('SELECT id FROM wallets WHERE user_id = ?', (user_id,))
            wallet_row = cursor.fetchone()
            if wallet_row:
                wallet_id = dict_from_row(wallet_row).get('id')
            
            print(f"\n[STEP 2] Fixing wallet for user {user_id}...")
            
            # Get current wallet balance
            cursor.execute('SELECT balance, total_added FROM wallets WHERE user_id = ?', (user_id,))
            wallet_row = cursor.fetchone()
            wallet = dict_from_row(wallet_row)
            
            current_balance = float(wallet.get('balance', 0))
            total_added = float(wallet.get('total_added', 0))
            
            print(f"  Current wallet balance: ₹{current_balance:.2f}")
            print(f"  Total added: ₹{total_added:.2f}")
            
            # Calculate correction
            difference = 100.0 - 1.0  # The difference between correct and incorrect
            new_balance = current_balance + difference
            new_total_added = total_added + difference
            
            print(f"\n[STEP 3] Applying corrections...")
            print(f"  Difference to add: ₹{difference:.2f}")
            print(f"  New wallet balance: ₹{new_balance:.2f}")
            print(f"  New total added: ₹{new_total_added:.2f}")
            
            # Confirm before updating
            confirm = input(f"\n🔄 Do you want to apply this fix? (yes/no): ").lower()
            if confirm != 'yes':
                print("❌ Fix cancelled")
                return False
            
            # Update wallet balance
            cursor.execute('''
                UPDATE wallets 
                SET balance = ?, total_added = ?
                WHERE user_id = ?
            ''', (new_balance, new_total_added, user_id))
            
            # Update the transaction amount from 1 to 100
            cursor.execute('''
                UPDATE wallet_transactions 
                SET amount = 100.0, balance_after = ?
                WHERE id = ?
            ''', (new_balance, txn.get('id')))
            
            # Add correction transaction record
            now = datetime.now(timezone.utc).isoformat()
            cursor.execute('''
                INSERT INTO wallet_transactions (wallet_id, user_id, type, amount, balance_after, description, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (wallet_id, user_id, 'correction', difference, new_balance,
                  'Correction: Fixed 100 rupees deposit (was showing as 1 rupee)', now))
            
            conn.commit()
            
            print(f"\n✅ [STEP 4] Fix applied successfully!")
            print(f"  ✓ Wallet balance updated: ₹{current_balance:.2f} → ₹{new_balance:.2f}")
            print(f"  ✓ Transaction amount corrected: ₹1.00 → ₹100.00")
            print(f"  ✓ Correction record added")
            
            # Verify the fix
            print(f"\n[STEP 5] Verifying the fix...")
            cursor.execute('SELECT balance, total_added FROM wallets WHERE user_id = ?', (user_id,))
            updated_wallet = dict_from_row(cursor.fetchone())
            
            print(f"  Wallet balance (verified): ₹{updated_wallet.get('balance', 0):.2f}")
            print(f"  Total added (verified): ₹{updated_wallet.get('total_added', 0):.2f}")
            
            # Show recent transactions
            cursor.execute('''
                SELECT type, amount, balance_after, description, created_at
                FROM wallet_transactions
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT 5
            ''', (user_id,))
            
            recent = [dict_from_row(row) for row in cursor.fetchall()]
            
            print(f"\n[Recent Transactions]")
            for i, t in enumerate(recent, 1):
                print(f"  {i}. {t.get('type'):15} | ₹{t.get('amount'):10.2f} | Balance: ₹{t.get('balance_after', 0):.2f}")
                print(f"     {t.get('description')}")
            
            print("\n" + "="*70)
            print("✅ WALLET FIX COMPLETE!")
            print("="*70 + "\n")
            
            return True
            
    except Exception as e:
        print(f"\n❌ Error during fix: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    success = fix_wallet_100_rupees()
    sys.exit(0 if success else 1)
