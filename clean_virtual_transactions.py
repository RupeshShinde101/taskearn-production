#!/usr/bin/env python3
"""
Clean up virtual transaction records from database.
Removes all unverified/virtual transactions and restores wallet balances.
"""

import os
import sys
import psycopg2
from dotenv import load_dotenv

load_dotenv()

# Database connection
try:
    conn = psycopg2.connect(
        host=os.getenv('DATABASE_HOST', 'localhost'),
        port=os.getenv('DATABASE_PORT', 5432),
        database=os.getenv('DATABASE_NAME'),
        user=os.getenv('DATABASE_USER'),
        password=os.getenv('DATABASE_PASSWORD')
    )
    cursor = conn.cursor()
    print("✅ Connected to database")
except Exception as e:
    print(f"❌ Database connection failed: {e}")
    sys.exit(1)

try:
    # Step 1: Identify virtual transactions (those without Razorpay references)
    print("\n📋 Identifying virtual transactions...")
    cursor.execute("""
        SELECT id, user_id, wallet_id, type, amount, description, created_at
        FROM wallet_transactions
        WHERE description LIKE '%Wallet top-up%' 
           OR description LIKE '%Virtual%'
        ORDER BY created_at DESC
    """)
    
    virtual_txns = cursor.fetchall()
    print(f"Found {len(virtual_txns)} virtual transaction(s)")
    
    if len(virtual_txns) > 0:
        print("\n📝 Virtual transactions to be deleted:")
        total_amount = 0
        for txn in virtual_txns:
            print(f"  - ID: {txn[0]}, User: {txn[1]}, Amount: ₹{txn[4]}, Desc: {txn[5]}")
            total_amount += txn[4]
        
        print(f"\n💰 Total virtual amount to be removed: ₹{total_amount}")
        
        # Step 2: Delete virtual transactions
        print("\n🗑️  Deleting virtual transactions...")
        cursor.execute("""
            DELETE FROM wallet_transactions
            WHERE description LIKE '%Wallet top-up%' 
               OR description LIKE '%Virtual%'
        """)
        deleted_count = cursor.rowcount
        print(f"✅ Deleted {deleted_count} virtual transaction(s)")
        
        # Step 3: Revert wallet balances
        print("\n💳 Reverting wallet balances...")
        cursor.execute("""
            SELECT DISTINCT user_id FROM wallets
        """)
        
        users = cursor.fetchall()
        for user_row in users:
            user_id = user_row[0]
            
            # Get all remaining transactions for this user
            cursor.execute("""
                SELECT SUM(amount) FROM wallet_transactions
                WHERE user_id = %s AND type IN ('earned', 'commission')
            """, (user_id,))
            
            result = cursor.fetchone()
            total_earned = result[0] if result[0] else 0
            
            # Update wallet balance to only include earned amounts
            cursor.execute("""
                UPDATE wallets
                SET balance = %s, 
                    total_added = 0,
                    updated_at = NOW()
                WHERE user_id = %s
            """, (total_earned, user_id))
            
            print(f"  ✅ User {user_id}: balance reset to ₹{total_earned}")
        
        conn.commit()
        print("\n✅ Database cleanup completed successfully!")
        print("   - All virtual transactions removed")
        print("   - Wallet balances reverted to earned amounts only")
        print("   - Ready for Razorpay-only transactions")
        
    else:
        print("✅ No virtual transactions found - database is clean!")
        conn.commit()

except Exception as e:
    print(f"❌ Error during cleanup: {e}")
    conn.rollback()
    sys.exit(1)
finally:
    cursor.close()
    conn.close()
