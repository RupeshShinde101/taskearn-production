#!/usr/bin/env python3
"""
Fix wallet balance by distributing equally to all users
"""

import os
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse
import datetime

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

print("Connecting...")
conn = psycopg2.connect(**db_config)
cursor = conn.cursor()

# Get total balance
cursor.execute("SELECT SUM(balance) FROM wallets")
total = cursor.fetchone()[0] or 0
print(f"Total balance: {total}")

# Get all users
cursor.execute("SELECT id FROM users")
user_ids = [row[0] for row in cursor.fetchall()]
print(f"Total users: {len(user_ids)}")

# Per-user balance
per_user = total / len(user_ids) if user_ids else 0
print(f"Balance per user: {per_user}")

# Step 1: Ensure all users have wallets
for user_id in user_ids:
    cursor.execute("SELECT id FROM wallets WHERE user_id = %s", (user_id,))
    if not cursor.fetchone():
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        cursor.execute("""
            INSERT INTO wallets (user_id, balance, total_added, total_earned, total_spent, total_cashback, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (user_id, 0, 0, 0, 0, 0, now))
        print(f"Created wallet for user {user_id}")

conn.commit()

# Step 2: Update all wallets to have equal share
for user_id in user_ids:
    cursor.execute("""
        UPDATE wallets
        SET balance = %s, total_added = %s
        WHERE user_id = %s
    """, (per_user, per_user, user_id))
    print(f"Set {user_id} balance to {per_user}")

conn.commit()

print("\nFINAL BALANCES:")
print("=" * 60)  
cursor.execute("""
    SELECT u.email, w.balance
    FROM wallets w
    JOIN users u ON w.user_id = u.id
    ORDER BY w.balance DESC
""")
for row in cursor.fetchall():
    print(f"{row[0]}: {row[1]}")

cursor.close()
conn.close()

print("\nDone! Try withdrawal now.")
