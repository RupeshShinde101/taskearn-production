#!/usr/bin/env python3
"""
Fix wallet amounts that were incorrectly stored due to paise/rupees bug
This corrects transactions where amount < 10 rupees but should be higher
"""

import sqlite3
import sys
import os
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))
from database import get_db, dict_from_row

def find_incorrect_transactions():
    """Find razor pay topup transactions that might be incorrect"""
    print("\n" + "="*80)
    print("WALLET CORRECTION TOOL - Find Incorrect Transactions")
    print("="*80 + "\n")
    
    try:
        with get_db() as (cursor, conn):
            # Look for razorpay_topup transactions with suspiciously low amounts
            # Amount between 0.1 and 9.9 suggests a paise/rupees issue
            cursor.execute('''
                SELECT wt.id, wt.wallet_id, wt.user_id, wt.amount, wt.balance_after, 
                       wt.created_at, u.name, u.email
                FROM wallet_transactions wt
                JOIN users u ON wt.user_id = u.id
                WHERE wt.type = 'razorpay_topup' 
                AND wt.amount > 0.1 
                AND wt.amount < 10
                ORDER BY wt.created_at DESC
            ''')
            
            results = cursor.fetchall()
            
            if not results:
                print("✅ No suspicious razorpay transactions found!")
                print("\n   This could mean:")
                print("   - The bug has been fixed in your deployment")
                print("   - No transactions have been made yet")
                print("   - The data doesn't exist on this database")
                return
            
            print(f"⚠️  Found {len(results)} potentially incorrect transaction(s):\n")
            
            for i, row in enumerate(results, 1):
                r = dict_from_row(row)
                txn_id = r.get('id')
                user_id = r.get('user_id')
                user_name = r.get('name')
                user_email = r.get('email')
                amount = float(r.get('amount', 0))
                balance_after = float(r.get('balance_after', 0))
                created_at = r.get('created_at')
                
                # The likely correct amount (multiply by 100)
                likely_correct = amount * 100
                
                print(f"{i}. Transaction ID: {txn_id}")
                print(f"   User: {user_name} ({user_email})")
                print(f"   Current: ₹{amount:.4f} (likely should be ₹{likely_correct:.2f})")
                print(f"   Balance after: ₹{balance_after}")
                print(f"   Date: {created_at}")
                print()
            
            # Ask if user wants to fix any
            if input("\nDo you want to fix any transactions? (y/n): ").lower() != 'y':
                print("\n✅ No changes made")
                return
            
            fix_transactions(results)
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()


def fix_transactions(results):
    """Fix the selected transactions"""
    print("\n" + "-"*80)
    print("CORRECTION PROCESS")
    print("-"*80 + "\n")
    
    try:
        corrections = []
        
        for i, row in enumerate(results, 1):
            r = dict_from_row(row)
            txn_id = r.get('id')
            user_id = r.get('user_id')
            amount = float(r.get('amount', 0))
            wallet_id = r.get('wallet_id')
            
            print(f"{i}. {r.get('name')}: ₹{amount} → ₹{amount * 100}? (y/n): ", end='')
            
            if input().lower() == 'y':
                corrections.append({
                    'txn_id': txn_id,
                    'user_id': user_id,
                    'wallet_id': wallet_id,
                    'old_amount': amount,
                    'new_amount': amount * 100,
                    'difference': (amount * 100) - amount
                })
        
        if not corrections:
            print("\n✅ No corrections selected")
            return
        
        print(f"\n🔄 Applying {len(corrections)} correction(s)...")
        
        with get_db() as (cursor, conn):
            for correction in corrections:
                txn_id = correction['txn_id']
                new_amount = correction['new_amount']
                difference = correction['difference']
                user_id = correction['user_id']
                wallet_id = correction['wallet_id']
                
                # Update transaction amount
                cursor.execute('''
                    UPDATE wallet_transactions
                    SET amount = ?
                    WHERE id = ?
                ''', (new_amount, txn_id))
                
                # Update wallet balance to add the difference
                cursor.execute('''
                    UPDATE wallets
                    SET balance = balance + ?,
                        total_added = total_added + ?
                    WHERE id = ?
                ''', (difference, difference, wallet_id))
                
                # Record adjustment transaction
                now = datetime.utcnow().isoformat() + 'Z'
                cursor.execute('''
                    INSERT INTO wallet_transactions (
                        wallet_id, user_id, type, amount, balance_after, 
                        description, created_at
                    )
                    SELECT ?, ?, 'correction', ?, balance, ?, ?
                    FROM wallets
                    WHERE id = ?
                ''', (wallet_id, user_id, difference,
                      f'Correction for transaction {txn_id}: ₹{correction["old_amount"]:.2f} → ₹{correction["new_amount"]:.2f}',
                      now, wallet_id))
                
                print(f"✅ Fixed {correction['user_id']}: ₹{correction['old_amount']:.2f} → ₹{correction['new_amount']:.2f} (+₹{difference:.2f})")
            
            conn.commit()
            print(f"\n✅ All corrections applied successfully!")
    
    except Exception as e:
        print(f"❌ Error applying corrections: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    find_incorrect_transactions()
