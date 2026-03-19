#!/usr/bin/env python3
"""
Check database content - users and tasks
"""

import sqlite3
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'backend'))
from database import get_db, dict_from_row

def check_db():
    """Display database status"""
    
    print("\n" + "="*80)
    print("DATABASE CONTENT CHECK")
    print("="*80)
    
    try:
        with get_db() as (cursor, conn):
            # Check users
            cursor.execute('SELECT COUNT(*) as count FROM users')
            user_count = cursor.fetchone()[0]
            print(f"\n👥 Users: {user_count}")
            
            if user_count > 0:
                cursor.execute('SELECT id, name, email FROM users LIMIT 5')
                for row in cursor.fetchall():
                    print(f"   - ID {row[0]}: {row[1]} ({row[2]})")
            
            # Check tasks
            cursor.execute('SELECT COUNT(*) as count FROM tasks')
            task_count = cursor.fetchone()[0]
            print(f"📋 Tasks: {task_count}")
            
            # Check wallets
            cursor.execute('SELECT COUNT(*) as count FROM wallets')
            wallet_count = cursor.fetchone()[0]
            print(f"💰 Wallets: {wallet_count}")
            
            # Check wallet transactions
            cursor.execute('SELECT COUNT(*) as count FROM wallet_transactions')
            txn_count = cursor.fetchone()[0]
            print(f"💳 Wallet Transactions: {txn_count}")
            
            # Check notifications
            cursor.execute('SELECT COUNT(*) as count FROM notifications')
            notif_count = cursor.fetchone()[0]
            print(f"🔔 Notifications: {notif_count}")
            
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
    
    print("="*80 + "\n")

if __name__ == '__main__':
    check_db()
