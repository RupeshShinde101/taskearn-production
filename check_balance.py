#!/usr/bin/env python3
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

conn = psycopg2.connect(**db_config)
cursor = conn.cursor()

print("Current Wallet Balances:")
print("=" * 60)
cursor.execute("""
    SELECT u.email, w.balance, w.total_added
    FROM wallets w
    JOIN users u ON w.user_id = u.id
    ORDER BY w.balance DESC
""")
for row in cursor.fetchall():
    print(f"{row[0]}: Balance = {row[1]}, Added = {row[2]}")

cursor.close()
conn.close()
