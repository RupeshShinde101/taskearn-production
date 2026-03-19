#!/usr/bin/env python3
"""
Check all wallet balances and recent transactions
"""

import sqlite3
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))
from database import get_db, dict_from_row

def check_wallets():
    """Display all wallets and their transactions"""
    
    print("\n" + "="*80)
    print("WALLET STATUS CHECK")
    print("="*80)
    
    try:
        with get_db() as (cursor, conn):
            # Get all wallets
            cursor.execute('''
                SELECT w.id, w.user_id, w.balance, w.total_added, w.total_spent, w.total_earned
                FROM wallets w
                ORDER BY w.created_at DESC
            ''')
            
            wallets = [dict_from_row(row) for row in cursor.fetchall()]
            
            if not wallets:
                print("❌ No wallets found")
                return
            
            print(f"\n📊 Found {len(wallets)} wallet(s):\n")
            
            for wallet in wallets:
                user_id = wallet.get('user_id')
                balance = float(wallet.get('balance', 0))
                total_added = float(wallet.get('total_added', 0))
                
                print(f"┌─ Wallet ID: {wallet.get('id')} | User: {user_id}")
                print(f"├─ Balance: ₹{balance:.2f}")
                print(f"├─ Total Added: ₹{total_added:.2f}")
                print(f"├─ Total Spent: ₹{wallet.get('total_spent', 0):.2f}")
                print(f"├─ Total Earned: ₹{wallet.get('total_earned', 0):.2f}")
                
                # Get recent transactions for this wallet
                cursor.execute('''
                    SELECT id, type, amount, balance_after, description, created_at
                    FROM wallet_transactions
                    WHERE user_id = ?
                    ORDER BY created_at DESC
                    LIMIT 10
                ''', (user_id,))
                
                transactions = [dict_from_row(row) for row in cursor.fetchall()]
                
                if transactions:
                    print(f"└─ Recent Transactions ({len(transactions)}):")
                    for i, t in enumerate(transactions, 1):
                        txn_type = t.get('type', 'unknown')
                        amount = float(t.get('amount', 0))
                        balance_after = float(t.get('balance_after', 0))
                        desc = t.get('description', '')
                        
                        print(f"   {i}. [{txn_type:15}] ₹{amount:10.2f} | Balance after: ₹{balance_after:10.2f}")
                        print(f"      {desc}")
                
                print()
    
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    print("="*80 + "\n")

if __name__ == '__main__':
    check_wallets()
