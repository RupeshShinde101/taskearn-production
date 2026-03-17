#!/usr/bin/env python3
"""
Clear all wallet balances - reset to zero
No unverified payments should be in the system
"""

import os
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse

load_dotenv()

database_url = os.getenv('DATABASE_URL')
parsed_url = urlparse(database_url)
db_config = {
    'host': parsed_url.hostname,
    'port': parsed_url.port or 5432,
    'database': parsed_url.path.lstrip('/'),
    'user': parsed_url.username,
    'password': parsed_url.password
}

print("Connecting to database...")
conn = psycopg2.connect(**db_config)
cursor = conn.cursor()

print("Current balances:")
cursor.execute("""
    SELECT u.email, w.balance
    FROM wallets w
    JOIN users u ON w.user_id = u.id
    ORDER BY w.balance DESC
""")
for row in cursor.fetchall():
    print(f"  {row[0]}: {row[1]}")

print("\nResetting all wallets to 0...")
cursor.execute("""
    UPDATE wallets
    SET balance = 0, total_added = 0
""")

print("Deleting all unverified transactions...")
cursor.execute("""
    DELETE FROM wallet_transactions
    WHERE type IN ('topup', 'credit')
""")

conn.commit()

print("\nFinal balances:")
cursor.execute("""
    SELECT u.email, w.balance
    FROM wallets w
    JOIN users u ON w.user_id = u.id
    ORDER BY w.balance DESC
""")
for row in cursor.fetchall():
    print(f"  {row[0]}: {row[1]}")

print("\nDONE - All wallets reset to 0")
print("Only verified Razorpay payments will be credited from now on")

cursor.close()
conn.close()
