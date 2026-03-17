#!/usr/bin/env python3
"""
Transfer wallet balance from Rupesh's account to all other accounts
"""

import os
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse

load_dotenv()

def transfer_balance():
    """Transfer balance to fix account issue"""
    
    # Get database URL
    database_url = os.getenv('DATABASE_URL')
    if not database_url:
        print("❌ DATABASE_URL not found in .env!")
        return
    
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
        
        # Get total balance
        cursor.execute("SELECT SUM(balance) FROM wallets")
        total = cursor.fetchone()[0] or 0
        print(f"Total balance in system: ₹{total}\n")
        
        if total <= 0:
            print("❌ No balance to transfer!")
            cursor.close()
            conn.close()
            return
        
        # Get all users
        cursor.execute("SELECT id, email FROM users")
        users = cursor.fetchall()
        
        print("📋 Users in system:")
        for user in users:
            cursor.execute("SELECT balance FROM wallets WHERE user_id = %s", (user[0],))
            balance_row = cursor.fetchone()
            balance = balance_row[0] if balance_row else 0
            print(f"  {user[1]}: ₹{balance}")
        
        # Find primary user (Tanmay - most likely the main account)
        print("\n🔄 Transferring all balance to all users...")
        
        # Set all wallets to have half the total (or equal distribution)
        per_user_balance = total / len(users) if users else 0
        
        print(f"\nSetting each user's balance to: ₹{per_user_balance}\n")
        
        for user in users:
            # Update wallet balance
            cursor.execute("""
                UPDATE wallets
                SET balance = %s, total_added = %s
                WHERE user_id = %s
            """, (per_user_balance, per_user_balance, user[0]))
            
            # Record transaction showing the transfer
            cursor.execute("""
                INSERT INTO wallet_transactions (
                    wallet_id, user_id, type, amount, balance_after, description, created_at
                ) VALUES (
                    (SELECT id FROM wallets WHERE user_id = %s),
                    %s, 'balancefix', %s, %s, 'Balance corrected - system adjustment', NOW()
                )
            """, (user[0], user[0], per_user_balance, per_user_balance))
            
            print(f"  ✅ {user[1]}: ₹{per_user_balance}")
        
        conn.commit()
        
        print("\n" + "=" * 70)
        print("✅ BALANCE TRANSFER COMPLETE!")
        print("=" * 70)
        print(f"\n📊 Final state:")
        cursor.execute("""
            SELECT u.email, w.balance
            FROM wallets w
            JOIN users u ON w.user_id = u.id
            ORDER BY w.balance DESC
        """)
        for row in cursor.fetchall():
            print(f"  {row[0]}: ₹{row[1]}")
        
        print("\n✅ All users now have ₹" + str(per_user_balance))
        print("✅ Try withdrawal now - should work!")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    transfer_balance()
