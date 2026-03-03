#!/usr/bin/env python3
"""
Test Railway PostgreSQL Connection
"""

import os
import sys
from dotenv import load_dotenv

# Load environment variables from .env
load_dotenv()

DATABASE_URL = os.environ.get('DATABASE_URL')

if not DATABASE_URL:
    print("❌ DATABASE_URL not found in .env file")
    sys.exit(1)

print(f"🔍 Testing Railway PostgreSQL Connection...")
print(f"📍 URL: {DATABASE_URL[:50]}...")

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    
    # Connect to the database
    conn = psycopg2.connect(DATABASE_URL)
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    # Test query
    cursor.execute("SELECT version();")
    db_version = cursor.fetchone()
    
    print("✅ Connection Successful!")
    print(f"📦 Database Version: {db_version['version']}")
    
    # Get database info
    cursor.execute("""
        SELECT datname FROM pg_database WHERE datname = 'railway';
    """)
    db_info = cursor.fetchone()
    
    if db_info:
        print(f"📊 Database: {db_info['datname']}")
    
    # Close connection
    cursor.close()
    conn.close()
    
    print("\n✨ Railway PostgreSQL is ready to use!")
    
except ImportError:
    print("❌ psycopg2 not installed")
    print("   Run: pip install psycopg2-binary")
    sys.exit(1)
    
except psycopg2.OperationalError as e:
    print(f"❌ Connection Failed: {e}")
    sys.exit(1)
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
