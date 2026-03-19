#!/usr/bin/env python3
"""
Check recent wallet transactions for debugging
"""

import sqlite3
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))
from database import get_db, dict_from_row

def check_recent_transactions():
    """Display recent wallet transactions"""
    
    print("\n" + "="*80)
    print("RECENT WALLET TRANSACTIONS DEBUG")
    print("="*80)
    
    try:
        with get_db() as (cursor, conn):
            # Get all users with wallets
            cursor.execute('''
                SELECT u.id as user_id, u.name, u.email, w.id as wallet_id, w.balance, w.total_added
                FROM users u
                LEFT JOIN wallets w ON u.id = w.user_id
                WHERE w.id IS NOT NULL
                ORDER BY w.created_at DESC
            ''')
            
            rows = cursor.fetchall()
            
            if not rows:
                print("❌ No wallets found in database")
                return
            
            print(f"\n📊 Found {len(rows)} wallet(s):\n")
            
            for row in rows:
                row_dict = dict_from_row(row)
                user_id = row_dict.get('user_id')
                user_name = row_dict.get('name')
                user_email = row_dict.get('email')
                wallet_id = row_dict.get('wallet_id')  # This is the wallet id from JOIN
                balance = float(row_dict.get('balance', 0))
                total_added = float(row_dict.get('total_added', 0))
                
                print(f"👤 {user_name} ({user_email})")
                print(f"   Wallet ID: {wallet_id}")
                print(f"   Current Balance: ₹{balance:.2f}")
                print(f"   Total Added: ₹{total_added:.2f}")
                
                # Get recent transactions
                cursor.execute('''
                    SELECT id, type, amount, balance_after, description, created_at
                    FROM wallet_transactions
                    WHERE wallet_id = ?
                    ORDER BY created_at DESC
                    LIMIT 5
                ''', (wallet_id,))
                
                transactions = [dict_from_row(t) for t in cursor.fetchall()]
                
                if transactions:
                    print(f"   Recent Transactions ({len(transactions)}):")
                    for t in transactions:
                        txn_id = t.get('id')
                        txn_type = t.get('type')
                        amount = float(t.get('amount', 0))
                        balance_after = float(t.get('balance_after', 0))
                        desc = t.get('description', '')
                        
                        print(f"     - [{txn_type:15}] ₹{amount:8.2f} | Balance: ₹{balance_after:8.2f} | {desc}")
                else:
                    print(f"   No transactions found")
                
                print()
    
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    print("="*80 + "\n")

if __name__ == '__main__':
    check_recent_transactions()
