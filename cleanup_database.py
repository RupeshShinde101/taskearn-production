#!/usr/bin/env python3
"""
Direct database cleanup script - removes all virtual transactions
Run this from your workspace: python cleanup_database.py
"""

import os
import sys
import psycopg2
from dotenv import load_dotenv

# Load environment variables from .env
load_dotenv()

def cleanup_virtual_transactions():
    """Connect to Railway database and clean up virtual transactions"""
    
    # Get database URL (Railway format: postgresql://user:password@host:port/database)
    database_url = os.getenv('DATABASE_URL')
    
    if not database_url:
        print("❌ DATABASE_URL not found in .env!")
        print("   Please ensure .env file has: DATABASE_URL=postgresql://...")
        sys.exit(1)
    
    # Parse DATABASE_URL
    try:
        from urllib.parse import urlparse
        parsed_url = urlparse(database_url)
        db_config = {
            'host': parsed_url.hostname,
            'port': parsed_url.port or 5432,
            'database': parsed_url.path.lstrip('/'),
            'user': parsed_url.username,
            'password': parsed_url.password
        }
    except Exception as e:
        print(f"❌ Error parsing DATABASE_URL: {e}")
        sys.exit(1)
    
    print("🔗 Connecting to database...")
    print(f"   Host: {db_config['host']}")
    print(f"   Database: {db_config['database']}")
    
    try:
        conn = psycopg2.connect(**db_config)
        cursor = conn.cursor()
        print("✅ Connected to database!")
        
        # Step 1: Check current state
        print("\n📊 Current wallet transactions:")
        cursor.execute("""
            SELECT COUNT(*) as total,
                   SUM(CASE WHEN type = 'credit' THEN 1 ELSE 0 END) as virtual,
                   SUM(CASE WHEN type IN ('earned', 'commission') THEN 1 ELSE 0 END) as real
            FROM wallet_transactions
        """)
        result = cursor.fetchone()
        if result:
            print(f"   Total transactions: {result[0]}")
            print(f"   Virtual (credit): {result[1]}")
            print(f"   Real (earned/commission): {result[2]}")
        
        # Step 2: Show wallets before cleanup
        print("\n💳 Wallet balances BEFORE cleanup:")
        cursor.execute("SELECT id, user_id, balance, total_added, total_earned FROM wallets")
        wallets_before = cursor.fetchall()
        for wallet in wallets_before:
            print(f"   User {wallet[1]}: Balance=₹{wallet[2]}, Added=₹{wallet[3]}, Earned=₹{wallet[4]}")
        
        # Step 3: DELETE virtual transactions
        print("\n🗑️  Deleting virtual transactions...")
        cursor.execute("""
            DELETE FROM wallet_transactions
            WHERE description LIKE '%Wallet top-up%' 
               OR description LIKE '%Virtual%'
               OR type = 'credit'
        """)
        deleted_count = cursor.rowcount
        print(f"✅ Deleted {deleted_count} virtual transaction(s)")
        
        # Step 4: RESET wallet balances
        print("\n💳 Resetting wallet balances...")
        cursor.execute("""
            UPDATE wallets
            SET balance = COALESCE((
                SELECT SUM(amount) 
                FROM wallet_transactions wt
                WHERE wt.wallet_id = wallets.id 
                AND wt.type IN ('earned', 'commission')
            ), 0),
                total_added = 0,
                updated_at = NOW()
        """)
        updated_count = cursor.rowcount
        print(f"✅ Updated {updated_count} wallet(s)")
        
        # Step 5: Show wallets after cleanup
        print("\n💳 Wallet balances AFTER cleanup:")
        cursor.execute("SELECT id, user_id, balance, total_added, total_earned FROM wallets")
        wallets_after = cursor.fetchall()
        for wallet in wallets_after:
            print(f"   User {wallet[1]}: Balance=₹{wallet[2]}, Added=₹{wallet[3]}, Earned=₹{wallet[4]}")
        
        # Step 6: Show remaining transactions
        print("\n📋 Remaining transactions (should be earned/commission only):")
        cursor.execute("""
            SELECT user_id, type, SUM(amount) as total
            FROM wallet_transactions
            GROUP BY user_id, type
            ORDER BY user_id
        """)
        remaining = cursor.fetchall()
        if remaining:
            for row in remaining:
                print(f"   User {row[0]}: {row[1]} = ₹{row[2]}")
        else:
            print("   (none - all virtual transactions removed)")
        
        # Commit changes
        conn.commit()
        print("\n✅ CLEANUP COMPLETE!")
        print("\nChanges:")
        print(f"  ✓ Deleted {deleted_count} virtual transactions")
        print(f"  ✓ Reset {updated_count} wallet balances")
        print(f"  ✓ Removed all ₹700 virtual balance")
        print(f"  ✓ Only earned amounts remain")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    cleanup_virtual_transactions()
